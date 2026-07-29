;;; anvil-watchdog-capability-descendant.el --- Test capability hygiene -*- lexical-binding: t; -*-

(require 'json)

(defun anvil-watchdog-capability--descriptor-identity (descriptor)
  "Return a tagged kernel identity for DESCRIPTOR, or nil when it is unrelated."
  (cond
   ((eq system-type 'gnu/linux)
    (let ((target
           (ignore-errors
             (file-symlink-p (format "/proc/self/fd/%d" descriptor)))))
      (when (and (stringp target)
                 (string-match
                  "\\`\\(socket\\|pipe\\):\\[\\([0-9]+\\)\\]\\'"
                  target))
        (list (match-string 1 target)
              (string-to-number (match-string 2 target))))))
   ((eq system-type 'darwin)
    (let* ((attributes
            (ignore-errors
              (file-attributes (format "/dev/fd/%d" descriptor) 'string)))
           (modes (and attributes (file-attribute-modes attributes))))
      (when (and (stringp modes)
                 (> (length modes) 0)
                 (memq (aref modes 0) '(?s ?p)))
        (let ((identity (file-attribute-file-identifier attributes)))
          (list (if (eq (aref modes 0) ?s) "socket" "pipe")
                (nth 0 identity)
                (nth 1 identity))))))
   (t
    (error "Unsupported descriptor identity platform: %S" system-type))))

(when (and (eq system-type 'gnu/linux)
           (not (file-directory-p "/proc/self/fd")))
  (error "Linux descriptor identity requires /proc/self/fd"))

(let ((result (getenv "ANVIL_TEST_DESCENDANT_RESULT"))
      (root-socket-identities
       (json-parse-string
        (or (getenv "ANVIL_TEST_ROOT_SOCKET_IDENTITIES") "[]")
        :array-type 'list))
      (event-pipe-inode
       (string-to-number
        (or (getenv "ANVIL_TEST_EVENT_PIPE_INODE") "0")))
      (capability-keys
       '("ANVIL_EMACS_WATCHDOG_SUPERVISED"
         "ANVIL_EMACS_WATCHDOG_EVENT_FD"
         "ANVIL_EMACS_WATCHDOG_ACTIVITY_SOCKET"
         "ANVIL_EMACS_WATCHDOG_RUN_ID"))
      inherited-root-socket-fds
      inherited-event-pipe-fds)
  (unless (and result (file-name-absolute-p result))
    (error "Missing absolute descendant result path"))
  (dotimes (offset 1021)
    (let* ((descriptor (+ 3 offset))
           (identity
            (anvil-watchdog-capability--descriptor-identity descriptor)))
      (cond
       ((and identity
             (equal (car identity) "pipe")
             (= (nth 1 identity) event-pipe-inode))
        (push descriptor inherited-event-pipe-fds))
       ((and identity
             (equal (car identity) "socket")
             (member identity root-socket-identities))
        (push descriptor inherited-root-socket-fds)))))
  (with-temp-file result
    (insert
     (json-serialize
      `((present_keys
         . ,(vconcat
             (delq nil
                   (mapcar
                    (lambda (name) (and (getenv name) name))
                    capability-keys))))
        (inherited_root_socket_fds
         . ,(vconcat (nreverse inherited-root-socket-fds)))
        (inherited_event_pipe_fds
         . ,(vconcat (nreverse inherited-event-pipe-fds)))
        (scan_first . 3)
        (scan_last . 1023))))))
