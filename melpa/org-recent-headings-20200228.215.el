;;; org-recent-headings.el --- Jump to recently used Org headings  -*- lexical-binding: t -*-

;; Author: Adam Porter <adam@alphapapa.net>
;; Url: http://github.com/alphapapa/org-recent-headings
;; Package-Version: 20200228.215
;; Version: 0.2-pre
;; Package-Requires: ((emacs "26.1") (org "9.0.5") (dash "2.13.0") (dash-functional "1.2.0") (frecency "0.1") (s "1.12.0"))
;; Keywords: hypermedia, outlines, Org

;;; Commentary:

;; This package keeps a list of recently used Org headings and lets
;; you quickly choose one to jump to by calling one of these commands:

;; The list is kept by advising functions that are commonly called to
;; access headings in various ways.  You can customize this list in
;; `org-recent-headings-advise-functions'.  Suggestions for additions
;; to the default list are welcome.

;; Note: This probably works with Org 8 versions, but it's only been
;; tested with Org 9.

;; This package makes use of handy functions and settings in
;; `recentf'.

;;; Installation:

;; Install from MELPA, or manually by putting this file in your
;; `load-path'.  Then put this in your init file:

;; (require 'org-recent-headings)
;; (org-recent-headings-mode)

;; You may also install Helm and/or Ivy, but they aren't required.

;;; Usage:

;; Activate `org-recent-headings-mode' to install the advice that will
;; track recently used headings.  Then play with your Org files by
;; going to headings from the Agenda, calling
;; `org-tree-to-indirect-buffer', etc.  Then call one of these
;; commands to jump to a heading:

;; + `org-recent-headings'
;; + `org-recent-headings-ivy'
;; + `org-recent-headings-helm'

;;; License:

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;; Code:

;;;; Requirements

