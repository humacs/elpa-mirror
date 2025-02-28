;;; dashboard-ls.el --- Display files/directories in current directory on Dashboard  -*- lexical-binding: t; -*-

;; Copyright (C) 2020  Shen, Jen-Chieh
;; Created date 2020-03-24 17:49:59

;; Author: Shen, Jen-Chieh <jcs090218@gmail.com>
;; Description: Display files/directories in current directory on Dashboard.
;; Keyword: directory file show dashboard
;; Version: 0.1.2
;; Package-Version: 20200329.1443
;; Package-Requires: ((emacs "24.3") (dashboard "1.2.5") (f "0.20.0") (s "1.12.0"))
;; URL: https://github.com/jcs090218/dashboard-ls

;; This file is NOT part of GNU Emacs.

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:
;;
;; Display files/directories in current directory on Dashboard.
;;

;;; Code:

(require 'f)
(require 's)

(require 'dashboard)
(require 'dashboard-widgets)

(add-to-list 'dashboard-item-generators '(ls-directories . dashboard-ls--insert-dir))
(add-to-list 'dashboard-item-generators '(ls-files . dashboard-ls--insert-file))

(defvar dashboard-ls-path nil
  "Update to date current path.
Use this variable when you don't have the `default-directory' up to date.")

(defun dashboard-ls--insert-dir (list-size)
  "Add the list of LIST-SIZE items from current directory."
  (dashboard-insert-section
   "Current Directories:"
   (let* ((current-dir (if dashboard-ls-path
                           dashboard-ls-path
                         default-directory))
          (dir-lst (f-directories current-dir))
          (opt-dir-lst '()))
     (dolist (dir dir-lst)
       (setq dir (s-replace current-dir "./" dir))
       (setq dir (s-replace "//" "/" dir))
       (push (concat dir "/") opt-dir-lst))
     (reverse opt-dir-lst))
   list-size
   "d"
   `(lambda (&rest ignore) (find-file-existing ,el))
   (abbreviate-file-name el)))

(defun dashboard-ls--insert-file (list-size)
  "Add the list of LIST-SIZE items from current files."
  (dashboard-insert-section
   "Current Files:"
   (let* ((current-dir (if dashboard-ls-path
                           dashboard-ls-path
                         default-directory))
          (file-lst (f-files current-dir))
          (opt-file-lst '()))
     (dolist (file file-lst)
       (setq file (s-replace current-dir "./" file))
       (setq file (s-replace "//" "/" file))
       (push file opt-file-lst))
     (reverse opt-file-lst))
   list-size
   "f"
   `(lambda (&rest ignore) (find-file-existing ,el))
   (abbreviate-file-name el)))

(provide 'dashboard-ls)
;;; dashboard-ls.el ends here
