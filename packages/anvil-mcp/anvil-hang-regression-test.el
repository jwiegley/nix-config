;;; anvil-hang-regression-test.el --- Hang regressions for Anvil -*- lexical-binding: t; -*-

;;; Commentary:

;; Regression tests for issue #53.  These tests deliberately use real
;; subprocesses: an offload REPL interrupted by `keyboard-quit', a dead REPL
;; whose zero-delay sentinel timer is withheld, and host shells that are
;; interrupted or fill their stderr pipe.  Every wait has a bounded deadline
;; and every test tears down the processes it creates.
;;
;; This file is deliberately a superset of upstream's
;; tests/anvil-hang-regression-test.el.  Do not deduplicate it unless upstream
;; also contains `anvil-hang-regression-shell-sync-timeout-cap',
;; `anvil-hang-regression-host-stdin-is-eof', and
;; `anvil-hang-regression-shell-filter-does-not-wait-for-detached-pipe-holder'.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'seq)
(require 'subr-x)
(require 'anvil-offload)
(require 'anvil-server)
(require 'anvil-host)
(require 'anvil-shell-filter)

(defconst anvil-hang-regression-test--tests-directory
  (file-name-directory (or load-file-name buffer-file-name))
  "Directory containing the offload stub used by these tests.")

(defun anvil-hang-regression-test--wait-until (predicate timeout)
  "Wait for PREDICATE to return non-nil, but no longer than TIMEOUT seconds."
  (let ((deadline (+ (float-time) timeout)))
    (while (and (not (funcall predicate))
                (< (float-time) deadline))
      (accept-process-output nil 0.02))
    (funcall predicate)))

(defun anvil-hang-regression-test--first-pending ()
  "Return the first pending offload future, or nil."
  (let (found)
    (maphash (lambda (_id future)
               (unless found
                 (setq found future)))
             (anvil-offload--ensure-pending))
    found))

(defun anvil-hang-regression-test--assert-offload-clean ()
  "Refuse to discard ownership state before subprocess cleanup converges."
  (let ((deadline (+ (float-time) 1.0)))
    (while (and (hash-table-p anvil-offload--pending)
                (> (hash-table-count anvil-offload--pending) 0)
                (< (float-time) deadline))
      (accept-process-output nil 0.01)))
  (let (owned pending)
    (dolist (table (anvil-offload--registered-ownership-tables))
      (maphash
       (lambda (proc value)
         (push (list table proc value) owned))
       table))
    (when (hash-table-p anvil-offload--pending)
      (maphash (lambda (id _future) (push id pending))
               anvil-offload--pending))
    (when (or anvil-offload--pool
              anvil-offload--pool-retiring-p
              anvil-offload--pool-cleanup-active-p
              anvil-offload--submission-active-p
              anvil-offload--stop-retiring-p
              anvil-offload--retired-pools
              owned
              pending)
      (error
       (concat
        "hang regression cleanup did not converge: "
        "pool=%S pool-retiring=%S cleanup-active=%S submission-active=%S stop-retiring=%S "
        "retired=%S owned=%S pending=%S")
       anvil-offload--pool
       anvil-offload--pool-retiring-p
       anvil-offload--pool-cleanup-active-p
       anvil-offload--submission-active-p
       anvil-offload--stop-retiring-p
       anvil-offload--retired-pools
       owned
       pending))))

(defun anvil-hang-regression-test--reset-offload ()
  "Kill and reset offload state only after ownership convergence."
  (anvil-offload-stop-repl)
  (anvil-hang-regression-test--assert-offload-clean)
  (setq anvil-offload--pool nil
        anvil-offload--round-robin 0
        anvil-offload--next-id 0
        anvil-offload--pending (make-hash-table :test 'eql)
        anvil-offload--isolated-processes (make-hash-table :test 'eq)
        anvil-offload--pool-retiring-p nil
        anvil-offload--pool-cleanup-active-p nil
        anvil-offload--submission-active-p nil
        anvil-offload--stop-retiring-p nil
        anvil-offload--retired-pools nil
        anvil-offload--ownership-table-registry nil)
  (accept-process-output nil 0.05))

(defun anvil-hang-regression-test--stub-tool (&optional timeout)
  "Return an offload tool plist using the test stub and TIMEOUT."
  (list :offload-require 'anvil-offload-stub
        :offload-load-path
        (list anvil-hang-regression-test--tests-directory)
        :offload-timeout (or timeout 5)))

(defun anvil-hang-regression-test--buffer-with-prefix (prefix)
  "Return the first live buffer with a name starting with PREFIX."
  (seq-find (lambda (buffer)
              (string-prefix-p prefix (buffer-name buffer)))
            (buffer-list)))

(ert-deftest anvil-hang-regression-interrupted-offload-releases-slot ()
  "A `keyboard-quit' must kill an offload and leave its slot reusable.

Before the issue #53 fix, the nonlocal exit escaped
`anvil-server--offload-apply' while its future and slow REPL remained live.
With a one-slot pool, every later request was queued behind that abandoned
form and appeared to hang."
  (anvil-hang-regression-test--reset-offload)
  (let ((anvil-offload-pool-size 1)
        (anvil-offload-emacs-bin
         (expand-file-name invocation-name invocation-directory))
        (tool (anvil-hang-regression-test--stub-tool 5))
        timer victim victim-proc victim-pid quit-seen)
    (unwind-protect
        (progn
          (setq timer
                (run-at-time
                 0.25 nil
                 (lambda ()
                   (setq victim (anvil-hang-regression-test--first-pending)
                         victim-proc
                         (and victim (anvil-future--process victim))
                         victim-pid
                         (and victim-proc (process-id victim-proc)))
                   (keyboard-quit))))
          (condition-case nil
              (anvil-server--offload-apply
               tool 'anvil-offload-stub-sleep (list "slow"))
            (quit (setq quit-seen t)))
          (should quit-seen)
          (should (anvil-future-p victim))
          (should (processp victim-proc))
          (should (integerp victim-pid))
          (should (= 0 (hash-table-count
                        (anvil-offload--ensure-pending))))
          (should (eq 'killed (anvil-future-status victim)))
          (should (string-match-p "killed after"
                                  (anvil-future-error victim)))
          (should
           (anvil-hang-regression-test--wait-until
            (lambda () (not (process-live-p victim-proc))) 2))
          (let* ((started (float-time))
                 (result
                  (anvil-server--offload-apply
                   tool 'anvil-offload-stub-pid-tool (list "fresh")))
                 (elapsed (- (float-time) started)))
            (should (string-match
                     "\\`pid:\\([0-9]+\\) tag:fresh\\'" result))
            (should-not (= victim-pid
                           (string-to-number (match-string 1 result))))
            (should (< elapsed 5.0))))
      (when (timerp timer)
        (cancel-timer timer))
      (when (and victim-proc (process-live-p victim-proc))
        (delete-process victim-proc))
      (anvil-hang-regression-test--reset-offload))))

(ert-deftest anvil-hang-regression-await-isolates-unrelated-filter ()
  "Awaiting one REPL must not dispatch an unrelated process filter.

The unrelated child writes while remaining live.  Its filter must stay
undispatched until the target future has settled and the caller explicitly
services that child.  This prevents arbitrary process callbacks from
re-entering synchronous Anvil waits."
  (anvil-hang-regression-test--reset-offload)
  (let ((anvil-offload-pool-size 1)
        (anvil-offload-emacs-bin
         (expand-file-name invocation-name invocation-directory))
        target unrelated filter-output)
    (unwind-protect
        (progn
          (setq target
                (anvil-offload
                 '(progn (sleep-for 0.5) 'target-done)))
          (setq unrelated
                (make-process
                 :name "anvil-hang-unrelated-filter"
                 :command
                 (list shell-file-name shell-command-switch
                       "sleep 0.05; printf unrelated; sleep 5")
                 :connection-type 'pipe
                 :noquery t
                 :filter
                 (lambda (_process output)
                   (setq filter-output
                         (concat filter-output output)))))
          ;; Allow for cold packaged Emacs startup while keeping the wait
          ;; bounded.  The regression assertion is filter isolation below.
          (should (anvil-future-await target 15))
          (should (eq 'target-done (anvil-future-value target)))
          (should-not filter-output)
          (should (accept-process-output unrelated 0.5 nil t))
          (should (equal "unrelated" filter-output)))
      (when (and unrelated (process-live-p unrelated))
        (delete-process unrelated))
      (anvil-hang-regression-test--reset-offload))))

(ert-deftest anvil-hang-regression-dead-repl-settles-without-timer ()
  "Awaiting a dead REPL must not depend on a zero-delay sentinel timer.

The real child waits until its future is registered, then exits with its
automatic sentinel disabled.  The production sentinel is invoked while
`run-at-time' is intercepted, making the old `sit-for 0' fallback leave the
future pending without depending on Emacs callback scheduling."
  (anvil-hang-regression-test--reset-offload)
  (let* ((proc
          (make-process
           :name "anvil-hang-dead-repl"
           :command
           (list shell-file-name shell-command-switch "read ignored; exit 7")
           :connection-type 'pipe
           :noquery t
           :sentinel #'ignore))
         (id 9001)
         (future
          (make-anvil-future :id id :process proc :status 'pending))
         deferred)
    (puthash id future (anvil-offload--ensure-pending))
    (unwind-protect
        (cl-letf (((symbol-function 'run-at-time)
                   (lambda (&rest args)
                     (setq deferred args)
                     'withheld-timer)))
          ;; Release the child only after its future and the timer stub are
          ;; live.  Invoke the real sentinel explicitly after death: whether
          ;; Emacs happens to dispatch a process sentinel during await is an
          ;; event-loop detail, not part of the behavior under test.
          (process-send-string proc "\n")
          (should
           (anvil-hang-regression-test--wait-until
            (lambda () (not (process-live-p proc))) 2))
          (anvil-offload--sentinel proc "exited abnormally with code 7\n")
          (should deferred)
          (should (eq 'pending (anvil-future-status future)))
          (should (anvil-future-await future 2))
          (should (eq 'error (anvil-future-status future)))
          (should (string-match-p "offload REPL exited"
                                  (anvil-future-error future)))
          (should-not (gethash id (anvil-offload--ensure-pending))))
      (when (process-live-p proc)
        (delete-process proc))
      (remhash id (anvil-offload--ensure-pending))
      (anvil-hang-regression-test--reset-offload))))

(ert-deftest anvil-hang-regression-final-filter-beats-deferred-death ()
  "A final reply delivered after the sentinel must beat deferred cleanup.

This exercises the sentinel-before-filter ordering explicitly.  The fallback
death callback is idempotent and must not overwrite a reply that settles the
future first."
  (anvil-hang-regression-test--reset-offload)
  (let* ((proc
          (make-process
           :name "anvil-hang-filter-order"
           :command (list shell-file-name shell-command-switch "exit 0")
           :connection-type 'pipe
           :noquery t
           :sentinel #'ignore))
         (id 9002)
         (future
          (make-anvil-future :id id :process proc :status 'pending))
         deferred)
    (unwind-protect
        (progn
          (should
           (anvil-hang-regression-test--wait-until
            (lambda () (not (process-live-p proc))) 2))
          (puthash id future (anvil-offload--ensure-pending))
          (cl-letf (((symbol-function 'run-at-time)
                     (lambda (&rest args)
                       (setq deferred args)
                       'withheld-timer)))
            (anvil-offload--sentinel proc "finished\n"))
          (should deferred)
          (should (eq 'pending (anvil-future-status future)))
          (anvil-offload--dispatch-reply
           proc (list :id id :ok 'late-reply))
          (apply (nth 2 deferred) (nthcdr 3 deferred))
          (should (eq 'done (anvil-future-status future)))
          (should (eq 'late-reply (anvil-future-value future))))
      (when (process-live-p proc)
        (delete-process proc))
      (remhash id (anvil-offload--ensure-pending))
      (anvil-hang-regression-test--reset-offload))))

(ert-deftest anvil-hang-regression-shell-sync-timeout-cap ()
  "Oversize synchronous shell requests must fail before spawning a child."
  (let ((anvil-shell-filter-max-sync-timeout 2)
        shell-called
        timeout-seen)
    (cl-letf (((symbol-function 'anvil-shell)
               (lambda (_cmd opts)
                 (setq shell-called t
                       timeout-seen (plist-get opts :timeout))
                 '(:exit 0 :stdout "" :stderr "")))
              ((symbol-function 'anvil-shell-filter--tee-put)
               (lambda (_raw) "test-tee")))
      (should-error (anvil-shell-filter-run "true" :timeout 3)
                    :type 'user-error)
      (should-not shell-called)
      (let ((result (anvil-shell-filter-run "true" :timeout 2)))
        (should shell-called)
        (should (= 2 timeout-seen))
        (should (zerop (plist-get result :exit)))))))

(ert-deftest anvil-hang-regression-host-stdin-is-eof ()
  "A host command that reads stdin must receive EOF instead of timing out."
  (let ((result
         (anvil-host--run
          "cat >/dev/null; printf 'stdin-eof\\n'"
          'utf-8
          temporary-file-directory
          1)))
    (should (equal '(0 "stdin-eof\n" "") result))))


(ert-deftest anvil-hang-regression-host-quit-cleans-processes-and-buffers ()
  "A `keyboard-quit' during a host shell must delete all temporary state."
  (let (timer stdout-buffer stderr-buffer stdout-proc stderr-proc quit-seen)
    (unwind-protect
        (progn
          (setq timer
                (run-at-time
                 0.25 nil
                 (lambda ()
                   (setq stdout-buffer
                         (anvil-hang-regression-test--buffer-with-prefix
                          " *anvil-host-stdout*")
                         stderr-buffer
                         (anvil-hang-regression-test--buffer-with-prefix
                          " *anvil-host-stderr*")
                         stdout-proc
                         (and stdout-buffer
                              (get-buffer-process stdout-buffer))
                         stderr-proc
                         (and stderr-buffer
                              (get-buffer-process stderr-buffer)))
                   (keyboard-quit))))
          (condition-case nil
              (anvil-shell "sleep 30" '(:timeout 5))
            (quit (setq quit-seen t)))
          (should quit-seen)
          (should (processp stdout-proc))
          (should (processp stderr-proc))
          (should-not (process-live-p stdout-proc))
          (should-not (process-live-p stderr-proc))
          (should-not (buffer-live-p stdout-buffer))
          (should-not (buffer-live-p stderr-buffer)))
      (when (timerp timer)
        (cancel-timer timer))
      (when (and stdout-proc (process-live-p stdout-proc))
        (delete-process stdout-proc))
      (when (and stderr-proc (process-live-p stderr-proc))
        (delete-process stderr-proc))
      (when (buffer-live-p stdout-buffer)
        (kill-buffer stdout-buffer))
      (when (buffer-live-p stderr-buffer)
        (kill-buffer stderr-buffer)))))

(ert-deftest anvil-hang-regression-host-drains-final-stdout-after-exit ()
  "A tracked shell's final stdout must survive that shell's exit.

The tracked process writes the final bytes itself.  An auxiliary wrapper would
only add a second dynamic-loader launch and make this drain regression depend
on host-wide loader scheduling."
  (skip-unless
   (and (memq system-type '(darwin gnu/linux))
        (file-executable-p shell-file-name)))
  (let (failures)
    (dotimes (iteration 100)
      (let ((result
             (anvil-shell
              "printf prefix; printf suffix"
              '(:timeout 15 :max-output nil))))
        (unless
            (and (zerop (plist-get result :exit))
                 (equal "prefixsuffix" (plist-get result :stdout))
                 (string-empty-p (plist-get result :stderr)))
          (push (cons iteration result) failures))))
    (should-not failures)))

(ert-deftest
    anvil-hang-regression-shell-filter-does-not-wait-for-detached-pipe-holder ()
  "A detached child retaining stdout and stderr must not delay shell-filter."
  (skip-unless
   (and (memq system-type '(darwin gnu/linux))
        (executable-find "nohup")
        (executable-find "sleep")))
  (let ((pid-file (make-temp-file "anvil-shell-filter-child-"))
        child-pid)
    (unwind-protect
        (let* ((command
                (format "%s %s 5 & echo $! > %s; printf ready"
                        (shell-quote-argument (executable-find "nohup"))
                        (shell-quote-argument (executable-find "sleep"))
                        (shell-quote-argument pid-file)))
               (started (float-time))
               (result
                (cl-letf (((symbol-function 'anvil-shell-filter--tee-put)
                           (lambda (_raw) "test-tee")))
                  (anvil-shell-filter-run command :timeout 3)))
               (elapsed (- (float-time) started)))
          (setq child-pid
                (string-to-number
                 (string-trim
                  (with-temp-buffer
                    (insert-file-contents pid-file)
                    (buffer-string)))))
          (should (> child-pid 1))
          (should (process-attributes child-pid))
          (should (zerop (plist-get result :exit)))
          (should (equal "ready" (plist-get result :compressed)))
          (should (< elapsed 2.0)))
      (when (and (integerp child-pid) (> child-pid 1))
        (ignore-errors (signal-process child-pid 9)))
      (delete-file pid-file))))

(ert-deftest anvil-hang-regression-host-drains-stderr-while-running ()
  "A stderr flood larger than pipe capacity must complete without timeout."
  (skip-unless (memq system-type '(darwin gnu/linux)))
  (let* ((bytes (* 1024 1024))
         (command
          (format
           "yes 0123456789abcdef | head -c %d >&2; printf done"
           bytes))
         (started (float-time))
         (result (anvil-shell command '(:timeout 3 :max-output nil)))
         (elapsed (- (float-time) started)))
    (should (eql 0 (plist-get result :exit)))
    (should (equal "done" (plist-get result :stdout)))
    (should (= bytes (length (plist-get result :stderr))))
    (should (< elapsed 3.0))))

(provide 'anvil-hang-regression-test)
;;; anvil-hang-regression-test.el ends here
