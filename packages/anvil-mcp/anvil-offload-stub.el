;;; anvil-offload-stub.el --- Tiny self-contained fixture for offload dispatch tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Loaded into the anvil-offload REPL subprocess by
;; `anvil-test-offload-dispatch-runs-in-subprocess' via
;; `:offload-require'.  Must NOT depend on anvil-server or any other
;; anvil module — the whole point is to verify that a tool handler
;; can run with minimal imports in the offload subprocess.

;;; Code:

(defun anvil-offload-stub-pid-tool (tag)
  "Return a string \"pid:PID tag:TAG\" from the running Emacs.

MCP Parameters:
  tag - arbitrary caller-supplied string echoed back in the reply"
  (format "pid:%d tag:%s" (emacs-pid) tag))

(defun anvil-offload-stub-boom (_ignored)
  "Always signal `arith-error' — used to test remote-error propagation.

MCP Parameters:
  _ignored - unused placeholder for the single-arg MCP schema convention"
  (/ 1 0))

(defun anvil-offload-stub-sleep (_ignored)
  "Sleep in the subprocess long enough to trip any sensible timeout.

MCP Parameters:
  _ignored - unused placeholder for the single-arg MCP schema convention"
  (sleep-for 30))

(defun anvil-offload-stub-load-path-size (_ignored)
  "Return the subprocess's `load-path' length as a decimal string.
Used to confirm that `:offload-inherit-load-path' actually inflates
the subprocess's load-path relative to a bare REPL.

MCP Parameters:
  _ignored - unused placeholder for the single-arg MCP schema convention"
  (format "%d" (length load-path)))

(defun anvil-offload-stub-checkpoint-then-sleep (tag)
  "Record a checkpoint with payload built from TAG, then sleep until killed.
Used to verify that `:resumable t' folds the latest checkpoint into
the partial reply on budget exceed.

MCP Parameters:
  tag - string used to build the :value payload so the test can verify it"
  (anvil-preempt-checkpoint (format "value:%s" tag)
                            (format "cursor:%s" tag))
  (sleep-for 30))

(provide 'anvil-offload-stub)
;;; anvil-offload-stub.el ends here
