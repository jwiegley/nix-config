;;; watchdog-telemetry-test.el --- Exact root activity phases -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'ert)
(require 'json)

(defconst anvil-watchdog-test--run-id
  "0123456789abcdef0123456789abcdef")

(defun anvil-watchdog-test--required-path (name)
  (let ((value (getenv name)))
    (unless (and value (file-name-absolute-p value) (file-exists-p value))
      (error "Missing exact generated test path: %s" name))
    (file-truename value)))

(defconst anvil-watchdog-test--telemetry-init
  (anvil-watchdog-test--required-path "ANVIL_DEDICATED_TELEMETRY_INIT"))
(defconst anvil-watchdog-test--packaged-anvil
  (anvil-watchdog-test--required-path "ANVIL_DEDICATED_ANVIL"))
(defconst anvil-watchdog-test--runtime-emacs
  (anvil-watchdog-test--required-path "ANVIL_TEST_EMACS_STORE"))

(unless (string-prefix-p "/nix/store/" anvil-watchdog-test--telemetry-init)
  (error "Telemetry fixture is not the realised generated init"))

(setenv "ANVIL_EMACS_WATCHDOG_ACTIVITY_SOCKET" "/tmp/anvil-telemetry-test.sock")
(setenv "ANVIL_EMACS_WATCHDOG_RUN_ID" anvil-watchdog-test--run-id)
(cl-letf (((symbol-function 'make-network-process)
           (lambda (&rest _arguments) 'anvil-watchdog-test-process)))
  (load anvil-watchdog-test--telemetry-init nil nil t))

(when (or (getenv "ANVIL_EMACS_WATCHDOG_ACTIVITY_SOCKET")
          (getenv "ANVIL_EMACS_WATCHDOG_RUN_ID"))
  (error "Telemetry init retained root capability environment"))

(require 'anvil)
(require 'anvil-server)

(unless (string-prefix-p
         (file-name-as-directory anvil-watchdog-test--packaged-anvil)
         (file-truename (locate-library "anvil")))
  (error "Tests did not load the exact packaged Anvil"))
(unless (and (string-prefix-p "/nix/store/" anvil-watchdog-test--runtime-emacs)
             (file-executable-p
              (expand-file-name "bin/emacs" anvil-watchdog-test--runtime-emacs)))
  (error "Tests did not receive the realised packaged Emacs"))

(defconst anvil-watchdog-test--server-id "anvil-watchdog-telemetry-test")

(defun anvil-watchdog-test--ok-tool ()
  "Return a small successful result."
  "ok")

(defun anvil-watchdog-test--direct-error-tool ()
  "Signal one direct bounded tool error."
  (signal 'anvil-server-tool-error '("bounded direct failure")))

(defun anvil-watchdog-test--macro-error-tool ()
  "Signal through both macro and dispatcher sanitizers."
  (anvil-server-with-error-handling
    (error "bounded macro failure")))

(defun anvil-watchdog-test--non-local-tool ()
  "Exit non-locally from a tool handler."
  (throw 'anvil-watchdog-test--escape 'escaped))

(defun anvil-watchdog-test--register-tool (id function)
  (anvil-server-unregister-tool id anvil-watchdog-test--server-id)
  (anvil-server-register-tool
   function
   :id id
   :description "Watchdog telemetry fixture"
   :server-id anvil-watchdog-test--server-id))

(defun anvil-watchdog-test--request (id method &optional params)
  (json-encode
   `((jsonrpc . "2.0")
     (id . ,id)
     (method . ,method)
     ,@(when params `((params . ,params))))))

(defun anvil-watchdog-test--decode-frames (frames)
  (mapcar
   (lambda (frame)
     (json-parse-string
      frame
      :object-type 'alist
      :array-type 'list
      :null-object nil
      :false-object :false))
   (nreverse frames)))

(defun anvil-watchdog-test--field (name frame)
  (alist-get name frame))

(defun anvil-watchdog-test--reset-telemetry ()
  (setq anvil-headless--watchdog-telemetry-process
        'anvil-watchdog-test-process
        anvil-headless--watchdog-telemetry-disabled nil
        anvil-headless--watchdog-telemetry-diagnosed nil
        anvil-headless--watchdog-telemetry-sequence 0
        anvil-headless--watchdog-telemetry-phase-started-ms 0
        anvil-headless--watchdog-telemetry-last-transition nil
        anvil-headless--watchdog-telemetry-method "none"
        anvil-headless--watchdog-telemetry-tool nil))

(defmacro anvil-watchdog-test--with-captured-frames (&rest body)
  (declare (indent 0) (debug t))
  `(let (frames)
     (anvil-watchdog-test--reset-telemetry)
     (let ((anvil-server--running t)
           (anvil-server-autostart-on-request nil))
       (cl-letf (((symbol-function 'process-live-p) (lambda (_process) t))
                 ((symbol-function 'process-send-string)
                  (lambda (_process frame) (push frame frames))))
         ,@body))
     (anvil-watchdog-test--decode-frames frames)))

(defun anvil-watchdog-test--assert-sequence
    (frames phases methods tools)
  (should (equal (mapcar (lambda (frame) (anvil-watchdog-test--field 'phase frame))
                         frames)
                 phases))
  (should (equal (mapcar (lambda (frame) (anvil-watchdog-test--field 'method frame))
                         frames)
                 methods))
  (should (equal (mapcar (lambda (frame) (anvil-watchdog-test--field 'tool frame))
                         frames)
                 tools))
  (should (equal (mapcar (lambda (frame) (anvil-watchdog-test--field 'sequence frame))
                         frames)
                 (number-sequence 1 (length frames)))))

(ert-deftest anvil-watchdog-telemetry-phase-parse-failure ()
  (let ((frames
         (anvil-watchdog-test--with-captured-frames
           (should (stringp
                    (anvil-server-process-jsonrpc
                     "x" anvil-watchdog-test--server-id))))))
    (anvil-watchdog-test--assert-sequence
     frames
     '("parse" "response-write" "idle")
     '("none" "none" "none")
     '(nil nil nil))))

(ert-deftest anvil-watchdog-telemetry-phase-unknown-method ()
  (let ((frames
         (anvil-watchdog-test--with-captured-frames
           (should (stringp
                    (anvil-server-process-jsonrpc
                     (anvil-watchdog-test--request 1 "unknown/method")
                     anvil-watchdog-test--server-id))))))
    (anvil-watchdog-test--assert-sequence
     frames
     '("parse" "dispatch" "response-write" "idle")
     '("none" "other" "other" "none")
     '(nil nil nil nil))))

(ert-deftest anvil-watchdog-telemetry-phase-cached-tools-list ()
  (anvil-watchdog-test--register-tool "telemetry-list" #'anvil-watchdog-test--ok-tool)
  (unwind-protect
      (progn
        (let ((anvil-server--running t)
              (anvil-headless--watchdog-telemetry-disabled t))
          (anvil-server-process-jsonrpc
           (anvil-watchdog-test--request 1 "tools/list")
           anvil-watchdog-test--server-id))
        (let ((frames
               (anvil-watchdog-test--with-captured-frames
                 (should (stringp
                          (anvil-server-process-jsonrpc
                           (anvil-watchdog-test--request 2 "tools/list")
                           anvil-watchdog-test--server-id))))))
          (anvil-watchdog-test--assert-sequence
           frames
           '("parse" "dispatch" "response-write" "idle")
           '("none" "tools/list" "tools/list" "none")
           '(nil nil nil nil))))
    (anvil-server-unregister-tool "telemetry-list" anvil-watchdog-test--server-id)))

(ert-deftest anvil-watchdog-telemetry-phase-successful-tool ()
  (anvil-watchdog-test--register-tool "telemetry-ok" #'anvil-watchdog-test--ok-tool)
  (unwind-protect
      (let* ((boundary-calls 0)
             (counter (lambda (&rest _arguments)
                        (setq boundary-calls (1+ boundary-calls))))
             frames)
        (should (fboundp 'anvil-server--enforce-inline-result-limit))
        (unwind-protect
            (progn
              (advice-add 'anvil-server--enforce-inline-result-limit
                          :before counter)
              (setq frames
                (anvil-watchdog-test--with-captured-frames
                  (should (stringp
                           (anvil-server-process-jsonrpc
                            (anvil-watchdog-test--request
                             1 "tools/call"
                             '((name . "telemetry-ok") (arguments . nil)))
                            anvil-watchdog-test--server-id))))))
          (advice-remove 'anvil-server--enforce-inline-result-limit counter))
        (anvil-watchdog-test--assert-sequence
         frames
         '("parse" "dispatch" "tool-call" "result-encode" "response-write" "idle")
         '("none" "tools/call" "tools/call" "tools/call" "tools/call" "none")
         '(nil nil "telemetry-ok" "telemetry-ok" "telemetry-ok" nil))
        (should (= 2 boundary-calls))
        (should (= 1 (cl-count "result-encode" frames
                               :key (lambda (frame)
                                      (anvil-watchdog-test--field 'phase frame))
                               :test #'equal))))
    (anvil-server-unregister-tool "telemetry-ok" anvil-watchdog-test--server-id)))

(ert-deftest anvil-watchdog-telemetry-phase-direct-bounded-error ()
  (anvil-watchdog-test--register-tool
   "telemetry-direct-error" #'anvil-watchdog-test--direct-error-tool)
  (unwind-protect
      (let ((frames
             (anvil-watchdog-test--with-captured-frames
               (should (stringp
                        (anvil-server-process-jsonrpc
                         (anvil-watchdog-test--request
                          1 "tools/call"
                          '((name . "telemetry-direct-error") (arguments . nil)))
                         anvil-watchdog-test--server-id))))))
        (anvil-watchdog-test--assert-sequence
         frames
         '("parse" "dispatch" "tool-call" "result-encode" "response-write" "idle")
         '("none" "tools/call" "tools/call" "tools/call" "tools/call" "none")
         '(nil nil "telemetry-direct-error" "telemetry-direct-error"
               "telemetry-direct-error" nil)))
    (anvil-server-unregister-tool
     "telemetry-direct-error" anvil-watchdog-test--server-id)))

(ert-deftest anvil-watchdog-telemetry-phase-macro-bounded-error ()
  (anvil-watchdog-test--register-tool
   "telemetry-macro-error" #'anvil-watchdog-test--macro-error-tool)
  (unwind-protect
      (let* ((boundary-calls 0)
             (counter (lambda (&rest _arguments)
                        (setq boundary-calls (1+ boundary-calls))))
             frames)
        (should (fboundp 'anvil-server--sanitize-tool-error))
        (unwind-protect
            (progn
              (advice-add 'anvil-server--sanitize-tool-error :before counter)
              (setq frames
                (anvil-watchdog-test--with-captured-frames
                  (should (stringp
                           (anvil-server-process-jsonrpc
                            (anvil-watchdog-test--request
                             1 "tools/call"
                             '((name . "telemetry-macro-error") (arguments . nil)))
                            anvil-watchdog-test--server-id))))))
          (advice-remove 'anvil-server--sanitize-tool-error counter))
        (anvil-watchdog-test--assert-sequence
         frames
         '("parse" "dispatch" "tool-call" "result-encode" "response-write" "idle")
         '("none" "tools/call" "tools/call" "tools/call" "tools/call" "none")
         '(nil nil "telemetry-macro-error" "telemetry-macro-error"
               "telemetry-macro-error" nil))
        (should (= 2 boundary-calls))
        (should (= 1 (cl-count "result-encode" frames
                               :key (lambda (frame)
                                      (anvil-watchdog-test--field 'phase frame))
                               :test #'equal))))
    (anvil-server-unregister-tool
     "telemetry-macro-error" anvil-watchdog-test--server-id)))

(ert-deftest anvil-watchdog-telemetry-phase-non-local-exit ()
  (anvil-watchdog-test--register-tool
   "telemetry-non-local" #'anvil-watchdog-test--non-local-tool)
  (unwind-protect
      (let ((frames
             (anvil-watchdog-test--with-captured-frames
               (should
                (eq 'escaped
                    (catch 'anvil-watchdog-test--escape
                      (anvil-server-process-jsonrpc
                       (anvil-watchdog-test--request
                        1 "tools/call"
                        '((name . "telemetry-non-local") (arguments . nil)))
                       anvil-watchdog-test--server-id)))))))
        (anvil-watchdog-test--assert-sequence
         frames
         '("parse" "dispatch" "tool-call" "idle")
         '("none" "tools/call" "tools/call" "none")
         '(nil nil "telemetry-non-local" nil)))
    (anvil-server-unregister-tool
     "telemetry-non-local" anvil-watchdog-test--server-id)))

(ert-deftest anvil-watchdog-telemetry-malformed-scalar-params-are-sanitized ()
  (let ((secret "anvil-malformed-params-secret-sentinel")
        diagnostics
        outgoing-logs
        raw-frames
        response)
    (anvil-watchdog-test--reset-telemetry)
    (let ((anvil-server--running t)
          (anvil-server-autostart-on-request nil))
      (cl-letf (((symbol-function 'process-live-p) (lambda (_process) t))
                ((symbol-function 'process-send-string)
                 (lambda (_process frame) (push frame raw-frames)))
                ((symbol-function 'anvil-server--log-json-rpc)
                 (lambda (direction json-message _server-id)
                   (when (equal direction "out")
                     (push json-message outgoing-logs))))
                ((symbol-function 'message)
                 (lambda (format-string &rest arguments)
                   (push (apply #'format format-string arguments) diagnostics))))
        (setq response
              (anvil-server-process-jsonrpc
               (anvil-watchdog-test--request 1 "tools/call" secret)
               anvil-watchdog-test--server-id))))
    (let* ((decoded-response
            (json-parse-string
             response
             :object-type 'alist
             :array-type 'list
             :null-object nil
             :false-object :false))
           (error-object (anvil-watchdog-test--field 'error decoded-response))
           (frames (anvil-watchdog-test--decode-frames raw-frames)))
      (should (= (anvil-watchdog-test--field 'code error-object)
                 anvil-server-jsonrpc-error-invalid-params))
      (anvil-watchdog-test--assert-sequence
       frames
       '("parse" "dispatch" "tool-call" "result-encode" "response-write" "idle")
       '("none" "tools/call" "tools/call" "tools/call" "tools/call" "none")
       '(nil nil nil nil nil nil)))
    (dolist (payload (append (list response)
                             raw-frames
                             outgoing-logs
                             diagnostics))
      (should-not (string-match-p (regexp-quote secret) payload)))))

(ert-deftest anvil-watchdog-telemetry-send-failure-is-observability-only ()
  (let (diagnostics)
    (anvil-watchdog-test--reset-telemetry)
    (let ((anvil-server--running t))
      (cl-letf (((symbol-function 'process-live-p) (lambda (_process) t))
                ((symbol-function 'process-send-string)
                 (lambda (&rest _arguments) (error "sensitive failure")))
                ((symbol-function 'message)
                 (lambda (format-string &rest arguments)
                   (push (apply #'format format-string arguments) diagnostics))))
        (should (stringp
                 (anvil-server-process-jsonrpc
                  (anvil-watchdog-test--request 1 "ping")
                  anvil-watchdog-test--server-id)))
        (should (stringp
                 (anvil-server-process-jsonrpc
                  (anvil-watchdog-test--request 2 "ping")
                  anvil-watchdog-test--server-id)))))
    (should (equal diagnostics '("Anvil watchdog telemetry disabled")))))

(ert-deftest anvil-watchdog-telemetry-connect-failure-is-observability-only ()
  (let (diagnostics)
    (setq anvil-headless--watchdog-telemetry-process nil
          anvil-headless--watchdog-telemetry-disabled nil
          anvil-headless--watchdog-telemetry-diagnosed nil)
    (cl-letf (((symbol-function 'make-network-process)
               (lambda (&rest _arguments) (error "sensitive connect failure")))
              ((symbol-function 'message)
               (lambda (format-string &rest arguments)
                 (push (apply #'format format-string arguments) diagnostics))))
      (anvil-headless--watchdog-telemetry-connect)
      (anvil-headless--watchdog-telemetry-connect)
      (let ((anvil-server--running t))
        (should (stringp
                 (anvil-server-process-jsonrpc
                  (anvil-watchdog-test--request 1 "ping")
                  anvil-watchdog-test--server-id)))))
    (should (equal diagnostics '("Anvil watchdog telemetry disabled")))))

(ert-deftest anvil-watchdog-telemetry-invalid-registered-tools-become-null ()
  (let ((anvil-server--tools (make-hash-table :test #'equal))
        (table (make-hash-table :test #'equal)))
    (puthash "control\nname" 'registered table)
    (puthash "نام-ابزار" 'registered table)
    (puthash anvil-watchdog-test--server-id table anvil-server--tools)
    (should-not
     (anvil-headless--watchdog-telemetry-registered-tool
      "control\nname" anvil-watchdog-test--server-id))
    (should-not
     (anvil-headless--watchdog-telemetry-registered-tool
      "نام-ابزار" anvil-watchdog-test--server-id))))

(defconst anvil-watchdog-test--probe-summary
  "root-restarts=3 cause=dispatch-timeout phase=tool-call tool=emacs-eval\n")

(defun anvil-watchdog-test--call-probe-advice (runner)
  "Call the generated worker-probe advice with RUNNER installed."
  (let ((anvil-headless--watchdog-probe-python "/nix/store/test-python")
        (anvil-headless--watchdog-probe-supervisor
         "/nix/store/test-supervisor.py")
        (anvil-headless--watchdog-probe-runtime-directory
         "/private/tmp/anvil-runtime/0123456789abcdef0123456789abcdef")
        (anvil-headless--watchdog-probe-agent-key
         "0123456789abcdef0123456789abcdef"))
    (cl-letf (((symbol-function 'anvil-headless--run-process-responsive)
               runner))
      (anvil-headless--watchdog-probe-around
       (lambda () "worker-summary")))))

(ert-deftest anvil-watchdog-telemetry-probe-valid-summary ()
  (let (invocation)
    (should
     (equal
      (anvil-watchdog-test--call-probe-advice
       (lambda (&rest arguments)
         (setq invocation arguments)
         (list 0 anvil-watchdog-test--probe-summary "")))
      (concat "worker-summary\nroot-summary="
              (string-trim-right anvil-watchdog-test--probe-summary))))
    (should
     (equal
      invocation
      '("/nix/store/test-python"
        ("-I" "-S" "/nix/store/test-supervisor.py"
         "--probe-summary"
         "--runtime-dir"
         "/private/tmp/anvil-runtime/0123456789abcdef0123456789abcdef"
         "--agent-key"
         "0123456789abcdef0123456789abcdef")
        "/private/tmp/anvil-runtime/0123456789abcdef0123456789abcdef"
        2 257 0)))))

(ert-deftest anvil-watchdog-telemetry-probe-invalid-output ()
  (dolist (result
           '((1 "" "")
             (0 "root-restarts=0 cause=none phase=unknown tool=none" "")
             (0 "root-restarts=x cause=none phase=unknown tool=none\n" "")
             (0 "root-restarts=0 cause=other phase=unknown tool=none\n" "")
             (0 "root-restarts=0 cause=none phase=other tool=none\n" "")
             (0 "root-restarts=0 cause=none phase=unknown tool=none\nextra\n" "")
             (0 "root-restarts=0 cause=none phase=unknown tool=none\n" "x")))
    (should
     (equal
      (anvil-watchdog-test--call-probe-advice
       (lambda (&rest _arguments) result))
      "worker-summary\nroot-summary=unavailable"))))

(ert-deftest anvil-watchdog-telemetry-probe-timeout-and-overflow ()
  (dolist (runner
           (list
            (lambda (&rest _arguments) (error "private timeout detail"))
            (lambda (&rest _arguments)
              (list 0 (concat (make-string 257 ?x) "\n") ""))
            (lambda (&rest _arguments)
              (list 0 anvil-watchdog-test--probe-summary "x"))))
    (should
     (equal
      (anvil-watchdog-test--call-probe-advice runner)
      "worker-summary\nroot-summary=unavailable"))))

(ert-deftest anvil-watchdog-telemetry-probe-adversarial-tool-label ()
  (dolist (tool '("bad\nline" "bad\rline" "bad\tline" "bad\x1bline" "نام"))
    (let ((result
           (anvil-watchdog-test--call-probe-advice
            (lambda (&rest _arguments)
              (list
               0
               (format
                "root-restarts=1 cause=heartbeat-timeout phase=tool-call tool=%s\n"
                tool)
               "")))))
      (should (equal result "worker-summary\nroot-summary=unavailable"))
      (should-not (string-match-p "[^\x20-\x7e\n]" result)))))

(provide 'watchdog-telemetry-test)
;;; watchdog-telemetry-test.el ends here
