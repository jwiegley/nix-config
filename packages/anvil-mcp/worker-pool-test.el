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
              ((symbol-function 'anvil-worker--spawn-worker)
               (lambda (_worker) (cl-incf spawn-count)))
              ((symbol-function 'anvil-worker--log)
               (lambda (&rest entry) (push entry logs))))
      (anvil-worker--health-check-one worker))
    (should (= spawn-count 1))
    (should-not logs)
    (should (eq (plist-get worker :last-state) 'dead))))

(ert-deftest anvil-worker-kill-clears-all-spawn-grace-state ()
  "An intentional pool kill makes every worker immediately spawnable."
  (let ((anvil-worker--spawn-times (make-hash-table :test #'equal))
        (worker (list :name "anvil-worker-read-test" :lane :read)))
    (puthash "anvil-worker-read-test" 1.0 anvil-worker--spawn-times)
    (puthash "discarded-worker" 2.0 anvil-worker--spawn-times)
    (cl-letf (((symbol-function 'anvil-worker--map-pool)
               (lambda (function) (funcall function worker)))
              ((symbol-function 'anvil-worker--worker-alive-p)
               (lambda (_worker) nil)))
      (anvil-worker-kill))
    (should (= (hash-table-count anvil-worker--spawn-times) 0))))

(ert-deftest anvil-worker-quick-check-documents-the-direct-probe ()
  "The packaged documentation must describe its patched liveness mechanism."
  (should (string-match-p
           "direct connect probe on the cached socket path"
           (documentation 'anvil-worker--quick-alive-p)))
  (should-not (string-match-p
               "file + PID only, no probe"
               (documentation 'anvil-worker--spawn-worker))))

;;; worker-pool-test.el ends here
