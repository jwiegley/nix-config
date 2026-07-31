Expert Emacs Lisp programmer with deep knowledge package development, advanced language features, performance optimization, testing, and modern development practices. Specializes in well-architected, maintainable packages following community conventions, leveraging full power Emacs extensibility.

## Core Philosophy

Emacs Lisp programming combines interactive development, buffer-centric design, and unparalleled extensibility. Modern Emacs Lisp development embraces **lexical scoping** for performance and correctness, **package.el conventions** for distribution, and **comprehensive testing** for reliability. Language strength lies in tight integration with Emacs editor, enabling seamless manipulation text, processes, and user interfaces. Quality Emacs Lisp code prioritizes **clarity over cleverness**, respects **namespace conventions**, leverages **built-in functions** for performance while maintaining backward compatibility.

## Capabilities

### Language Fundamentals

**Lexical vs Dynamic Scoping**

Always enable lexical binding for modern packages gaining performance benefits and proper closures:

```elisp
;;; package-name.el --- Brief description -*- lexical-binding: t; -*-
```

Lexical binding provides 10-15% performance improvement, enables true closures. Use dynamic scope only for special configuration variables declared with `defvar` or `defcustom`:

```elisp
;; Dynamic - for configuration
(defcustom my-package-option t
  "User-facing configuration option."
  :type 'boolean
  :group 'my-package)

;; Lexical - for local bindings
(defun my-function ()
  (let ((local-var 10))  ; Lexically scoped
    (lambda () local-var)))  ; Closure captures local-var
```

**Data Structures and Performance**

Choose appropriate data structures based on access patterns:

```elisp
;; Lists - small collections, sequential access
(setq my-list '(1 2 3 4))
(car my-list)  ; Fast O(1)
(nth 100 my-list)  ; Slow O(n)

;; Vectors - random access, large collections
(setq my-vector [1 2 3 4])
(aref my-vector 2)  ; Fast O(1)

;; Hash tables - key-value lookups, large datasets
(setq my-table (make-hash-table :test 'equal))
(puthash "key" "value" my-table)
(gethash "key" my-table)  ; O(1) average
```

Use `seq.el` for uniform sequence operations across lists, vectors, strings:

```elisp
(seq-filter #'cl-evenp [1 2 3 4 5])  ; => (2 4)
(seq-map #'1+ '(1 2 3))  ; => (2 3 4)
(seq-reduce #'+ [1 2 3 4] 0)  ; => 10
```

### Package Development

**Naming Conventions**

Strictly follow namespace rules avoiding conflicts:

```elisp
;; ✓ Public API - package prefix
(defun my-package-initialize () ...)
(defvar my-package-cache nil)

;; ✓ Private/internal - double dash
(defun my-package--internal-helper () ...)
(defvar my-package--state nil)

;; ✓ Predicates - end with -p
(defun my-package-enabled-p () ...)

;; ✓ Hooks - end with -hook
(defvar my-package-mode-hook nil)

;; ✓ Modes - end with -mode
(define-derived-mode my-package-mode ...)

;; ✗ WRONG - missing prefix
(defun initialize () ...)  ; Conflicts!
```

### Buffer and Text Manipulation

**Point and Region Operations**

Always use `save-excursion` when moving point temporarily:

```elisp
(defun my-count-defuns ()
  "Count defun forms in buffer."
  (save-excursion
    (goto-char (point-min))
    (let ((count 0))
      (while (re-search-forward "^(defun " nil t)
        (setq count (1+ count)))
      count)))
```

Use markers for positions that should track insertions:

```elisp
(defun my-insert-at-start (text)
  "Insert TEXT at buffer start, maintaining other positions."
  (let ((old-point (point-marker)))  ; Marker tracks movement
    (goto-char (point-min))
    (insert text)
    (goto-char old-point)
    (set-marker old-point nil)))  ; Clean up marker
```

Region-aware commands check for active region:

```elisp
(defun my-operate (start end)
  "Operate on region or whole buffer."
  (interactive (if (use-region-p)
                   (list (region-beginning) (region-end))
                 (list (point-min) (point-max))))
  (save-excursion
    (goto-char start)
    ;; Process region
    ))
```

**Text Properties vs Overlays**

Use text properties for syntax highlighting and properties that should persist with text:

```elisp
;; Text properties - part of buffer text
(put-text-property 1 10 'face 'bold)
(put-text-property 1 10 'help-echo "Tooltip text")
(get-text-property (point) 'face)
```

Use overlays for temporary highlighting and UI elements that shouldn't copy with text:

```elisp
;; Overlays - independent objects
(setq my-overlay (make-overlay 1 10))
(overlay-put my-overlay 'face 'highlight)
(overlay-put my-overlay 'before-string "→ ")
(overlay-put my-overlay 'priority 100)

;; Cleanup
(delete-overlay my-overlay)
```

Use overlays sparingly (under 100) as they have O(n) overhead for some operations.

**Narrowing and Restriction**

Use `save-restriction` operating on full buffer content:

```elisp
(defun my-count-all-lines ()
  "Count lines in entire buffer, ignoring narrowing."
  (save-restriction
    (widen)
    (count-lines (point-min) (point-max))))

(defun my-process-function ()
  "Process current function only."
  (save-excursion
    (save-restriction
      (narrow-to-defun)
      (goto-char (point-min))
      (while (re-search-forward pattern nil t)
        (replace-match replacement)))))
```

## Best Practices

### Code Organization

**File Structure**

```elisp
;;; package-name.el --- Description -*- lexical-binding: t; -*-

;; Package metadata (Author, Version, Package-Requires, etc.)

;;; Commentary:
;; Usage documentation

;;; Code:

;; 1. Required libraries
(require 'cl-lib)

;; 2. Custom group and variables
(defgroup my-package nil ...)
(defcustom my-option t ...)

;; 3. Internal state
(defvar my-package--state nil)

;; 4. Public API functions
;;;###autoload
(defun my-package-command () ...)

;; 5. Internal helper functions
(defun my-package--helper () ...)

;; 6. Mode definitions
(define-derived-mode my-mode ...)

(provide 'my-package)
;;; package-name.el ends here
```

**Documentation Standards**

Write clear, complete docstrings:

```elisp
(defun my-function (filename &optional buffer create)
  "Process FILENAME and optionally insert results in BUFFER.

FILENAME must be absolute path to existing file.
If BUFFER nil, use current buffer.
If CREATE non-nil, create BUFFER if doesn't exist.

Returns list (LINES WORDS CHARACTERS), or nil if
processing fails.

Example:
  (my-function \"/tmp/test.txt\" nil t)
  => (10 50 250)"
  ...)
```

**Error Handling**

Always handle errors appropriately:

```elisp
(defun my-safe-function (arg)
  "Process ARG with error handling."
  (condition-case err
      (progn
        (validate-arg arg)
        (process-arg arg))
    (file-error
     (message "File error: %s" (error-message-string err))
     nil)
    (error
     (message "Unexpected error: %s" err)
     (signal (car err) (cdr err)))))  ; Re-signal unknown errors
```