(require 'cl-lib)
(require 'org)
(require 'org-agenda)
(require 'recentf)
(require 'seq)
(require 'subr-x)

(require 'dash)
(require 'dash-functional)
(require 'frecency)
(require 's)

;;;; Structs

(cl-defstruct org-recent-headings-entry
  (id) (file) (outline-path) (display) (frecency))

;;;; Variables

(defvar org-recent-headings-debug nil
  "When non-nil, enable debug warnings.")

(defvar org-recent-headings-list nil
  "List of recent Org headings.")

(defconst org-recent-headings-save-file-header
  ";;; Automatically generated by `org-recent-headings' on %s.\n"
  "Header to be written into the `org-recent-headings-save-file'.")

(defgroup org-recent-headings nil
  "Jump to recently used Org headings."
  :group 'org)

(defcustom org-recent-headings-advise-functions
  '(org-agenda-goto org-agenda-show org-agenda-show-mouse org-show-entry
                    org-reveal org-refile org-tree-to-indirect-buffer
                    org-bookmark-jump
                    helm-org-parent-headings helm-org-in-buffer-headings
                    helm-org-agenda-files-headings helm-org-bookmark-jump-indirect)
  "Functions to advise to store recent headings.
Whenever one of these functions is called, the heading for the
entry at point will be added to the recent-headings list.  This
means that the point should be in a regular Org buffer (i.e. not
an agenda buffer)."
  ;; FIXME: This needs to toggle the mode when set, if it's active
  ;; MAYBE: Add `org-cycle', or make a special option for it.
  :type '(repeat function))

(defcustom org-recent-headings-store-heading-hooks '(org-capture-prepare-finalize-hook)
  "Hooks to add heading-storing function to."
  :type '(repeat variable))

(defcustom org-recent-headings-candidate-number-limit 10
  "Number of candidates to display in Helm source."
  :type 'integer)

(defcustom org-recent-headings-save-file (locate-user-emacs-file "org-recent-headings")
  "File to save the recent Org headings list into."
  :type 'file
  :initialize 'custom-initialize-default
  :set (lambda (symbol value)
         (let ((oldvalue (eval symbol)))
           (custom-set-default symbol value)
           (and (not (equal value oldvalue))
                org-recent-headings-mode
                (org-recent-headings--load-list)))))

(defcustom org-recent-headings-show-entry-function 'org-recent-headings--show-entry-indirect
  "Default function to use to show selected entries."
  :type '(radio (function :tag "Show entries in real buffers." org-recent-headings--show-entry-direct)
                (function :tag "Show entries in indirect buffers." org-recent-headings--show-entry-indirect)
                (function :tag "Custom function")))

(defcustom org-recent-headings-list-size 200
  "Maximum size of recent headings list."
  :type 'integer)

(defcustom org-recent-headings-reverse-paths nil
  "Reverse outline paths.
This way, the most narrowed-down heading will be listed first."
  :type 'boolean)

(defcustom org-recent-headings-truncate-paths-by 12
  "Truncate outline paths by this many characters.
Depending on your org-level faces, you may want to adjust this to
prevent paths from being wrapped onto a second line."
  :type 'integer)

(defcustom org-recent-headings-use-ids 'when-available
  "Use Org IDs to find headings instead of file/outline paths.
Org IDs are more flexible, because Org may be able to find them
when headings are refiled to other files or locations.  Also,
file/outline paths can be ambiguous if a file's outline has
multiple headings with the same name.  But finding by ID may
cause Org to load other Org files while searching for an ID,
which takes time, so some users may prefer to just use
file/outline paths, which will always search only one file."
  :type '(radio (const :tag "Never: just use file/outline paths" nil)
                (const :tag "When an ID already exists" when-available)
                (const :tag "Always: create new IDs when necessary" always)))

(defcustom org-recent-headings-reject-any-fns nil
  "Functions used to test potential headings.
If any function in this list returns non-nil, the heading is not
saved.  Functions are called with one argument, an entry, which
is returned by function `org-recent-headings--current-entry',
which see."
  :type '(repeat function))

;;;; Minor mode

;;;###autoload
(define-minor-mode org-recent-headings-mode
  "Global minor mode to keep a list of recently used Org headings so they can be quickly selected and jumped to.
With prefix argument ARG, turn on if positive, otherwise off."
  :global t
  (let ((advice-function (if org-recent-headings-mode
                             (lambda (to fun)
                               ;; Enable mode
                               (advice-add to :after fun))
                           (lambda (from fun)
                             ;; Disable mode
                             (advice-remove from fun))))
        (hook-setup (if org-recent-headings-mode 'add-hook 'remove-hook)))
    (dolist (target org-recent-headings-advise-functions)
      (when (fboundp target)
        (funcall advice-function target 'org-recent-headings--store-heading)))
    (dolist (hook org-recent-headings-store-heading-hooks)
      (funcall hook-setup hook 'org-recent-headings--store-heading))
    ;; Add/remove save hook
    (funcall hook-setup 'kill-emacs-hook 'org-recent-headings--save-list)
    ;; Load/save list
    (if org-recent-headings-mode
        (org-recent-headings--load-list)
      (org-recent-headings--save-list))
    ;; Display message
    (if org-recent-headings-mode
        (message "org-recent-headings-mode enabled.")
      (message "org-recent-headings-mode disabled."))))

;;;; Commands

;;;;; Plain completing-read

(defun org-recent-headings ()
  "Choose from recent Org headings."
  (interactive)
  (org-recent-headings--prepare-list)
  (let* ((heading-display-strings (-map #'org-recent-headings-entry-display org-recent-headings-list))
         (selected-heading (completing-read "Heading: " heading-display-strings))
         ;; FIXME: If there are two headings with the same name, this will only
         ;; pick the first one.  I guess it won't happen if full-paths are used,
         ;; which most likely will be, but maybe it should still be fixed.
         (entry (car (--select (string= selected-heading (org-recent-headings-entry-display it))
                               org-recent-headings-list))))
    (funcall org-recent-headings-show-entry-function entry)))

;;;;; Helm

(with-eval-after-load 'helm

  ;; This declaration is absolutely necessary for some reason.  Even if `helm' is loaded
  ;; before this package is loaded, an "invalid function" error will be raised when this
  ;; package is loaded, unless this declaration is here.  Even if I manually "(require
  ;; 'helm)" and then load this package after the error (and Helm is already loaded, and I've
  ;; verified that `helm-build-sync-source' is defined), once Emacs has tried to load this
  ;; package thinking that the function is invalid, it won't stop thinking it's invalid.  It
  ;; also seems to be related to `defvar' not doing anything when run a second time (unless
  ;; called with `eval-defun').  But at the same time, the error didn't always happen in my
  ;; config, or with different combinations of `with-eval-after-load', "(when (fboundp 'helm)
  ;; ...)", and loading packages in a different order.  I don't know exactly why it's
  ;; happening, but at the moment, this declaration seems to fix it.  Let us hope it really
  ;; does.  I hope no one else is suffering from this, because if so, I have inflicted mighty
  ;; annoyances upon them, and I wouldn't blame them if they never used this package again.
  (declare-function helm-build-sync-source "helm")
  (declare-function helm-exit-and-execute-action "helm")
  (declare-function helm-marked-candidates "helm")
  (declare-function with-helm-alive-p "helm")
  (declare-function helm-make-actions "helm-lib")

  (defvar helm-map)
  (defvar org-recent-headings-helm-map
    (let ((map (copy-keymap helm-map)))
      (define-key map (kbd "<C-return>") 'org-recent-headings--show-entry-indirect-helm-action)
      map)
    "Keymap for `helm-source-org-recent-headings'.")

  (defvar helm-source-org-recent-headings
    (helm-build-sync-source " Recent Org headings"
      :candidates (lambda ()
                    (org-recent-headings--prepare-list)
                    org-recent-headings-list)
      :candidate-number-limit 'org-recent-headings-candidate-number-limit
      :candidate-transformer 'org-recent-headings--truncate-candidates
      ;; FIXME: If `org-recent-headings-helm-map' is changed after this `defvar' is
      ;; evaluated, the keymap used in the source is not changed, which is very confusing
      ;; for users (including myself).  Maybe we should build the source at runtime.
      :keymap org-recent-headings-helm-map
      :action (helm-make-actions
               "Show entry (default function)" 'org-recent-headings--show-entry-default
               "Show entry in real buffer" 'org-recent-headings--show-entry-direct
               "Show entry in indirect buffer" 'org-recent-headings--show-entry-indirect
               "Remove entry" 'org-recent-headings-helm-remove-entries
               "Bookmark heading" 'org-recent-headings--bookmark-entry))
    "Helm source for `org-recent-headings'.")

  (defun org-recent-headings--show-entry-indirect-helm-action ()
    "Action to call `org-recent-headings--show-entry-indirect' from Helm session keymap."
    (interactive)
    (with-helm-alive-p
      (helm-exit-and-execute-action 'org-recent-headings--show-entry-indirect)))

  (defun org-recent-headings-helm ()
    "Choose from recent Org headings with Helm."
    (interactive)
    (helm :sources helm-source-org-recent-headings))

  (defun org-recent-headings--truncate-candidates (candidates)
    "Return CANDIDATES with their DISPLAY string truncated to frame width."
    ;; MAYBE: Can't we just truncate lines in the Helm buffer?
    (cl-loop with width = (- (frame-width) org-recent-headings-truncate-paths-by)
             for entry in candidates
             for display = (org-recent-headings-entry-display entry)
             ;; FIXME: Why using setf here instead of just collecting the result of s-truncate?
             collect (cons (setf display (s-truncate width display))
                           entry)))

  (cl-defun org-recent-headings-helm-remove-entries (&rest _ignore)
    "Remove selected/marked candidates from recent headings list."
    (--each (helm-marked-candidates)
      (org-recent-headings--remove-entry it))))

;;;;; Ivy

(with-eval-after-load 'ivy

  ;; TODO: Might need to declare `ivy-completing-read' also, but I
  ;; haven't hit the error yet.

  (defun org-recent-headings-ivy ()
    "Choose from recent Org headings with Ivy."
    (interactive)
    (let ((completing-read-function  #'ivy-completing-read))
      (org-recent-headings))))

;;;; Functions

(defun org-recent-headings--bookmark-entry (entry)
  "Bookmark heading specified by ENTRY."
  (org-with-point-at (org-recent-headings--entry-marker entry)
    (bookmark-set)))

(defun org-recent-headings--remove-entry (entry)
  "Remove ENTRY from recent headings list."
  (setf org-recent-headings-list
        (cl-remove entry org-recent-headings-list
                   :test #'org-recent-headings--equal)))

(defun org-recent-headings--store-heading (&rest _ignore)
  "Add current heading to `org-recent-headings' list."
  (if-let* ((entry (org-recent-headings--current-entry))
            (store-p (not (--any? (funcall it entry)
                                  org-recent-headings-reject-any-fns))))
      (if-let* ((existing-entry (car (cl-member entry org-recent-headings-list :test #'org-recent-headings--equal))))
          ;; Update existing item.
          (setf (org-recent-headings-entry-frecency existing-entry)
                (frecency-update (org-recent-headings-entry-frecency existing-entry)))
        ;; No existing item: add new one.
        (setf (org-recent-headings-entry-frecency entry)
              (frecency-update (org-recent-headings-entry-frecency entry)))
        (push entry org-recent-headings-list))
    ;; No entry: warn about possible non-Org buffer.  If this happens, it probably means
    ;; that a function should be removed from `org-recent-headings-advise-functions'.
    (when org-recent-headings-debug
      (warn "`org-recent-headings--store-heading' called in non-Org buffer: %s.  Please report this bug." (current-buffer)))))

(defun org-recent-headings--current-entry ()
  "Return entry for current Org entry, suitable for `org-recent-headings-list'."
  (when-let* ((buffer (pcase major-mode
                        ('org-agenda-mode (org-agenda-with-point-at-orig-entry
                                           (current-buffer)))
                        ('org-mode (current-buffer))))
              ;; Save point, because if we switch to a base buffer, point will change.
              (pos (point))
              ;; Get base buffer when applicable
              (buffer (or (buffer-base-buffer buffer)
                          buffer))
              (file-path (buffer-file-name buffer)))
    (with-current-buffer buffer
      (org-with-wide-buffer
       (goto-char pos)
       (unless (org-before-first-heading-p)
         (when-let* ((heading (org-get-heading t t)))
           ;; Heading is not empty
           (let* ((outline-path (org-recent-headings--olp))
                  (id (or (org-id-get)
                          (when (eq org-recent-headings-use-ids 'always)
                            (org-id-get-create))))
                  (display (concat (file-name-nondirectory file-path) ":"
                                   (if org-recent-headings-reverse-paths
                                       (--> (org-get-outline-path t)
                                            (org-format-outline-path it 1000 nil "")
                                            (org-split-string it "")
                                            (nreverse it)
                                            (s-join "\\" it))
                                     (org-format-outline-path (org-get-outline-path t))))))
             (make-org-recent-headings-entry :id id :file file-path :outline-path outline-path :display display))))))))

(defun org-recent-headings--olp ()
  "Return outline path for current entry.
Unlike `org-get-outline-path', this returns the raw heading
strings (without to-do keywords or tags), which are more suitable
for regexp searches."
  ;; `org-get-outline-path' replaces links in headings with their
  ;; descriptions, which prevents using them in regexp searches.
  (org-with-wide-buffer
   (nreverse (cl-loop collect (substring-no-properties (org-get-heading t t))
                      while (org-up-heading-safe)))))

(defun org-recent-headings--olp-marker (olp &optional unique)
  "Return a marker pointing to outline path OLP in current buffer.
Return nil if not found.  If UNIQUE, display a warning if OLP
points to multiple headings.

This works like `org-find-olp', but much faster."
  ;; `org-find-olp' provides the same results, but this function is about 3x faster.
  ;; The solution to the problem--of finding OLPs containing headings with links--was
  ;; returning raw heading text in `org-recent-headings--current-entry' rather than the
  ;; de-linked strings returned by `org-get-outline-path'.  But while exploring that
  ;; problem, I wrote this function, and since it's faster, we might as well use it.
  ;; NOTE: Disabling `case-fold-search' is important to avoid voluntary hair loss.
  (let ((case-fold-search nil))
    (cl-labels ((find-at (level headings)
                         ;; Could use `org-complex-heading-regexp-format', but this is actually much faster.
                         (let ((re (rx-to-string `(seq bol (repeat ,level "*") (1+ blank)
                                                       (optional (or ,@org-todo-keywords-1) (1+ blank)) ; To-do keyword
                                                       (optional "[#" (in "ABC") "]" (1+ blank)) ; Priority
                                                       ,(car headings) (0+ blank) (or eol ":")))))
                           (when (re-search-forward re nil t)
                             (when (and unique (save-excursion
                                                 (save-restriction
                                                   (when (re-search-forward re nil t)
                                                     (if (cdr headings)
                                                         (find-at (1+ level) (cdr headings))
                                                       t)))))
                               (display-warning 'org-recent-headings
                                                (format "Multiple headings found in %S for outline path: %S" (current-buffer) olp)
                                                :warning))
                             (if (cdr headings)
                                 (progn
                                   (org-narrow-to-subtree)
                                   (find-at (1+ level) (cdr headings)))
                               (copy-marker (point-at-bol)))))))
      (org-with-wide-buffer
       (goto-char (point-min))
       (find-at 1 olp)))))

;;;;; List maintenance

;; TODO: Add boolean var tracking whether list has changed and needs preparing.

(defun org-recent-headings--prepare-list ()
  "Sort and trim `org-recent-headings-list'."
  ;; FIXME: See task in notes.org.
  (setq org-recent-headings-list
        (-sort (-on #'> (lambda (entry)
                          (frecency-score (org-recent-headings-entry-frecency entry))))
               org-recent-headings-list))
  (org-recent-headings--trim))

(defun org-recent-headings--trim ()
  "Trim recent headings list.
This assumes the list is already sorted.  Whichever entries are
at the end of the list, beyond the allowed list size, are
removed."
  (let ((original-size (length org-recent-headings-list)))
    (when (> original-size org-recent-headings-list-size)
      (setq org-recent-headings-list (-take org-recent-headings-list-size org-recent-headings-list)))
    (when-let* ((debug-p org-recent-headings-debug)
                (new-size (length org-recent-headings-list))
                (difference (/= original-size new-size)))
      (warn "org-recent-headings-list reduced from %s to %s entries" original-size new-size))))

(defun org-recent-headings--remove-duplicates ()
  "Remove duplicates from `org-recent-headings-list'."
  (setq org-recent-headings-list
        (cl-delete-duplicates org-recent-headings-list
                              :test #'org-recent-headings--equal
                              :from-end t)))

(defun org-recent-headings--equal (a b)
  "Return non-nil if A and B point to the same Org entry.
A and B should be entries from `org-recent-headings-list' as
conses in (key . attrs) format."
  (pcase-let* (((cl-struct org-recent-headings-entry (id a-id) (file a-file) (outline-path a-outline-path)) a)
               ((cl-struct org-recent-headings-entry (id b-id) (file b-file) (outline-path b-outline-path)) b))
    (when (and a-file b-file)           ; Sanity check
      (or (when (and a-id b-id)
            ;; If the Org IDs are set and are the same, the entries point to
            ;; the same heading
            (string= a-id b-id))
          (when (and a-outline-path b-outline-path)
            ;; If both entries have outline-path in keys, compare file and olp
            (and (string= a-file b-file)
                 (equal a-outline-path b-outline-path)))))))

;;;;; Show entries

(defun org-recent-headings--show-entry-default (entry)
  "Show heading specified by ENTRY using default function.
Default function set in `org-recent-headings-show-entry-function'."
  ;; This is for the Helm source, to allow it to make use of a
  ;; customized option setting the default function.  Maybe there's a
  ;; better way, but this works.
  (funcall org-recent-headings-show-entry-function entry))

(defun org-recent-headings--show-entry-direct (entry)
  "Go to heading specified by ENTRY."
  (let ((marker (org-recent-headings--entry-marker entry)))
    (switch-to-buffer (marker-buffer marker))
    (widen)
    (goto-char marker)
    (org-reveal)
    (org-show-entry)))

(defun org-recent-headings--show-entry-indirect (real)
  "Show heading specified by REAL in an indirect buffer.
REAL is a plist with `:file', `:id', and `:regexp' entries.  If
`:id' is non-nil, `:file' and `:regexp may be nil.'"
  ;; By using `save-excursion' and `save-restriction', this function doesn't
  ;; change the position or narrowing of the entry's underlying buffer.
  (let ((marker (org-recent-headings--entry-marker real)))
    (save-excursion
      (save-restriction
        (switch-to-buffer (marker-buffer marker))
        (widen)
        (goto-char marker)
        (org-reveal)
        (org-show-entry)
        (org-tree-to-indirect-buffer)))))

(defun org-recent-headings--entry-marker (entry)
  "Return marker for ENTRY.
Raises an error if entry can't be found."
  (pcase-let* (((cl-struct org-recent-headings-entry id file outline-path) entry)
               (buffer (or (org-find-base-buffer-visiting file)
                           (find-file-noselect file)
                           (unless id
                             ;; Don't give error if an ID, because Org might still be able to find it
                             (error "File not found: %s" file))))
               (marker (if buffer
                           (with-current-buffer buffer
                             (save-excursion
                               (save-restriction
                                 (widen)
                                 (goto-char (point-min))
                                 ;; TODO: If showing the entry fails, optionally automatically remove it from list.
                                 ;; TODO: Factor out entry-finding into separate function.
                                 (cond (id (org-id-find id 'marker))
                                       (outline-path  (org-recent-headings--olp-marker outline-path))
                                       (t (error "org-recent-headings: Entry has no ID or OLP: %S" entry))))))
                         ;; No buffer; let Org try to find it.
                         ;; NOTE: Not sure if it's helpful to do this separately in the code above when `buffer' is set.
                         (org-id-find id 'marker))))
    (or marker
        (error "org-recent-headings: Can't find entry: %S" entry))))

;;;;; File saving/loading

;; Mostly copied from `recentf'

(defun org-recent-headings--save-list ()
  "Save the recent Org headings list.
Write data into the file specified by `org-recent-headings-save-file'."
  (condition-case err
      (with-temp-buffer
        (erase-buffer)
        (set-buffer-file-coding-system recentf-save-file-coding-system)
        (insert (format-message org-recent-headings-save-file-header
				(current-time-string)))
        (recentf-dump-variable 'org-recent-headings-list)
        (insert "\n\n;; Local Variables:\n"
                (format ";; coding: %s\n" recentf-save-file-coding-system)
                ";; End:\n")
        (write-file (expand-file-name org-recent-headings-save-file))
        (when recentf-save-file-modes
          (set-file-modes org-recent-headings-save-file recentf-save-file-modes))
        nil)
    (error
     (warn "org-recent-headings-mode: %s" (error-message-string err)))))

;; TODO: Remove 0.1->0.2 conversion code after 0.3 is released.

(defun org-recent-headings--load-list ()
  "Load a previously saved recent list.
Read data from the file specified by `org-recent-headings-save-file'."
  (let ((file (expand-file-name org-recent-headings-save-file)))
    (when (file-readable-p file)
      (load-file file)))
  (-when-let* ((old-style-list-p (listp (car org-recent-headings-list)))
               ;; Some of the keys might be missing, but all of the attrs should be present, so test only those.
               ((_
                 . (&keys :display :frecency-timestamps :frecency-num-timestamps :frecency-total-count))
                (car org-recent-headings-list)))
    ;; Try to convert 0.1-style list to 0.2-style.
    (setf org-recent-headings-list (org-recent-headings--convert org-recent-headings-list))))

(defun org-recent-headings--convert (list)
  "Return LIST converted from 0.1-style to 0.2-style."
  (--map (-let* ((((&keys :id :file :outline-path)
                   . (&keys :display :frecency-timestamps :frecency-num-timestamps :frecency-total-count))
                  it)
                 (frecency (list (cons :frecency-timestamps frecency-timestamps)
                                 (cons :frecency-num-timestamps frecency-num-timestamps)
                                 (cons :frecency-total-count frecency-total-count))))
           (make-org-recent-headings-entry :id id :file file :outline-path outline-path
                                           :display display :frecency frecency))
         list))

;;;; Footer

(provide 'org-recent-headings)

;;; org-recent-headings.el ends here
