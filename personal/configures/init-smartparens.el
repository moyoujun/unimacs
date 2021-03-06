;;; init-smartparens.el --- Summary
;;; Commentary:
;; comments

;;; Code:
(use-package smartparens
  :defer 0
  :bind (("C-M-f" . sp-forward-sexp)
         ("C-M-b" . sp-backward-sexp)
         ("C-M-n" . sp-next-sexp)
         ("C-M-p" . sp-previous-sexp)
         ("C-M-S-SPC" . sp-mark-sexp)
         ("C-M-S-k"   . sp-kill-sexp)
         ("M-[" .   sp-backward-unwrap-sexp)
         ("M-]" .   sp-unwrap-sexp)
         ("C-M-{" . sp-rewrap-sexp))
  :config
  (require 'smartparens-config)
  (smartparens-global-mode 1)
  (show-smartparens-global-mode 1)
  (setq sp-highlight-pair-overlay nil)  ; bug: when multiple-cursors.
  ;; NOTICE: historic reason, in terminal: C-[ -> ESC, must unbind it first:
  (define-key input-decode-map [?\C-\[] [C-\[])
  (sp-pair "[" "]" :wrap "<C-\[>")
  (sp-pair "{" "}" :wrap "C-{")
  (sp-pair "(" ")" :wrap "C-(")
  (setq sp-navigate-consider-sgml-tags '(html-mode nxml-mode web-mode xml-mode))
  (sp-local-pair 'minibuffer-inactive-mode "'" nil :actions nil)
  (add-hook 'lisp-mode-hook 'turn-on-smartparens-strict-mode)
  (add-hook 'markdown-mode-hook 'turn-on-smartparens-strict-mode)

  ;; @ref https://github.com/Fuco1/.emacs.d/blob/master/files/smartparens.el
  ;; @doc https://github.com/Fuco1/smartparens/wiki/Pair-management
  ;;; org-mode
  (sp-with-modes 'org-mode
    (sp-local-pair "“" "”")
    (sp-local-pair "《" "》")
    (sp-local-pair "*" "*" :actions '(insert wrap) :unless '(sp-point-after-word-p sp-point-at-bol-p) :wrap "C-*" :skip-match 'sp--org-skip-asterisk)
    (sp-local-pair "_" "_" :unless '(sp-point-after-word-p))
    (sp-local-pair "/" "/" :unless '(sp-point-after-word-p) :post-handlers '(("[d1]" "SPC")))
    (sp-local-pair "~" "~" :unless '(sp-point-after-word-p) :post-handlers '(("[d1]" "SPC")))
    (sp-local-pair "=" "=" :unless '(sp-point-after-word-p) :post-handlers '(("[d1]" "SPC")))
    (sp-local-pair "?" "?"))

  (defun sp--org-skip-asterisk (ms mb me)
    (or (and (= (line-beginning-position) mb)
             (eq 32 (char-after (1+ mb))))
        (and (= (1+ (line-beginning-position)) me)
             (eq 32 (char-after me)))))

  ;;; tcl-mode
  (sp-with-modes 'tcl-mode
    (sp-local-pair "\\[" "\\]")
    (sp-local-pair "hwi OpenStack" "hwi CloseStack")
    (sp-local-pair "OpenStack" "CloseStack"))
  (sp-with-modes 'java-mode
    (sp-local-pair "<" ">" :when '(sp-point-after-word-p) :post-handlers '(("[d1]" "SPC"))))
  (sp-with-modes 'scala-mode
    (sp-local-pair "<" ">" :when '(sp-point-after-word-p) :post-handlers '(("[d1]" "SPC"))))
  :diminish (smartparens-mode smartparens-global-mode))

(provide 'init-smartparens)
;;; init-smartparens.el ends here