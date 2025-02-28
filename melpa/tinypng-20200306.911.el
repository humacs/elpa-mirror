;;; tinypng.el --- Compress PNG and JPEG with TinyPNG.com API  -*- lexical-binding: t; -*-

;; Copyright (C) 2019  Xu Chunyang

;; Author: Xu Chunyang <mail@xuchunyang.me>
;; Homepage: https://github.com/xuchunyang/tinypng.el
;; Created: 2019-06-10T11:46:05+08:00
;; Package-Requires: ((emacs "25.1"))
;; Package-Version: 20200306.911
;; Version: 0
;; Keywords: multimedia

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

;; Compress PNG and JEPG via https://tinypng.com/ API.

;;; Code:

(require 'json)
(require 'url)

(declare-function dired-get-filename "dired")

(defvar tinypng-token nil)

(defun tinypng--read-token ()
  "Get Tinypng api token from ~/.authinfo.

If it does not exist, you will be prompt for one, 
then it will be saved."
  (let* ((plist (let ((auth-source-creation-prompts
                       '((secret . "Paste your API key of %h: "))))
                  (car (auth-source-search :host "api.tinify.com"
                                           :user "tinypng.el"
                                           :max 1
                                           :create t))))
         (save (plist-get plist :save-function))
         (token (plist-get plist :secret)))
    (and (functionp save) (funcall save))
    (if (functionp token)
        (funcall token)
      token)))

(defun tinypng--read-from ()
  (let* ((file-at-point (pcase major-mode
                          ;; The ' pattern requires Emacs-25.1, the ` pattern
                          ;; works for older versions of Emacs, but I has no
                          ;; interest in supporting old versions.
                          ('image-mode buffer-file-name)
                          ('dired-mode (dired-get-filename nil t))
                          (_ (thing-at-point 'filename))))
         (img-p (lambda (f)
                  (member (file-name-extension f) '("png" "jpg" "jpeg"))))
         (valid (lambda (f)
                  (and (file-exists-p f)
                       (funcall img-p f))))
         (default (and file-at-point
                       (funcall valid file-at-point)
                       file-at-point))
         (prompt (if default
                     (format "Compress image (default %s): " default)
                   "Compress image: "))
         (from (read-file-name prompt nil default t nil img-p)))
    from))

;;;###autoload
(defun tinypng (from &optional to)
  "Compress PNG or JEPG image.

FROM is path of the image you want to comparess.

TO is the path you want to save the output to, if TO is the same
as FROM, FROM will be overwritten.  TO can also be nil, then the
output will not be save, instead open the output image in browser."
  (interactive
   (let* ((from (tinypng--read-from))
          (to (and current-prefix-arg
                   (read-file-name
                    (format "Save output to (default %s): " from)))))
     (list from to)))
  (unless tinypng-token
    (setq tinypng-token (tinypng--read-token)))
  (unless tinypng-token
    (user-error "[tinypng] No token found"))
  (with-current-buffer
      (let ((url-request-method "POST")
            (url-request-extra-headers
             `(("Authorization" .
                ,(format "Basic %s"
                         (base64-encode-string (concat "api:" tinypng-token))))))
            (url-request-data (with-temp-buffer
                                (set-buffer-multibyte nil)
                                (insert-file-contents-literally from)
                                (buffer-string))))
        (url-retrieve-synchronously "https://api.tinify.com/shrink"))
    (set-buffer-multibyte nil)
    (goto-char (point-min))
    (re-search-forward "^\r?\n")
    (let-alist (json-read)
      (if .error
          (error "%s: %s" .error .message)
        (cond
         (to
          (url-copy-file .output.url to t)
          (message "Success! %s (%s) -> %s (%s)     %s (%s saved)"
                   from (file-size-human-readable .input.size 'iec)
                   to (file-size-human-readable .output.size 'iec)
                   (format "-%.0f%%" (* 100 (- 1 .output.ratio)))
                   (file-size-human-readable (- .input.size .output.size))))
         (t
          (message "Decrease size from %d to %d, output url: %s"
                   .input.size
                   .output.size
                   .output.url)
          (browse-url .output.url)))
        (kill-buffer)))))

(provide 'tinypng)
;;; tinypng.el ends here
