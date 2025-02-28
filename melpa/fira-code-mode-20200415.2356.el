;;; fira-code-mode.el --- Minor mode for Fira Code ligatures using prettify-symbols
;; -*- lexical-binding: t; -*-

;; Copyright (C) 2020 Jonathan Ming

;; Author: Jonathan Ming <jming422@gmail.com>
;; Version: 1.0
;; Package-Version: 20200415.2356
;; Package-Requires: ((emacs "24.4"))
;; Keywords: faces, ligatures, fonts, programming-ligatures
;; URL: https://github.com/jming422/fira-code-mode


;; This file is not part of GNU Emacs.

;;; License:

;; fira-code-mode is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; fira-code-mode is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with fira-code-mode.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; Minor mode for Fira Code ligatures, built from these instructions:
;; https://github.com/tonsky/FiraCode/wiki/Emacs-instructions#using-prettify-symbols
;;
;; NOTE: Requires installing the Fira Code Symbol font from here:
;; https://github.com/tonsky/FiraCode/issues/211#issuecomment-239058632

;;; Code:

;; Customizable variables:
(defgroup fira-code-ligatures nil
  "Fira Code ligature settings."
  :version "0.0.1"
  :group 'faces)

(defcustom fira-code-mode-disabled-ligatures ()
  "Add a string to this list to prevent it from being displayed with a ligature.

After editing this variable, any buffers that previously had the ligature minor mode enabled
will need to disable and re-enable the mode in order for the edits to take effect."
  :type '(repeat string) ;; TODO: Make this of type `set'
  :group 'fira-code-ligatures)

(defcustom fira-code-mode-enable-hex-literal t
  "When non-nil, display the \"x\" in hex literals with a ligature.
e.g. 0x12 displays as 012

When this option is enabled, command `fira-code-mode' adds a font-lock keyword
in order to support displaying \"x\" as a ligature when preceded by a 0.

Note that adding \"x\" to the list of disabled ligatures does not effect this
option; if \"x\" is disabled but this option is enabled, then strings like
\"0xE16B\" will have a ligature, while ones like \"0 x 1\" will not."
  :type 'boolean
  :group 'fira-code-ligatures)


;; The sauce. Stuff we need to feed to `prettify-symbols':
(defun fira-code-mode--make-alist (list)
  "Generate `prettify-symbols-alist' additions from LIST."
  (let ((idx -1))
    (delq nil
          (mapcar
           (lambda (s)
             (setq idx (1+ idx))
             (when s
               (let* ((code (+ #Xe100 idx))
                      (width (string-width s))
                      (prefix ())
                      (suffix '(?\s (Br . Br)))
                      (n 1))
                 (while (< n width)
                   (setq prefix (append prefix '(?\s (Br . Bl))))
                   (setq n (1+ n)))
                 (cons s (append prefix suffix (list (decode-char 'ucs code)))))))
           list))))

(defconst fira-code-mode--all-ligatures
  '("www" "**" "***" "**/" "*>" "*/" "\\\\" "\\\\\\" "{-" "[]" "::"
    ":::" ":=" "!!" "!=" "!==" "-}" "--" "---" "-->" "->" "->>" "-<"
    "-<<" "-~" "#{" "#[" "##" "###" "####" "#(" "#?" "#_" "#_(" ".-"
    ".=" ".." "..<" "..." "?=" "??" ";;" "/*" "/**" "/=" "/==" "/>"
    "//" "///" "&&" "||" "||=" "|=" "|>" "^=" "$>" "++" "+++" "+>"
    "=:=" "==" "===" "==>" "=>" "=>>" "<=" "=<<" "=/=" ">-" ">=" ">=>"
    ">>" ">>-" ">>=" ">>>" "<*" "<*>" "<|" "<|>" "<$" "<$>" "<!--"
    "<-" "<--" "<->" "<+" "<+>" "<=" "<==" "<=>" "<=<" "<>" "<<" "<<-"
    "<<=" "<<<" "<~" "<~~" "</" "</>" "~@" "~-" "~=" "~>" "~~" "~~>"
    "%%" "x" ":" "+" "+" "*"))

(defun fira-code-mode--ligatures ()
  "Generate a list of all ligatures not disabled via `fira-code-mode-disabled-ligatures'."
  (mapcar
   (lambda (s)
     (if (member s fira-code-mode-disabled-ligatures)
         nil ;; The list must retain the same number of elements, with `nil' in-place for disabled ligatures.
       s))
   fira-code-mode--all-ligatures))


;; Patch for the hex literal (e.g. 0x1234) ligature using `font-lock-keywords'
(defconst fira-code-mode--hex-ligature-keyword '(("0\\(x\\)" 1 '(face nil display ""))))

(defun fira-code-mode--patch-hex-ligature ()
  "Patch `font-lock-keywords' with an entry for 0x-style hex literals."
  (unless (member 'display font-lock-extra-managed-props)
    (push 'display font-lock-extra-managed-props))
  (font-lock-add-keywords nil fira-code-mode--hex-ligature-keyword)
  (if (fboundp 'font-lock-flush)
      (font-lock-flush)
    (when font-lock-mode
      (with-no-warnings (font-lock-fontify-buffer)))))

(defun fira-code-mode--unpatch-hex-ligature ()
  "Unpatch `font-lock-keywords' with an entry for 0x-style hex literals."
  (font-lock-remove-keywords nil fira-code-mode--hex-ligature-keyword)
  (if (fboundp 'font-lock-flush)
      (font-lock-flush)
    (when font-lock-mode
      (with-no-warnings (font-lock-fontify-buffer)))))


;; Minor mode definitions
(defvar-local fira-code-mode--enabled-prettify-mode nil)
(defvar fira-code-mode--old-prettify-alist)

(defun fira-code-mode--enable ()
  "Enable Fira Code ligatures in current buffer."
  (setq-local fira-code-mode--old-prettify-alist prettify-symbols-alist)
  (setq-local prettify-symbols-alist (append
                                      (fira-code-mode--make-alist (fira-code-mode--ligatures))
                                      fira-code-mode--old-prettify-alist))
  (unless prettify-symbols-mode
    (prettify-symbols-mode t)
    (setq-local fira-code-mode--enabled-prettify-mode t))
  (when fira-code-mode-enable-hex-literal
    (fira-code-mode--patch-hex-ligature)))

(defun fira-code-mode--disable ()
  "Disable Fira Code ligatures in current buffer."
  (fira-code-mode--unpatch-hex-ligature)
  (setq-local prettify-symbols-alist fira-code-mode--old-prettify-alist)
  (when fira-code-mode--enabled-prettify-mode
    (prettify-symbols-mode -1)
    (setq-local fira-code-mode--enabled-prettify-mode nil)))

;;;###autoload
(define-minor-mode fira-code-mode
  "Fira Code ligatures minor mode"
  :lighter "  \xe15b"
  :group 'fira-code-ligatures
  (unless (display-graphic-p)
    (display-warning '(fira-code-ligatures) "Warning: fira-code-mode probably won't work for non-graphical displays!"))
  (setq-local prettify-symbols-unprettify-at-point 'right-edge)
  (if fira-code-mode
      (fira-code-mode--enable)
    (fira-code-mode--disable)))

;;;###autoload
(define-globalized-minor-mode global-fira-code-mode fira-code-mode
  fira-code-mode)

;; Extra utility functions
(defun fira-code-mode--setup ()
  "Setup Fira Code Symbols font.
The following function isn't normally required, but if the range #Xe100 to
#Xe16f has been previously customized by `set-fontset-font', then this function
will ensure that this range is resolved using the Fira Code Symbol font instead."
  (set-fontset-font t '(#Xe100 . #Xe16f) "Fira Code Symbol")
  (message "Finished setting up the Fira Code Symbol font."))


(provide 'fira-code-mode)
;;; fira-code-mode.el ends here
