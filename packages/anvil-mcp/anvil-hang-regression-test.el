;;; anvil-hang-regression-test.el --- Hang regressions for Anvil -*- lexical-binding: t; -*-

;;; Commentary:

;; Regression tests for issue #53.  These tests deliberately use real
;; subprocesses: an offload REPL interrupted by `keyboard-quit', a dead REPL
;; whose zero-delay sentinel timer is withheld, and host shells that are
;; interrupted or fill their stderr pipe.  Every wait has a bounded deadline
;; and every test tears down the processes it creates.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'seq)
(require 'subr-x)
(require 'anvil-offload)
(require 'anvil-server)
(require 'anvil-host)

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

(defun anvil-hang-regression-test--reset-offload ()
  "Kill the offload pool and reset all request state."
  (when anvil-offload--pool
    (anvil-offload-stop-repl))
  (setq anvil-offload--pool nil
        anvil-offload--round-robin 0
        anvil-offload--next-id 0
        anvil-offload--pending (make-hash-table :test 'eql))
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

The real child exits while `run-at-time' is intercepted, making the old
`sit-for 0' fallback deterministically leave the future pending."
  (anvil-hang-regression-test--reset-offload)
  (let* ((proc
          (make-process
           :name "anvil-hang-dead-repl"
           :command
           (list shell-file-name shell-command-switch "sleep 0.1; exit 7")
           :connection-type 'pipe
           :noquery t
           :sentinel #'anvil-offload--sentinel))
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
          (should (anvil-future-await future 2))
          (should deferred)
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
          (anvil-offload--dispatch-reply (list :id id :ok 'late-reply))
          (apply (nth 2 deferred) (nthcdr 3 deferred))
          (should (eq 'done (anvil-future-status future)))
          (should (eq 'late-reply (anvil-future-value future))))
      (when (process-live-p proc)
        (delete-process proc))
      (remhash id (anvil-offload--ensure-pending))
      (anvil-hang-regression-test--reset-offload))))

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
  "A child shell's final stdout must survive its tracked wrapper's exit."
  (skip-unless
   (and (memq system-type '(darwin gnu/linux))
        (file-executable-p "/bin/sh")
        (executable-find "echo")))
  (let ((wrapper
         (make-temp-file
          "anvil-host-wrapper-" nil ".sh"
          "#!/bin/sh\n/bin/sh \"$@\"\nexit $?\n"))
        failures)
    (unwind-protect
        (progn
          (set-file-modes wrapper #o700)
          (let ((shell-file-name wrapper))
            (dotimes (iteration 50)
              (let ((result
                     (anvil-shell
                      (format "printf prefix; %s -n suffix"
                              (shell-quote-argument
                               (executable-find "echo")))
                      '(:timeout 15 :max-output nil))))
                (unless
                    (and (zerop (plist-get result :exit))
                         (equal "prefixsuffix"
                                (plist-get result :stdout))
                         (string-empty-p (plist-get result :stderr)))
                  (push (cons iteration result) failures)))))
          (should-not failures))
      (delete-file wrapper))))

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
