;;; edit-env-test.el --- Tests for edit-env -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)
(require 'edit-env)

(ert-deftest edit-env-update-preserves-equals-in-added-value ()
  (let ((process-environment nil)
        (edit-env-added-ls 'fixture)
        edit-env-changed-ls)
    (cl-letf (((symbol-function 'widget-value)
               (lambda (_widget) '("FOO=a=b")))
              ((symbol-function 'edit-env) #'ignore)
              ((symbol-function 'bury-buffer) #'ignore)
              ((symbol-function 'message) #'ignore))
      (edit-env-update))
    (should (equal (getenv "FOO") "a=b"))))

(ert-deftest edit-env-display-preserves-equals-in-existing-value ()
  (let ((process-environment '("FOO=a=b")))
    (save-window-excursion
      (unwind-protect
          (progn
            (edit-env)
            (with-current-buffer "*Environment Variable Editor*"
              (should (string-match-p "FOO[[:space:]]+a=b" (buffer-string)))))
        (when (get-buffer "*Environment Variable Editor*")
          (kill-buffer "*Environment Variable Editor*"))))))

(ert-deftest edit-env-display-and-update-preserve-bare-entry ()
  (let ((process-environment '("BARE" "FOO=a=b")))
    (save-window-excursion
      (unwind-protect
          (progn
            (edit-env)
            (with-current-buffer "*Environment Variable Editor*"
              (should (string-match-p "BARE[[:space:]]+" (buffer-string)))
              (let ((bare-widget
                     (cl-find-if
                      (lambda (widget)
                        (equal
                         (widget-get widget 'environment-variable-name)
                         "BARE"))
                      widget-field-list)))
                (should bare-widget)
                (edit-env-mark-changed bare-widget)
                (cl-letf (((symbol-function 'widget-value)
                           (lambda (widget)
                             (and (eq widget bare-widget) "restored")))
                          ((symbol-function 'edit-env) #'ignore)
                          ((symbol-function 'bury-buffer) #'ignore))
                  (edit-env-update))
                (should (equal (getenv "BARE") "restored")))))
        (when (get-buffer "*Environment Variable Editor*")
          (kill-buffer "*Environment Variable Editor*"))))))

;;; edit-env-test.el ends here
