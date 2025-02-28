;;; zim-wiki-mode.el --- Zim Desktop Wiki edit mode          -*- lexical-binding: t; -*-

;; URL: https://github.com/WillForan/zim-wiki-mode
;; Package-Version: 20200316.1223
;; Author: Will Foran <willforan+zim-wiki-mode@gmail.com>
;; Keywords: outlines
;; Package-Requires: ((emacs "25") (helm-ag "0.58") (helm-projectile "0.14.0") (dokuwiki-mode "0.1.1") (link-hint "0.1") (pretty-hydra "0.2.2"))
;; Version: 0.1.0

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;;; Commentary:
;; Edit zim wiki txt files within Emacs
;;
;; ffap code from:
;;   https://www.reddit.com/r/emacs/comments/676r5b/how_to_stop_findfileatprompting_when_there_is_a/


;;; Code:


;; configure other packages
(require 'ffap)
(require 'helm-projectile)
(require 'helm-ag)
(require 'dokuwiki-mode)

;; setings
(defgroup zim-wiki nil
  "Major mode for a zim wiki notebook (dokuwiki derivitive)."
  :group 'text
  :prefix "zim-wiki-"
  :tag "Zim-Wiki"
:link '(url-link "http://zim-wiki.org"))

(defcustom zim-wiki-root (expand-file-name "~/notes/PersonalWiki")
  "The root folder for the zim wiki notebook."
  :group 'zim-wiki
  :type 'string)
(defcustom zim-wiki-journal-datestr "Calendar/%Y/Week_%02V.txt"
  "Path as time format to journal pages."
  :group 'zim-wiki
  :type 'string)
(defcustom zim-wiki-now-disp "[d: %Y-%m-%d]"
  "How to insert date/time."
  :group 'zim-wiki
  :type 'string)

;; Functions

(defun zim-wiki-now-page ()
  "What is the path to the page for this time."
  (let ((datestr (format-time-string zim-wiki-journal-datestr)))
	(concat zim-wiki-root "/" datestr)))

(defun zim-wiki-goto-now ()
  "Go to the journal page for now."
  (interactive)
  (switch-to-buffer (find-file-noselect (zim-wiki-now-page)))
  ;; TODO: if empty buffer, add date template? have zim-wiki-insert-header, but it wont be date
  (zim-wiki-mode))

(defun zim-wiki-search ()
  "Search zim notebook with ag."
  (interactive)
  (helm-do-ag zim-wiki-root)
  (zim-wiki-mode))

(defun zim-wiki-mklink (path &optional text)
  "Make a link from a PATH with optional TEXT: [[path]] or [[path|text]]."
  (let* ((text (if text (concat "|" text) "")))
   (concat "[[" path text "]]")))

(defun zim-wiki-link-now ()
  "Link to current day."
  (zim-wiki-mklink
     (zim-wiki-path2wiki (zim-wiki-now-page))
     (format-time-string zim-wiki-now-disp)))

;; :a:b to /zim-wiki-root/a/b.txt
;; TODO: +a:b $(cwd)/a/b/.txt
;;       [[a:b]] $(cwd)/a/b.txt should just work (?)
;;       deal with spaces
(defun zim-wiki-wiki2path (zp)
  "Transform zim link ZP (':a:b') to file path /root/a/b.txt ."
  (let*
      ((zr (concat zim-wiki-root "/" ))
       (zp (replace-regexp-in-string "^\\+" "" zp))
       (zp (replace-regexp-in-string "^:+" zr zp))
       (zp (replace-regexp-in-string ":+" "/"  zp))
       ;; anything after a pipe
       (zp (replace-regexp-in-string "\\|.*" ""  zp))
       ;; remove any [ or ]
       (zp (replace-regexp-in-string "[][]" ""  zp))
       (zp (concat zp ".txt") ))
      zp))

(defun zim-wiki-path2wiki (zp)
  "Transform path ZP ('./a/b.txt') to wiki path."
  (let*
      (
       (zp (replace-regexp-in-string "^\\./" "+" zp)) ;; relative is +

       ;; various ways the file to be linked can have root in it:
       ;;  * normal: /home/b/blah
       ;;  * home alias: ~/b/blah
       ;;  * symlink: ~/b/blah -> /emulated/0/storage/blah
       (zp (replace-regexp-in-string (concat "^" zim-wiki-root) ":" zp))
       (zp (replace-regexp-in-string
	    (concat "^" (expand-file-name zim-wiki-root)) ":" zp))
       (zp (replace-regexp-in-string
	    (concat "^" (expand-file-name (file-truename zim-wiki-root)))
	    ":" zp))
       ;; no .txt,  / becomes :, no repeat :
       (zp (replace-regexp-in-string ".txt" "" zp)) ;; no extension
       (zp (replace-regexp-in-string "/" ":"  zp)) ;; all slashes to :
       (zp (replace-regexp-in-string ":+" ":"  zp)) ;; replace extra :'s
       )
    zp))

(defun zim-wiki-insert-now-link ()
  "Insert now string in current buffer."
  (interactive)
  (insert (zim-wiki-link-now)))

(defun zim-wiki-insert-current-at-now ()
  "Insert current page into now page (and go to now page)."
  (interactive)
  (let ((cur (zim-wiki-path2wiki (buffer-file-name))))
    (progn
      (zim-wiki-goto-now)
      ;; go to end
      (goto-char (point-max)) ;; TODO: change for week -- search for week dayname
      (insert "\n")
      (insert (zim-wiki-mklink cur)))))


;; at point
(defun zim-wiki-ffap-file (&optional wikipath)
  "Wrap (zim-wiki-wiki2path WIKIPATH) with absolute path and text at postion.
Move past any '[' before looking under cursor for a file
N.B. text is :a:b not /a/b but same file pattern rules apply"
  (let* ( ;(name (or wikipath (word-at-point)))
          (name (or wikipath
		   ;; skip ahead of [[ if looking at first part of link
	  	   (progn
	  	    (skip-chars-forward "[")
	  	    (ffap-string-at-point 'file))))
          (name (zim-wiki-wiki2path name)))
        (expand-file-name name)))

(defun zim-wiki-ffap-open (fname)
  "Open a given file FNAME as a zim-wiki dokument."
  (progn
    (if (and fname (file-exists-p fname))
	    (find-file fname)
	    (find-file-at-point fname))
    (if (= (buffer-size) 0) (zim-wiki-insert-header))
    (zim-wiki-mode)))

(defun zim-wiki-ffap (&optional wikipath)
  "Goto file from WIKIPATH."
  (interactive)
  (let* ((fname (zim-wiki-ffap-file wikipath)))
    (zim-wiki-ffap-open fname)))

(defun zim-wiki-ffap-below ()
  "Open a link in new window below current."
  (interactive)
  (with-selected-window (split-window-below) (zim-wiki-ffap)))

;; with selection?
(defun zim-wiki-vfap (&optional wikipath)
  "Read only mode ‘zim-wiki-ffap’ WIKIPATH?"
  (interactive)
  (zim-wiki-ffap wikipath)
  (read-only-mode))


;; find a page
(defun zim-wiki-helm-projectile ()
  "Go to a file using ‘helm-projectile’ (requires notebook in VCS)."
  (interactive)
  (helm-projectile)
  (zim-wiki-mode))

;; find a page but dont go there, just insert it
(defun zim-wiki-buffer-to-link (buffer)
  "Make a link of a given BUFFER."
  (zim-wiki-mklink (zim-wiki-path2wiki (expand-file-name (buffer-file-name buffer)))))

(defun zim-wiki-buffer-close-insert (cur)
   "Go away from CUR buffer created soley to get link.  Probably a bad idea."
  ;; TODO: find a way to restore buffer list. maybe dont kill the buffer incase it was already open?
  (let* ((res (current-buffer)))
   ;; (switch-to-buffer cur) ; go back to where we are told
   (if (not (string= (buffer-file-name res) (buffer-file-name cur)))
    (progn (kill-buffer res) ; go back by killing buffer we just created
           (insert (zim-wiki-buffer-to-link res))))))

;; search/projectile insert results
(defun zim-wiki-insert-helm-projectile ()
  "Use projectile to insert on the current page.
Opens projectile buffer before switching back"
  (interactive)
  (let* ((cur (current-buffer)))
      (zim-wiki-helm-projectile)
      (zim-wiki-buffer-close-insert cur)))

(defun zim-wiki-insert-search ()
  "Search zim notebook with ag."
  (interactive)
  (let* ((cur (current-buffer)))
    (zim-wiki-search)
    (zim-wiki-buffer-close-insert cur)))

;; wrap in a link
;; TODO: at-point for 'filename does not catpure + but does get :
(defun zim-wiki-link-wrap ()
  "Wrap current word as link."
  (interactive)
  (let*
      ((bounds (bounds-of-thing-at-point 'filename))
      (x (car bounds))
      (y (cdr bounds))
      (s (buffer-substring-no-properties x y)))
    (progn
      (delete-region x y)
      (goto-char x)
      (insert (zim-wiki-mklink s)))))
  
(defun zim-wiki-insert-header ()
  "Insert header on a new page."
  (interactive)
  (goto-char 0)
  (insert (concat
      "Content-Type: text/x-zim-wiki\n"
      "Wiki-Format: zim 0.4\n"
      "Creation-Date: " (format-time-string "%Y-%m-%dT%H:%M:%S%z")  "\n"
      "====== "
      (file-name-sans-extension (file-name-nondirectory (buffer-file-name)))
      " ======\n"
      "Created: " (format-time-string "%A %d %B %Y") "\n";Created Thursday 17 May 2018
      )))


(defun zim-wiki-buffer-path-to-kill-ring ()
  "Put the current file full path onto the kill ring."
  (interactive)
  (kill-new (expand-file-name (buffer-file-name))))

(defun zim-wiki-insert-kill-ring-as-link ()
  "Put the current file full path onto the kill ring."
  (interactive)
  (insert (zim-wiki-mklink (zim-wiki-path2wiki (current-kill 0)))))
(defun zim-wiki-insert-prev-buffer-link ()
   "Link previous buffer path as wiki."
   (interactive)
   (insert (zim-wiki-buffer-to-link (other-buffer (current-buffer) 1))))


;; link-hint
(require 'link-hint)
(defun zim-wiki-link-hint--next-dokuwiki-link (&optional bound)
  "Find the next dokuwiki url.
Only search the range between just after the point and BOUND."
  (link-hint--next-property-with-value 'face 'dokuwiki-link bound))


(link-hint-define-type 'zim-wiki-link
  :next #'zim-wiki-link-hint--next-dokuwiki-link
  :at-point-p #'zim-wiki-ffap-file
  ;; TODO consider making file links opt-in (use :vars)
  :not-vars '(org-mode Info-mode)
  :open #'zim-wiki-ffap-open
  :copy #'kill-new)

(push 'link-hint-zim-wiki-link link-hint-types)


;; pretty hydra menu
(require 'pretty-hydra)
(pretty-hydra-define zim-wiki-hydra (:color blue :title "zim-wiki" :quit-key "q")
  ("Go"
   (("n" zim-wiki-goto-now "todays page")
    ("t" zim-wiki-helm-projectile "file title")
    ("s" zim-wiki-search "search text")
    ("l" link-hint-open-link "link hint open")
    ("o" zim-wiki-ffap "open link")
    ("b" zim-wiki-ffap "open link below"))
   "Insert"
   (("L" zim-wiki-insert-helm-projectile "link title")
    ("S" zim-wiki-insert-search "link search")
    ("N" zim-wiki-insert-now-link "link today")
    ("w" zim-wiki-link-wrap "wrap as link")
    ("B" zim-wiki-insert-prev-buffer-link "prev"))
   "Clipboard"
   (("y" zim-wiki-buffer-path-to-kill-ring "current to clip")
    ("p" zim-wiki-insert-kill-ring-as-link "insert clip as link"))))

;; consider
;;(evil-leader/set-key "z" 'zimwik-hydra/body)


;; http://ergoemacs.org/emacs/elisp_create_major_mode_keymap.html
(defvar zim-wiki-mode-map
  (let ((map (make-sparse-keymap)))
    ;; hydra overview
    (define-key map (kbd "C-c C-z")   #'zim-wiki-hydra/body)     ;; give all the options
    ;; go places
    (define-key map (kbd "C-c M-f")   #'zim-wiki-helm-projectile);; go to a page by searching file names
    (define-key map (kbd "C-c C-f")   #'zim-wiki-search)         ;; find in all of notebook
    (define-key map (kbd "C-c RET")   #'zim-wiki-ffap)           ;; go to link
    (define-key map (kbd "C-c M-RET") #'zim-wiki-ffap-below)     ;; go to link in new window

    ;; make links
    (define-key map (kbd "C-c M-l") #'zim-wiki-insert-helm-projectile)
    (define-key map (kbd "C-c C-l") #'zim-wiki-insert-search)

    (define-key map (kbd "C-c M-w") #'zim-wiki-link-wrap)                ;; a:b -> [[a:b]]
    (define-key map (kbd "C-c M-y") #'zim-wiki-buffer-path-to-kill-ring) ;; copy current file path
    (define-key map (kbd "C-c M-p") #'zim-wiki-insert-kill-ring-as-link) ;; paste as a link
    (define-key map (kbd "C-c C-p") #'zim-wiki-insert-prev-buffer-link)  ;; buffer before this one as a wiki link

    ;; date/time
    (define-key map (kbd "C-c C-n") #'zim-wiki-goto-now)              ;; go to now page
    (define-key map (kbd "C-c C-N") #'zim-wiki-insert-now-link)       ;; link to curret date/time
    (define-key map (kbd "C-c M-n") #'zim-wiki-insert-current-at-now) ;; insert cur page into now page (and go there)

    ;; tree
    ;;(define-key map (kbd "C-c t")   'neotree-toggle)  ; toggle tree
    ;;(define-key map (kbd "C-c T")   'neotree-find)    ; find thing in tree

    ;; org mode theft
    ;;(define-key map (kbd "M-RET")   'org-insert-item)    ; insert new list item

    map)
   "Keymap for ‘zim-wiki-mode’.")

(define-derived-mode zim-wiki-mode dokuwiki-mode "zim-wiki"
  "Major mode for editing zim wiki.")

(provide 'zim-wiki-mode)


;; TODO:
;;  * agenda "[ ] task [d: yyyy-mm-dd]"
;;  * backlink collection (use sqlitedb? zim-wiki uses?)
;;  * tags

;;  * prettify headers?
;;    https://github.com/sabof/org-bullets/blob/master/org-bullets.el

;;; zim-wiki-mode.el ends here
