;;; with-shell-interpreter.el --- Helper for shell command APIs -*- lexical-binding: t; -*-

;; Copyright (C) 2019-2020 Jordan Besly
;;
;; Version: 0.1.0
;; Package-Version: 20200504.1225
;; Keywords: processes, terminals
;; URL: https://github.com/p3r7/with-shell-interpreter
;; Package-Requires: ((emacs "25.1")(cl-lib "0.6.1"))
;;
;; SPDX-License-Identifier: MIT

;;; Commentary:
;;
;; Helper macro for Emacs shell command APIs, making implicit argument as explicit keyword arguments.
;; Provides macro `with-shell-interpreter'.
;;
;; For detailed instructions, please look at the README.md at https://github.com/p3r7/with-shell-interpreter/blob/master/README.md

;;; Code:



;; REQUIRES

(require 'cl-lib)

(require 'files-x)
(require 'shell)



;; VARS

(defvar with-shell-interpreter-default-remote "/bin/bash"
  "For remote shells, default interpreter exec to fallback to if :interpreter \
is not specified.
Let-binds `explicit-shell-file-name' and `shell-file-name'.")

(defvar with-shell-interpreter-default-remote-args '("-c" "export EMACS=; export TERM=dumb; stty echo; bash")
  "For remote shells, default interpreter args to fallback to if \
:interpreter-args is not specified and :interpreter is equal to \
`with-shell-interpreter-default-remote'.
Let-binds `explicit-INTEPRETER-args'")

(defvar with-shell-interpreter-default-remote-command-switch "-c"
  "For remote shells, default interpreter command switch to fallback to if \
:command-switch is not specified.
Let-binds `shell-command-switch'")



;; COMPATIBILITY

;; NB: connection-local variables are only available since version 26.1
(eval-when-compile
  (if (fboundp 'hack-connection-local-variables)
      (defalias 'with-shell-interpreter--hack-connection-local-variables #'hack-connection-local-variables)
    (defalias 'with-shell-interpreter--hack-connection-local-variables (lambda (_c) nil))))

;; NB: only bound on Windows build of Emacs
(unless (boundp 'w32-quote-process-args)
  ;; tame lexical binding warnings
  (defvar w32-quote-process-args))



;; MAIN HELPER

(defmacro with-shell-interpreter (&rest args)
  "Eval :form at location described by :path with :interpreter binary.

ARGS are in fact keywords, `with-shell-interpreter' being a macro wrapper around
`with-shell-interpreter-eval'.  Usage:

  (with-shell-interpreter
     [:keyword [option]]...
     :form
     ;; actual code
     )

:form               Code to execute.
:path               Location from which form is executed.
                    Can be local or remote (TRAMP format).
                    Let-binds `default-directory'.
:interpreter        Name or absolute path of shell interpreter executable.
                    If only providing a name, ensure that the executable
                    is present in the PATH.
                    Let-binds `explicit-shell-file-name' and
                    `shell-file-name'.
:interpreter-args   Login args to call interpreter with for login.
                    Let-binds `explicit-INTEPRETER-args'.
                    Useful only for interactive shells.
:command-switch     Command switch arg for asking interpreter to run a
                    shell command (e.g. \"-c\" in bourne shell and most
                    derivatives).
                    Let-binds `shell-command-switch'.
                    Useful only for single shell commands.
:w32-arg-quote      Only affecting Microsoft Windows build of Emacs.
                    Character to use for quoting arguments.
                    Let-binds `w32-quote-process-args'.
:allow-local-vars   Allow local values to have precedence over global ones
                    for:
                     - `explicit-shell-file-name'
                     - `explicit-INTEPRETER-args'
                     - `shell-command-switch'
                     - `w32-quote-process-args'
                    Value can be:
                      - 'buffer: allow buffer-local vars values
                      - 'connection: allow connection-local values
                      - 'both: allow both types of local values
                      - 'none: ignore all local values
                    Default is 'connection.

For more detailed instructions, have a look at https://github.com/p3r7/with-shell-interpreter/blob/master/README.md"
  (declare (indent 1) (debug t))
  `(with-shell-interpreter-eval
    :form (lambda () ,(cons 'progn (with-shell-interpreter--plist-get args :form)))
    :path ,(plist-get args :path)
    :interpreter ,(plist-get args :interpreter)
    :interpreter-args ,(plist-get args :interpreter-args)
    :command-switch ,(plist-get args :command-switch)
    :w32-arg-quote ,(plist-get args :w32-arg-quote)
    :allow-local-vars ,(plist-get args :allow-local-vars)))

(put 'with-shell-interpreter 'lisp-indent-function 'defun)

(cl-defun with-shell-interpreter-eval (&key form path
                                            interpreter interpreter-args command-switch
                                            w32-arg-quote
                                            allow-local-vars)
  "Same as `with-shell-interpreter' except :form has to be a quoted sexp."
  (unless path
    (setq path default-directory))
  (unless (file-exists-p path)
    (error "Path %s doesn't seem to exist" path))

  (let* ((func
          (if (functionp form) form
            ;; Try to use the "current" lexical/dynamic mode for `form'.
            (eval `(lambda () ,form) lexical-binding)))
         (is-remote (file-remote-p path))
         (allow-local-vars (or allow-local-vars 'connection))
         (ignore-buffer-local-vars (not (member allow-local-vars '(buffer both))))
         (ignore-cnnx-local-vars (not (member allow-local-vars '(connection both))))
         (cnnx-local-vars (with-shell-interpreter--get-cnnx-local-vars path))
         (interpreter (with-shell-interpreter--get-interpreter-value is-remote ignore-buffer-local-vars
                                                                     ignore-cnnx-local-vars cnnx-local-vars
                                                                     interpreter))
         (interpreter-name (with-shell-interpreter--get-interpreter-name interpreter))
         (explicit-interpreter-args-var (intern (concat "explicit-" interpreter-name "-args")))
         (interpreter-args (with-shell-interpreter--get-interpreter-args-value is-remote explicit-interpreter-args-var
                                                                               interpreter
                                                                               ignore-buffer-local-vars
                                                                               ignore-cnnx-local-vars cnnx-local-vars
                                                                               interpreter-args))
         (command-switch (with-shell-interpreter--get-command-switch is-remote interpreter
                                                                     ignore-buffer-local-vars
                                                                     ignore-cnnx-local-vars cnnx-local-vars
                                                                     command-switch))
         ;; bellow are vars acting as implicit options to shell functions
         (default-directory path)
         (shell-file-name interpreter)
         (explicit-shell-file-name interpreter)
         (shell-command-switch command-switch)
         (enable-connection-local-variables nil) ; disable lookup of connection-local vars in :form
         ;; NB: w32-only feature
         (w32-quote-process-args (with-shell-interpreter--get-w32-quote-process-args is-remote interpreter
                                                                                     ignore-buffer-local-vars
                                                                                     ignore-cnnx-local-vars cnnx-local-vars
                                                                                     w32-arg-quote)))
    (cl-progv
        (list explicit-interpreter-args-var)
        (list interpreter-args)
      (funcall func))))



;; PRIVATE HELPERS

(defun with-shell-interpreter--normalize-path (path)
  "Normalize PATH, converting \\ into /."
  ;; REVIEW: shouldn't we just use instead `convert-standard-filename'
  ;; or even `executable-find'?
  (subst-char-in-string ?\\ ?/ path))


(defun with-shell-interpreter--get-interpreter-name (interpreter)
  "Extracts INTERPRETER name, keeping extension."
  (file-name-nondirectory interpreter))


(defun with-shell-interpreter--plist-get (plist prop)
  "Extract value of property PROP from property list PLIST.
Like `plist-get' except allows value to be multiple elements."
  (when plist
    (cl-loop with passed = nil
             for e in plist
             until (and passed
                        (keywordp e)
                        (not (eq e prop)))
             if (and passed
                     (not (keywordp e)))
             collect e
             else if (and (not passed)
                          (keywordp e)
                          (eq e prop))
             do (setq passed 't))))


(defun with-shell-interpreter--symbol-value (sym &optional ignore-buffer-local)
  "Return the value of SYM in current buffer.
If IGNORE-BUFFER-LOCAL is nil, always return global value (never buffer-local one)."
  (if ignore-buffer-local
      ;; NB: if local-only `default-value' throws an error
      (ignore-errors
        (default-value sym))
    (symbol-value sym)))


(defun with-shell-interpreter--boundp-buffer-local (symbol)
  "Return t if SYMBOL has a buffer-local value.
Even works if it's value is nil."
  (assoc symbol (buffer-local-variables)))


(defun with-shell-interpreter--get-cnnx-local-vars (path)
  "Get connection-local-vars for PATH."
  (when (file-remote-p path)
    (let (output)
      (with-temp-buffer
        (with-shell-interpreter--hack-connection-local-variables
         `(
           ;; REVIEW: only those props in criteria?
           ;; this is what `shell' uses, but maybe can we do better?
           :application tramp
           :protocol ,(file-remote-p path 'method)
           :user ,(file-remote-p path 'user)
           :machine ,(file-remote-p path 'host)))
        (setq output connection-local-variables-alist))
      output)))


(defun with-shell-interpreter--get-interpreter-value (is-remote
                                                      &optional ignore-buffer-local-vars
                                                      ignore-cnnx-local-vars cnnx-local-vars
                                                      input-value)
  "Determine value of shell interpreter.
Use INPUT-VALUE if not empty, else fallback to default values, depending on
CNNX-LOCAL-VARS and whether:
 - IS-REMOTE or not
 - IGNORE-BUFFER-LOCAL-VARS or not
 - IGNORE-CNNX-LOCAL-VARS or not

The order of precedence is like so:
 - input value
 - buffer-local value (if IGNORE-BUFFER-LOCAL-VARS is false)
 - connection-local value (if IGNORE-CNNX-LOCAL-VARS is false)
 - default remote value
 - global value"
  (with-shell-interpreter--normalize-path
   (or input-value
       ;; buffer-local value
       (when (and (not ignore-buffer-local-vars)
                  (with-shell-interpreter--boundp-buffer-local 'explicit-shell-file-name))
         (with-shell-interpreter--symbol-value 'explicit-shell-file-name nil))
       (when (and (not ignore-buffer-local-vars)
                  (with-shell-interpreter--boundp-buffer-local 'shell-file-name))
         (with-shell-interpreter--symbol-value 'shell-file-name nil))
       ;; connection-local value
       (when (and is-remote
                  (not ignore-cnnx-local-vars))
         (or (alist-get 'explicit-shell-file-name cnnx-local-vars)
             (alist-get 'shell-file-name cnnx-local-vars)))
       ;; default remote interpreter value
       (when is-remote
         with-shell-interpreter-default-remote)
       ;; global value
       (ignore-errors
         (with-shell-interpreter--symbol-value 'explicit-shell-file-name ignore-buffer-local-vars))
       (ignore-errors
         (with-shell-interpreter--symbol-value 'shell-file-name ignore-buffer-local-vars)))))


(defun with-shell-interpreter--get-interpreter-args-value (is-remote args-var-name interpreter
                                                                     &optional ignore-buffer-local-vars
                                                                     ignore-cnnx-local-vars cnnx-local-vars
                                                                     input-value)
  "Determine value of shell interpreter.
Use INPUT-VALUE if not empty, else fallback to default values, depending on
 ARGS-VAR-NAME, INTERPRETER, CNNX-LOCAL-VARS and whether:
 - IS-REMOTE or not
 - IGNORE-BUFFER-LOCAL-VARS or not
 - IGNORE-CNNX-LOCAL-VARS or not

The order of precedence is like so:
 - input value
 - buffer-local value (if IGNORE-BUFFER-LOCAL-VARS is false)
 - connection-local value (if IGNORE-CNNX-LOCAL-VARS is false)
 - default remote value (if INTERPRETER is default remote interpreter)
 - global value
 - universal fallback value"
  (or input-value
      ;; buffer-local value
      (when (and (not ignore-buffer-local-vars)
                 (with-shell-interpreter--boundp-buffer-local args-var-name))
        (with-shell-interpreter--symbol-value args-var-name nil))
      ;; connection-local value
      (when (and is-remote
                 (not ignore-cnnx-local-vars)
                 (or
                  (string= interpreter (assoc 'explicit-shell-file-name cnnx-local-vars))
                  (string= interpreter (assoc 'shell-file-name cnnx-local-vars))))
        (alist-get args-var-name cnnx-local-vars))
      ;; default remote interpreter value
      (when (and is-remote
                 (string= interpreter with-shell-interpreter-default-remote))
        with-shell-interpreter-default-remote-args)
      ;; global value
      (ignore-errors
        (with-shell-interpreter--symbol-value args-var-name t))
      ;; universal fallback value
      '("-i")))


(defun with-shell-interpreter--get-command-switch (is-remote interpreter
                                                             &optional ignore-buffer-local-vars
                                                             ignore-cnnx-local-vars cnnx-local-vars
                                                             input-value)
  "Determine value of shell command switch.
Use INPUT-VALUE if not empty, else fallback to default values, depending on
 INTERPRETER, CNNX-LOCAL-VARS and whether:
 - IS-REMOTE or not
 - IGNORE-BUFFER-LOCAL-VARS or not
 - IGNORE-CNNX-LOCAL-VARS or not

The order of precedence is like so:
 - input value
 - buffer-local value (if IGNORE-BUFFER-LOCAL-VARS is false)
 - connection-local value (if IGNORE-CNNX-LOCAL-VARS is false)
 - default remote value (if INTERPRETER is default remote interpreter)
 - global value
 - universal fallback value"
  (or input-value
      ;; buffer-local value
      (when (and (not ignore-buffer-local-vars)
                 (with-shell-interpreter--boundp-buffer-local 'shell-command-switch))
        (with-shell-interpreter--symbol-value 'shell-command-switch nil))
      ;; connection-local value
      (when (and is-remote
                 (not ignore-cnnx-local-vars)
                 (or
                  (string= interpreter (assoc 'explicit-shell-file-name cnnx-local-vars))
                  (string= interpreter (assoc 'shell-file-name cnnx-local-vars))))
        (alist-get 'shell-command-switch cnnx-local-vars))
      ;; default remote interpreter value
      (when (and is-remote
                 (string= interpreter with-shell-interpreter-default-remote))
        with-shell-interpreter-default-remote-command-switch)
      ;; global value
      (ignore-errors
        (with-shell-interpreter--symbol-value 'shell-command-switch t))
      ;; universal fallback value
      "-c"))


(defun with-shell-interpreter--get-w32-quote-process-args (is-remote interpreter
                                                                     &optional ignore-buffer-local-vars
                                                                     ignore-cnnx-local-vars cnnx-local-vars
                                                                     input-value)
  "Determine value of shell command switch.
Use INPUT-VALUE if not empty, else fallback to default values, depending on
 INTERPRETER, CNNX-LOCAL-VARS and whether:
 - IS-REMOTE or not
 - IGNORE-BUFFER-LOCAL-VARS or not
 - IGNORE-CNNX-LOCAL-VARS or not

The order of precedence is like so:
 - input value
 - buffer-local value (if IGNORE-BUFFER-LOCAL-VARS is false)
 - connection-local value (if IGNORE-CNNX-LOCAL-VARS is false)
 - global value"
  (or input-value
      ;; buffer-local value
      (when (and (not ignore-buffer-local-vars)
                 (with-shell-interpreter--boundp-buffer-local 'w32-quote-process-args))
        (with-shell-interpreter--symbol-value 'w32-quote-process-args nil))
      ;; connection-local value
      (when (and is-remote
                 (not ignore-cnnx-local-vars)
                 (or
                  (string= interpreter (assoc 'explicit-shell-file-name cnnx-local-vars))
                  (string= interpreter (assoc 'shell-file-name cnnx-local-vars))))
        (alist-get 'shell-command-switch cnnx-local-vars))
      ;; global value
      (ignore-errors
        (with-shell-interpreter--symbol-value 'w32-quote-process-args ignore-buffer-local-vars))))




(provide 'with-shell-interpreter)

;;; with-shell-interpreter.el ends here
