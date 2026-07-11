;;; worker-pool-test.el --- Focused tests for the packaged Anvil worker pool -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'ert)
(require 'anvil-worker)

(ert-deftest anvil-worker-health-retries-an-already-dead-worker ()
  "A dead-to-dead health tick retries spawning without logging a transition."
  (let ((worker (list :name "anvil-worker-read-test"
                      :lane :read
                      :last-state 'dead))
        (spawn-count 0)
        logs)
    (cl-letf (((symbol-function 'anvil-worker--worker-alive-p)
               (lambda (_worker) nil))
              ((symbol-function 'anvil-worker--quick-alive-p)
               (lambda (_worker) nil))
              ((symbol-function 'anvil-worker--spawn-worker)
               (lambda (_worker) (cl-incf spawn-count)))
              ((symbol-function 'anvil-worker--log)
               (lambda (&rest entry) (push entry logs))))
      (anvil-worker--health-check-one worker))
    (should (= spawn-count 1))
    (should-not logs)
    (should (eq (plist-get worker :last-state) 'dead))))

(ert-deftest anvil-worker-kill-clears-all-owned-and-grace-state ()
  "An intentional pool kill forgets every owned process and spawn grace."
  (let ((anvil-worker--spawn-times (make-hash-table :test #'equal))
        (anvil-worker--owned-processes (make-hash-table :test #'equal))
        (worker (list :name "anvil-worker-read-test" :lane :read)))
    (puthash "anvil-worker-read-test" 1.0 anvil-worker--spawn-times)
    (puthash "discarded-worker" 2.0 anvil-worker--spawn-times)
    (puthash "discarded-worker" 'not-a-process anvil-worker--owned-processes)
    (cl-letf (((symbol-function 'anvil-worker--map-pool)
               (lambda (function) (funcall function worker)))
              ((symbol-function 'anvil-worker--worker-alive-p)
               (lambda (_worker) nil)))
      (anvil-worker-kill))
    (should (= (hash-table-count anvil-worker--spawn-times) 0))
    (should (= (hash-table-count anvil-worker--owned-processes) 0))))

(ert-deftest anvil-worker-quick-check-documents-the-direct-probe ()
  "The packaged documentation must describe its patched liveness mechanism."
  (should (string-match-p
           "direct connect probe on the cached socket path"
           (documentation 'anvil-worker--quick-alive-p)))
  (should-not (string-search
               "file + PID only, no probe"
               (documentation 'anvil-worker--spawn-worker))))

(ert-deftest anvil-worker-spawn-grace-does-not-slide ()
  "A suppressed spawn must not extend the grace window forever."
  (let ((anvil-worker--spawn-times (make-hash-table :test #'equal))
        (anvil-worker--owned-processes (make-hash-table :test #'equal))
        (anvil-worker-init-file "/tmp/anvil-worker-test-init.el")
        (anvil-worker-spawn-grace 45)
        (worker (list :name "anvil-worker-read-test"
                      :lane :read
                      :server-file "/tmp/anvil-worker-read-test"))
        (now 0.0)
        (spawn-count 0))
    (unwind-protect
        (cl-letf (((symbol-function 'float-time)
                   (lambda (&optional _time) now))
                  ((symbol-function 'anvil-worker--quick-alive-p)
                   (lambda (_worker) nil))
                  ((symbol-function 'start-process)
                   (lambda (&rest _args)
                     (cl-incf spawn-count)
                     (intern (format "fake-process-%d" spawn-count))))
                  ((symbol-function 'set-process-query-on-exit-flag)
                   (lambda (&rest _args) nil))
                  ((symbol-function 'process-id)
                   (lambda (_process) 4242))
                  ((symbol-function 'anvil-worker--maybe-schedule-warmup)
                   (lambda (_worker) nil))
                  ((symbol-function 'anvil-worker--log)
                   (lambda (&rest _entry) nil)))
          (anvil-worker--spawn-worker worker)
          (should (= spawn-count 1))
          (should (= (gethash "anvil-worker-read-test"
                              anvil-worker--spawn-times)
                     0.0))
          (setq now 10.0)
          (anvil-worker--spawn-worker worker)
          (should (= spawn-count 1))
          (should (= (gethash "anvil-worker-read-test"
                              anvil-worker--spawn-times)
                     0.0))
          (setq now 50.0)
          (anvil-worker--spawn-worker worker)
          (should (= spawn-count 2))
          (should (= (gethash "anvil-worker-read-test"
                              anvil-worker--spawn-times)
                     50.0)))
      (let ((buffer (get-buffer " *anvil-worker-read-test*")))
        (when buffer (kill-buffer buffer))))))

(ert-deftest anvil-worker-health-kills-owned-hung-worker-at-threshold ()
  "Only the third idle failed full probe kills an owned connectable worker."
  (let* ((anvil-worker-hung-check-limit 3)
         (anvil-worker--spawn-times (make-hash-table :test #'equal))
         (anvil-worker--owned-processes (make-hash-table :test #'equal))
         (worker (list :name "anvil-worker-read-test"
                       :lane :read
                       :busy nil
                       :hung-checks 0
                       :last-state 'alive))
         (owned 'owned-process)
         (quick-alive t)
         (kill-count 0)
         (spawn-count 0)
         logs)
    (puthash "anvil-worker-read-test" owned anvil-worker--owned-processes)
    (puthash "anvil-worker-read-test" 1.0 anvil-worker--spawn-times)
    (cl-letf (((symbol-function 'anvil-worker--worker-alive-p)
               (lambda (_worker) nil))
              ((symbol-function 'anvil-worker--quick-alive-p)
               (lambda (_worker) quick-alive))
              ((symbol-function 'processp)
               (lambda (process) (eq process owned)))
              ((symbol-function 'process-live-p)
               (lambda (process) (eq process owned)))
              ((symbol-function 'process-id)
               (lambda (_process) 4242))
              ((symbol-function 'kill-process)
               (lambda (_process) (cl-incf kill-count)))
              ((symbol-function 'anvil-worker--spawn-worker)
               (lambda (_worker) (cl-incf spawn-count)))
              ((symbol-function 'anvil-worker--log)
               (lambda (&rest entry) (push entry logs))))
      (anvil-worker--health-check-one worker)
      (anvil-worker--health-check-one worker)
      (should (= kill-count 0))
      (anvil-worker--health-check-one worker)
      (should (= kill-count 1))
      (should (= spawn-count 0))
      (should-not (gethash "anvil-worker-read-test"
                           anvil-worker--owned-processes))
      (should-not (gethash "anvil-worker-read-test"
                           anvil-worker--spawn-times))
      (setq quick-alive nil)
      (anvil-worker--health-check-one worker)
      (should (= spawn-count 1))
      (should (= (cl-count 'unresponsive logs :key #'car) 1))
      (should (= (cl-count 'hung-killed logs :key #'car) 1)))))

(ert-deftest anvil-worker-health-never-kills-a-busy-worker ()
  "A busy worker's slow event loop is owned by dispatch, not health checks."
  (let ((anvil-worker-hung-check-limit 1)
        (worker (list :name "anvil-worker-read-test"
                      :lane :read
                      :busy t
                      :hung-checks 0
                      :last-state 'alive))
        (terminate-count 0))
    (cl-letf (((symbol-function 'anvil-worker--worker-alive-p)
               (lambda (_worker) nil))
              ((symbol-function 'anvil-worker--quick-alive-p)
               (lambda (_worker) t))
              ((symbol-function 'anvil-worker--terminate-owned-hung-worker)
               (lambda (_worker) (cl-incf terminate-count))))
      (dotimes (_ 4) (anvil-worker--health-check-one worker)))
    (should (= terminate-count 0))
    (should (= (plist-get worker :hung-checks) 0))
    (should (eq (plist-get worker :last-state) 'alive))))

(ert-deftest anvil-worker-health-logs-unowned-hung-worker-once ()
  "A connectable worker not spawned by this Emacs is never killed by PID."
  (let ((anvil-worker-hung-check-limit 1)
        (anvil-worker--spawn-times (make-hash-table :test #'equal))
        (anvil-worker--owned-processes (make-hash-table :test #'equal))
        (worker (list :name "anvil-worker-read-test"
                      :lane :read
                      :busy nil
                      :hung-checks 0
                      :last-state 'alive))
        logs)
    (cl-letf (((symbol-function 'anvil-worker--worker-alive-p)
               (lambda (_worker) nil))
              ((symbol-function 'anvil-worker--quick-alive-p)
               (lambda (_worker) t))
              ((symbol-function 'anvil-worker--log)
               (lambda (&rest entry) (push entry logs))))
      (anvil-worker--health-check-one worker)
      (anvil-worker--health-check-one worker))
    (should (= (cl-count 'hung-unowned logs :key #'car) 1))
    (should (plist-get worker :hung-unowned-logged))))

;;; worker-pool-test.el ends here
