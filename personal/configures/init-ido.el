;;; init-ido.el --- Summary
;;; Commentary:
;; comments

;;; Code:
(use-package ido
  :ensure nil
  :disabled
  :demand t
  :init
  (ido-mode 'buffer) ; use 'buffer rather than t to use only buffer switching
  ;; (ido-everywhere t)
  (setq ido-use-filename-at-point nil)
  (setq ido-auto-merge-work-directories-length -1) ; use -1 to disable annoying too smart auto completion
  (setq ido-use-virtual-buffers t)                 ; Allow the same buffer to be open in different frames
  (setq ido-default-buffer-method 'selected-window) ; current window

  ;; (use-package ido-ubiquitous
  ;;   ;; ido everywhere: Use C-f during file selection to switch to regular find-file
  ;;   :init
  ;;   (ido-ubiquitous-mode t))

  (use-package flx-ido
    :init
    (flx-ido-mode 1)
    (setq ido-enable-flex-matching t)
    ;; disable ido faces to see flx highlights.
    (setq ido-use-faces nil
          flx-ido-use-faces t))

  (use-package ido-vertical-mode
    :disabled
    :init
    (ido-vertical-mode 1)
    (setq ido-vertical-define-keys 'C-n-and-C-p-only
          ido-vertical-show-count  t
          ido-use-faces            t)
    (set-face-attribute 'ido-vertical-first-match-face nil
                        :background nil
                        :foreground "orange")
    (set-face-attribute 'ido-vertical-only-match-face nil
                        :background nil
                        :foreground nil)
    (set-face-attribute 'ido-vertical-match-face nil
                        :foreground nil))

  )

(provide 'init-ido)
;;; init-ido.el ends here
