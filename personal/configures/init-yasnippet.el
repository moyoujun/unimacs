;;; init-yasnippet.el --- Summary:
;;; Commentary:
;;; code:
(use-package yasnippet
  :bind ("<tab>" . yas-expand) ; other completion, like minibuffer, use C-S-i
  :config
  (custom-set-faces
   ;; custom-set-faces was added by Custom.
   ;; If you edit it by hand, you could mess it up, so be careful.
   ;; Your init file should contain only one such instance.
   ;; If there is more than one, they won't work right.
   '(yas-field-highlight-face ((t (:inherit secondary-selection :background "gray" :foreground "black")))))

  (setq my-yasnippet-dir (expand-file-name "snippets" unimacs-utils-dir))
  (setq yas-snippet-dirs (list yas-installed-snippets-dir))
  (when (and (file-exists-p my-yasnippet-dir)
             (not (member my-yasnippet-dir yas-snippet-dirs)))
      (add-to-list 'yas-snippet-dirs my-yasnippet-dir))
  ;; give yas-dropdown-prompt in yas-prompt-functions a chance.(others: yas-ido-prompt yas-completing-prompt)
  (require 'dropdown-list)
  (setq yas-prompt-functions '(yas-dropdown-prompt yas-completing-prompt))
  ;; use yas-completing-prompt when ONLY when `M-x yas-insert-snippet'
  ;; thanks to capitaomorte for providing the trick.
  (defadvice yas-insert-snippet (around use-completing-prompt activate)
    "Use `yas-completing-prompt' for `yas-prompt-functions' but only here..."
    (let ((yas-prompt-functions '(yas-completing-prompt)))
      ad-do-it))
  ;; @see http://stackoverflow.com/questions/7619640/emacs-latex-yasnippet-why-are-newlines-inserted-after-a-snippet
  (setq-default mode-require-final-newline nil)
  :diminish (yas-minor-mode yas-global-mode)
  )

(yas-global-mode 1)

(provide 'init-yasnippet)
;;; init-yasnippet.el ends here
