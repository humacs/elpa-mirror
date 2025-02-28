Window configuration switcher grouped by workspaces

winds.el is very similar to [[https://github.com/wasamasa/eyebrowse/][eyebrowse]] and other window config
switchers, but allows for having multiple "workspaces" grouping sets
of window config slots.

This small package was started because I tend to have multiple
unrelated projects open at once, and need to keep them open.  I do
not want to cycle through unrelated window configs to get to what I
want and I want to keep only one fullscreen Emacs frame open.

(This package has basic support for multiple frames)

* Screenshot
  [[file:scrot.png]]

* Install

  This package is available on Melpa. Simply install it with your
  favorite package manager:

  #+BEGIN_SRC elisp
  (use-package winds :ensure t)
  #+END_SRC

* Getting Started

  To get started, bind some keys to ~winds-goto~:

  #+BEGIN_SRC elisp
  (global-set-key (kbd "M-1") (lambda () (interactive) (winds-goto :ws 1)))
  (global-set-key (kbd "M-2") (lambda () (interactive) (winds-goto :ws 2)))
  (global-set-key (kbd "M-3") (lambda () (interactive) (winds-goto :ws 3)))
  (global-set-key (kbd "C-c 1") (lambda () (interactive) (winds-goto :cfg 1)))
  (global-set-key (kbd "C-c 2") (lambda () (interactive) (winds-goto :cfg 2)))
  (global-set-key (kbd "C-c 3") (lambda () (interactive) (winds-goto :cfg 3)))
  #+END_SRC

  You might also want to bind ~next~/~prev~ and ~close~

  #+BEGIN_SRC elisp
  (global-set-key (kbd "C-c <")  'winds-next)
  (global-set-key (kbd "C-c >")  'winds-prev)
  (global-set-key (kbd "C-c \\") 'winds-close)
  (global-set-key (kbd "C-<")    'winds-cfg-next)
  (global-set-key (kbd "C->")    'winds-cfg-prev)
  (global-set-key (kbd "C-\\")   'winds-cfg-close)
  #+END_SRC

* Options

  To disable the status message when changing window configs:

  #+BEGIN_SRC elisp
  (setq winds-display-status-msg nil)
  #+END_SRC

  For a simple mode-line indicator, add this to your ~mode-line-format~:

  #+BEGIN_SRC elisp
    (:eval (format "%s|%s " (winds-get-cur-ws) (winds-get-cur-cfg)))
  #+END_SRC

  For example (dumb example):

  #+BEGIN_SRC elisp
    (setq mode-line-format
          `(,mode-line-format
            (:eval (format "%s|%s "
                           (winds-get-cur-ws)
                           (winds-get-cur-cfg)))))
  #+END_SRC

  =winds.el= works with =desktop.el=! If you want to enable saving of
  winds workspaces add this to your configuration:

  #+BEGIN_SRC elisp
    (with-eval-after-load 'desktop (winds-enable-desktop-save))
  #+END_SRC

* My config

  As an example, here is how I use this package:

  #+BEGIN_SRC elisp
    (use-package winds
      :straight t
      :custom
      (winds-default-ws 1)
      (winds-default-cfg 1)
      :config
      (with-eval-after-load 'desktop (winds-enable-desktop-save))
      :general
      (:prefix "SPC w"
        "w n" 'winds-next
        "w p" 'winds-prev
        "w c" 'winds-close
        "w w TAB" 'winds-last
        "n" 'winds-cfg-next
        "p" 'winds-cfg-prev
        "c" 'winds-cfg-close
        "w TAB" 'winds-cfg-last
        "w o" 'winds-pos-last
        "w 0" (lambda () (interactive) (winds-goto :ws 10))
        "w 1" (lambda () (interactive) (winds-goto :ws 1))
        "w 2" (lambda () (interactive) (winds-goto :ws 2))
        "w 3" (lambda () (interactive) (winds-goto :ws 3))
        "w 4" (lambda () (interactive) (winds-goto :ws 4))
        "w 5" (lambda () (interactive) (winds-goto :ws 5))
        "w 6" (lambda () (interactive) (winds-goto :ws 6))
        "w 7" (lambda () (interactive) (winds-goto :ws 7))
        "w 8" (lambda () (interactive) (winds-goto :ws 8))
        "w 9" (lambda () (interactive) (winds-goto :ws 9))
        "0" (lambda () (interactive) (winds-goto :cfg 10))
        "1" (lambda () (interactive) (winds-goto :cfg 1))
        "2" (lambda () (interactive) (winds-goto :cfg 2))
        "3" (lambda () (interactive) (winds-goto :cfg 3))
        "4" (lambda () (interactive) (winds-goto :cfg 4))
        "5" (lambda () (interactive) (winds-goto :cfg 5))
        "6" (lambda () (interactive) (winds-goto :cfg 6))
        "7" (lambda () (interactive) (winds-goto :cfg 7))
        "8" (lambda () (interactive) (winds-goto :cfg 8))
        "9" (lambda () (interactive) (winds-goto :cfg 9))))
  #+END_SRC
