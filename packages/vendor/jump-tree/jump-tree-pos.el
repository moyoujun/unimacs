;;; jump-tree-pos.el --- Treat position history as a tree  -*- lexical-binding: t; -*-

;; Copyright (C) 2009-2017  Free Software Foundation, Inc

;; Author: Wen Yang <yangwen0228@foxmail.com>
;; Maintainer: Wen Yang <yangwen0228@foxmail.com>
;; Version: 0.1.0
;; Package-Version: 20170803.1
;; Keywords: convenience, files, jump, tree
;; URL:
;; Repository:

;; This file is part of Emacs.
;;
;; This file is free software: you can redistribute it and/or modify it under
;; the terms of the GNU General Public License as published by the Free
;; Software Foundation, either version 3 of the License, or (at your option)
;; any later version.
;;
;; This program is distributed in the hope that it will be useful, but WITHOUT
;; ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
;; FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
;; more details.
;;
;; You should have received a copy of the GNU General Public License along
;; with GNU Emacs.  If not, see <http://www.gnu.org/licenses/>.


;;; Commentary:
;; This file serves as the core functionality of this package.  We use a list
;; to record the positions `(file-path . point-marker)'.  And when we
;; run command `jump-tree-jump-prev', `jump-tree-jump-next'
;; or `jump-tree-visualize', we transfer the list into the `jump-tree-pos-tree'.
;; This tree has a root and a current node.  Every tree node has a previous
;; node or parent node, and a next node represents a list of child nodes.
;; And we use a banch number to represents the index of the child nodes.

;;; Code:

(eval-when-compile (require 'cl))


;;; =====================================================================
;;;              Compatibility hacks for older Emacsen

;; `registerv' defstruct isn't defined in Emacs versions < 24
(unless (fboundp 'registerv-make)
  (defmacro registerv-make (data &rest _dummy) data))

(unless (fboundp 'registerv-data)
  (defmacro registerv-data (data) data))

;; `user-error' isn't defined in Emacs < 24.3
(unless (fboundp 'user-error)
  (defalias 'user-error 'error)
  ;; prevent debugger being called on user errors
  (add-to-list 'debug-ignored-errors "^No further jump-prev information")
  (add-to-list 'debug-ignored-errors "^No further jump-next information"))


;;; =====================================================================
;;;              Global variables and customization options

(defgroup jump-tree nil
  "Tree jump-prev/jump-next."
  :group 'jump-tree)

(defvar jump-tree-pos-list '()
  "Jump history list, contain POSITION entries '(file-name . marker).")

(defvar jump-tree-pos-tree nil
  "Tree of position entries globally.")

(defvar jump-tree-in-progress nil
  "Jump-Tree-Pos-List state.")

(defcustom jump-tree-pos-list-limit 40
  "Max length of ‘jump-tree-pos-list’."
  :type 'integer
  :group 'jump-tree)

(defcustom jump-tree-pos-tree-limit 100
  "Max count of jump-tree-tree-list."
  :type 'integer
  :group 'jump-tree)

(defcustom jump-tree-pos-list-hook-commands
  '(beginning-of-buffer
    end-of-buffer backward-up-list
    beginning-of-defun end-of-defun
    unimacs-move-beginning-of-line unimacs-move-end-of-line
    unimacs-move-beginning-of-window unimacs-move-end-of-window
    helm-swoop helm-imenu helm-find-files helm-multi-files
    helm-projectile-switch-project helm-projectile-find-file
    helm-gtags-find-pattern helm-gtags-find-tag-adapter
    helm-gtags-find-rtag-adapter helm-ag-select-directory
    find-function find-variable
    mark-defun mark-whole-buffer
    avy-goto-char avy-goto-char-2
    ensime-edit-definition
    ensime-edit-definition-with-fallback
    isearch-forward)
  "Commands to hook."
  :type 'list
  :group 'jump-tree)

(defcustom jump-tree-mode-lighter " Jump-Tree"
  "Lighter displayed in mode line when command `jump-tree-mode' is enabled."
  :group 'jump-tree
  :type 'string)


;;; =====================================================================
;;;              jump-tree record position list

(defun jump-tree-pos-list-jump (position)
  "Do jump to target file and point from POSITION."
  (let ((file-path (car position))
        (marker (cdr position)))
    (when (and (markerp marker) (marker-buffer marker))
      (find-file file-path)
      (goto-char marker))))

(defun jump-tree-pos-list-push (position)
  "Push POSITION to `jump-tree-pos-list'."
  (while (> (length jump-tree-pos-list) jump-tree-pos-list-limit)
    (setq jump-tree-pos-list (cdr jump-tree-pos-list)))
  (push position jump-tree-pos-list))

(defun jump-tree-pos-list-same-position? (position)
  "Check whether current POSITION is equal with the last POSITION in list."
  (let ((new-point (cdr position))
        (top-point (cdar jump-tree-pos-list)))
    (cond ((not new-point) nil)
          ((not top-point) nil)
          ((eq (marker-position new-point) (marker-position top-point)) 't))))

(defun jump-tree-pos-list-set ()
  "The record data structure is (file-name . position)."
  (interactive)
  (if (buffer-file-name)
      (let ((position (cons (buffer-file-name) (point-marker))))
        (unless (jump-tree-pos-list-same-position? position)
          (jump-tree-pos-list-push position)))))

(defun jump-tree-pos-list-command-hook ()
  "Pre command hook that call `jump-tree-pos-list-set' when registerd command hook called."
  (when (and (not jump-tree-in-progress)
             (memq this-command jump-tree-pos-list-hook-commands))
    (jump-tree-pos-list-set)))

(add-hook 'pre-command-hook 'jump-tree-pos-list-command-hook)


;;; =====================================================================
;;;                     jump-tree data structure

(defstruct
    (jump-tree
     :named
     (:constructor nil)
     (:constructor make-jump-tree
                   (&aux
                    (root (jump-tree-make-node nil nil))
                    (current root)
                    (count 0)))
     ;;(:copier nil)
     )
  root current count)

(defstruct
    (jump-tree-node
     (:type vector)   ; create unnamed struct
     (:constructor nil)
     (:constructor jump-tree-make-node
                   (previous position
                             &aux
                             (timestamp (current-time))
                             (branch 0)))
     (:copier nil))
  previous next position timestamp branch meta-data)

(defmacro jump-tree-node-p (n)
  "Check node N is whether a `jump-tree-node'."
  (let ((len (length (jump-tree-make-node nil nil))))
    `(and (vectorp ,n) (= (length ,n) ,len))))

(defstruct
    (jump-tree-position-data
     (:type vector)   ; create unnamed struct
     (:constructor nil)
     (:constructor jump-tree-make-position-data
                   (&optional file-path marker))
     (:copier nil))
  file-path marker)

(defmacro jump-tree-position-data-p (pos)
  "Check POS is whether a `jump-tree-position-data'."
  (let ((len (length (jump-tree-make-position-data))))
    `(and (vectorp ,pos) (= (length ,pos) ,len))))

(defmacro jump-tree-node-file-path (node)
  "Fetch FILE-PATH data from NODE's meta-data field :position."
  `(let ((pos (plist-get (jump-tree-node-meta-data ,node) :position)))
     (when (jump-tree-position-data-p pos)
       (jump-tree-position-data-file-path pos))))

(defmacro jump-tree-node-marker (node)
  "Fetch MARKER data from NODE's meta-data field :position."
  `(let ((pos (plist-get (jump-tree-node-meta-data ,node) :position)))
     (when (jump-tree-position-data-p pos)
       (jump-tree-position-data-marker pos))))

(defsetf jump-tree-node-file-path (node) (val)
  `(let ((pos (plist-get (jump-tree-node-meta-data ,node) :position)))
     (unless (jump-tree-position-data-p pos)
       (setf (jump-tree-node-meta-data ,node)
             (plist-put (jump-tree-node-meta-data ,node) :position
                        (setq pos (jump-tree-make-position-data)))))
     (setf (jump-tree-position-data-file-path pos) ,val)))

(defsetf jump-tree-node-marker (node) (val)
  `(let ((pos (plist-get (jump-tree-node-meta-data ,node) :position)))
     (unless (jump-tree-position-data-p pos)
       (setf (jump-tree-node-meta-data ,node)
             (plist-put (jump-tree-node-meta-data ,node) :position
                        (setq pos (jump-tree-make-position-data)))))
     (setf (jump-tree-position-data-marker pos) ,val)))

(defstruct
    (jump-tree-register-data
     (:type vector)
     (:constructor nil)
     (:constructor jump-tree-make-register-data (buffer node)))
  buffer node)

(defun jump-tree-register-data-p (data)
  "Check DATA is whether a `jump-tree-register-data'."
  (and (vectorp data)
       (= (length data) 2)
       (jump-tree-node-p (jump-tree-register-data-node data))))

(defun jump-tree-register-data-print-func (data)
  "Print DATA's register data."
  (princ (format "an jump-tree state for buffer %s"
                 (jump-tree-register-data-buffer data))))

(defmacro jump-tree-node-register (node)
  "Fetch REGISTER data from NODE's meta-data field :register."
  `(plist-get (jump-tree-node-meta-data ,node) :register))

(defsetf jump-tree-node-register (node) (val)
  `(setf (jump-tree-node-meta-data ,node)
         (plist-put (jump-tree-node-meta-data ,node) :register ,val)))


;;; =====================================================================
;;;         Basic common jump-tree data structure functions
(defmacro jump-tree-num-branches ()
  "Return number of branches at current position tree node."
  '(length (jump-tree-node-next (jump-tree-current jump-tree-pos-tree))))

(defun jump-tree-grow-backwards (node position)
  "Add new NODE with POSITION *above* jump-tree node, and return new node.
Note that this will overwrite NODE's \"previous\" link, so should
only be used on a detached NODE, never on nodes that are already
part of `jump-tree-pos-tree'."
  (let ((new (jump-tree-make-node nil position)))
    (setf (jump-tree-node-next new) (list node))
    (setf (jump-tree-node-previous node) new)
    new))

(defun jump-tree-splice-node (node splice)
  "Splice NODE into position tree, below node SPLICE.
Note that this will overwrite NODE's \"next\" and \"previous\"
links, so should only be used on a detached NODE, never on nodes
that are already part of `jump-tree-pos-tree'."
  (setf (jump-tree-node-next node) (jump-tree-node-next splice)
        (jump-tree-node-branch node) (jump-tree-node-branch splice)
        (jump-tree-node-previous node) splice
        (jump-tree-node-next splice) (list node)
        (jump-tree-node-branch splice) 0)
  (dolist (n (jump-tree-node-next node))
    (setf (jump-tree-node-previous n) node)))

(defun jump-tree-snip-node (node)
  "Snip NODE out of position tree."
  (let* ((parent (jump-tree-node-previous node))
         index i)
    ;; if NODE is only child, replace parent's next links with NODE's
    (if (= (length (jump-tree-node-next parent)) 0)
        (setf (jump-tree-node-next parent) (jump-tree-node-next node)
              (jump-tree-node-branch parent) (jump-tree-node-branch node))
      ;; otherwise...
      (setq index (jump-tree-index node (jump-tree-node-next parent)))
      (cond
       ;; if active branch used do go via NODE, set parent's branch to active
       ;; branch of NODE
       ((= (jump-tree-node-branch parent) index)
        (setf (jump-tree-node-branch parent)
              (+ index (jump-tree-node-branch node))))
       ;; if active branch didn't go via NODE, update parent's branch to point
       ;; to same node as before
       ((> (jump-tree-node-branch parent) index)
        (incf (jump-tree-node-branch parent)
              (1- (length (jump-tree-node-next node))))))
      ;; replace NODE in parent's next list with NODE's entire next list
      (if (= index 0)
          (setf (jump-tree-node-next parent)
                (nconc (jump-tree-node-next node)
                       (cdr (jump-tree-node-next parent))))
        (setq i (nthcdr (1- index) (jump-tree-node-next parent)))
        (setcdr i (nconc (jump-tree-node-next node) (cddr i)))))
    ;; update previous links of NODE's children
    (dolist (n (jump-tree-node-next node))
      (setf (jump-tree-node-previous n) parent))))

(defun jump-tree-mapc (func node)
  "Apply FUNC to NODE and to each node below it."
  (let ((stack (list node))
        n)
    (while stack
      (setq n (pop stack))
      (funcall func n)
      (setq stack (append (jump-tree-node-next n) stack)))))

(defun jump-tree-index (node list)
  "Find the first occurrence of NODE in LIST.
Return the index of the matching item, or nil of not found.
Comparison is done with `eq'."
  (let ((i 0))
    (catch 'found
      (while (progn
               (when (eq node (car list)) (throw 'found i))
               (incf i)
               (setq list (cdr list))))
      nil)))


;;; =====================================================================
;;;             position list utility functions
(defun jump-tree-pos-list-discard-invalid ()
  "If the file or buffer is closed, then the marker is invalid.
This function will remove these invalid entries."
  (setq jump-tree-pos-list
        (remove-if (lambda (position)
                     (or (not (markerp (cdr position)))
                         (not (marker-buffer (cdr position)))))
                   jump-tree-pos-list)))

(defun jump-tree-pos-list-transfer-to-tree ()
  "Transfer entries accumulated in `jump-tree-pos-list' to `jump-tree-pos-tree'."

  ;; `jump-tree-pos-list-transfer-to-tree' should never be called when jump is disabled
  ;; (i.e. `jump-tree-pos-tree' is t)
  (assert (not (eq jump-tree-pos-tree t)))

  ;; if `jump-tree-pos-tree' is empty, create initial jump-tree
  (when (null jump-tree-pos-tree) (setq jump-tree-pos-tree (make-jump-tree)))

  (jump-tree-pos-list-discard-invalid)

  (when jump-tree-pos-list
    ;; create new node from first changeset in `jump-tree-pos-list', save old
    ;; `jump-tree-pos-tree' current node, and make new node the current node
    (let* ((node (jump-tree-make-node nil (pop jump-tree-pos-list)))
           (splice (jump-tree-current jump-tree-pos-tree))
           (count 1))
      (setf (jump-tree-current jump-tree-pos-tree) node)
      ;; grow tree fragment backwards
      (while jump-tree-pos-list
        (setq node
              (jump-tree-grow-backwards node (pop jump-tree-pos-list)))
        (incf count))
      ;; build a new branch, number 0.
      (setf (jump-tree-node-previous node) splice)
      (push node (jump-tree-node-next splice))
      (setf (jump-tree-node-branch splice) 0)
      (incf (jump-tree-count jump-tree-pos-tree) count))
    ;; discard position history if necessary
    (jump-tree-discard-history)))

(defun jump-tree-pos-list-rebuild-from-tree ()
  "Rebuild `jump-tree-pos-list' from information in `jump-tree-pos-tree'.
When some buffers are closed, and the markers become invalid, we should clear
these nodes."
  (unless (eq jump-tree-pos-list t)
    (jump-tree-pos-list-transfer-to-tree)
    (setq jump-tree-pos-list nil)
    (when jump-tree-pos-tree
      (let ((stack (list (list (jump-tree-root jump-tree-pos-tree)))))
        (push (sort (mapcar 'identity (jump-tree-node-next (caar stack)))
                    (lambda (a b)
                      (time-less-p (jump-tree-node-timestamp a)
                                   (jump-tree-node-timestamp b))))
              stack)
        ;; Traverse tree in depth-and-oldest-first order, but add position records
        ;; on the way down, and jump-next records on the way up.
        (while (or (car stack)
                   (not (eq (car (nth 1 stack))
                            (jump-tree-current jump-tree-pos-tree))))
          (if (car stack)
              (progn
                (setq jump-tree-pos-list
                      (append (jump-tree-node-position (caar stack))
                              jump-tree-pos-list))
                (push (sort (mapcar 'identity
                                    (jump-tree-node-next (caar stack)))
                            (lambda (a b)
                              (time-less-p (jump-tree-node-timestamp a)
                                           (jump-tree-node-timestamp b))))
                      stack))
            (pop stack)
            (pop (car stack))))))))


;;; =====================================================================
;;;                History discarding utility functions

(defun jump-tree-oldest-leaf (node)
  "Return oldest leaf node below NODE."
  (while (jump-tree-node-next node)
    (setq node
          (car (sort (mapcar 'identity (jump-tree-node-next node))
                     (lambda (a b)
                       (time-less-p (jump-tree-node-timestamp a)
                                    (jump-tree-node-timestamp b)))))))
  node)

(defun jump-tree-discard-node (node)
  "Discard NODE from `jump-tree-pos-tree', and return next in line for discarding."

  ;; don't discard current node
  (unless (eq node (jump-tree-current jump-tree-pos-tree))

    ;; discarding root node...
    (if (eq node (jump-tree-root jump-tree-pos-tree))
        (cond
         ;; should always discard branches before root
         ((> (length (jump-tree-node-next node)) 1)
          (error "Trying to discard jump-tree root which still\
 has multiple branches"))
         ;; don't discard root if current node is only child
         ((eq (car (jump-tree-node-next node))
              (jump-tree-current jump-tree-pos-tree))
          nil)
         ;; discard root
         (t
          ;; clear any register referring to root
          (let ((pos (jump-tree-node-register node)))
            (when (and pos (eq (get-register pos) node))
              (set-register pos nil)))
          ;; make child of root into new root
          (setq node (setf (jump-tree-root jump-tree-pos-tree)
                           (car (jump-tree-node-next node))))
          (decf (jump-tree-count jump-tree-pos-tree))
          ;; discard new root's position data and PREVIOUS link
          (setf (jump-tree-node-position node) nil
                (jump-tree-node-previous node) nil)
          ;; if new root has branches, or new root is current node, next node
          ;; to discard is oldest leaf, otherwise it's new root
          (if (or (> (length (jump-tree-node-next node)) 1)
                  (eq (car (jump-tree-node-next node))
                      (jump-tree-current jump-tree-pos-tree)))
              (jump-tree-oldest-leaf node)
            node)))

      ;; discarding leaf node...
      (let* ((parent (jump-tree-node-previous node))
             (current (nth (jump-tree-node-branch parent)
                           (jump-tree-node-next parent))))
        ;; clear any register referring to the discarded node
        (let ((pos (jump-tree-node-register node)))
          (when (and pos (eq (get-register pos) node))
            (set-register pos nil)))
        (decf (jump-tree-count jump-tree-pos-tree))
        ;; discard leaf
        (setf (jump-tree-node-next parent)
              (delq node (jump-tree-node-next parent))
              (jump-tree-node-branch parent)
              (jump-tree-index current (jump-tree-node-next parent)))
        ;; if parent has branches, or parent is current node, next node to
        ;; discard is oldest leaf, otherwise it's the parent itself
        (if (or (eq parent (jump-tree-current jump-tree-pos-tree))
                (and (jump-tree-node-next parent)
                     (or (not (eq parent (jump-tree-root jump-tree-pos-tree)))
                         (> (length (jump-tree-node-next parent)) 1))))
            (jump-tree-oldest-leaf parent)
          parent)))))

(defun jump-tree-discard-history ()
  "Discard position history until we're within memory usage limits.
Set by `jump-tree-pos-tree-limit'."

  (when (> (jump-tree-count jump-tree-pos-tree) jump-tree-pos-tree-limit)
    ;; if there are no branches off root, first node to discard is root;
    ;; otherwise it's leaf node at botom of oldest branch
    (let ((node (if (> (length (jump-tree-node-next
                                (jump-tree-root jump-tree-pos-tree))) 1)
                    (jump-tree-oldest-leaf (jump-tree-root jump-tree-pos-tree))
                  (jump-tree-root jump-tree-pos-tree))))

      ;; discard nodes until next node to discard would bring memory use
      ;; within `jump-tree-pos-tree-limit'
      (while (and node
                  (> (jump-tree-count jump-tree-pos-tree) jump-tree-pos-tree-limit))
        (setq node (jump-tree-discard-node node))))))

(defun jump-tree-jump-prev (&optional arg)
  "Jump to the previous position.
Repeat this command to position more changes.
A numeric ARG serves as a repeat count.
In Transient Mark mode when the mark is active, only position changes
within the current region.  Similarly, when not in Transient Mark
mode, just \\[universal-argument] as an argument limits position to
changes within the current region."
  (interactive "*P")
  (unless jump-tree-mode
    (user-error "`jump-tree-mode' not enabled in buffer"))
  ;; throw error if position is disabled in buffer
  (when (eq jump-tree-pos-list t)
    (user-error "No position information in this buffer"))
  (jump-tree-jump-prev-1 arg)
  ;; inform user if at branch point
  (when (> (jump-tree-num-branches) 1) (message "Jump-Prev branch point!")))

(defun jump-tree-jump-prev-1 (&optional arg)
  "Internal position function.
A numeric ARG serves as a repeat count."
  (setq deactivate-mark t)
  (let ((jump-tree-in-progress t)
        pos current)
    ;; transfer entries accumulated in `jump-tree-pos-list' to
    ;; `jump-tree-pos-tree'
    (when jump-tree-pos-list
      (jump-tree-pos-list-set))

    (jump-tree-pos-list-transfer-to-tree)
    (dotimes (i (or (and (numberp arg) (prefix-numeric-value arg)) 1))
      ;; check if at top of position tree
      (setq current (jump-tree-current jump-tree-pos-tree))
      (unless (jump-tree-node-previous current)
        (user-error "No further jump-prev information"))
      (setq current (jump-tree-node-previous current))
      (setf (jump-tree-current jump-tree-pos-tree) current)

      (jump-tree-pos-list-jump (jump-tree-node-position current)))))

(defun jump-tree-jump-next (&optional arg)
  "Jump to the next position.
A numeric ARG serves as a repeat count.
In Transient Mark mode when the mark is active, only jump-next changes
within the current region.  Similarly, when not in Transient Mark
mode, just \\[universal-argument] as an argument limits jump-next to
changes within the current region."
  (interactive "*P")
  (unless jump-tree-mode
    (user-error "`jump-tree-mode' not enabled in buffer"))
  ;; throw error if position is disabled in buffer
  (when (eq jump-tree-pos-list t)
    (user-error "No position information in this buffer"))
  (jump-tree-jump-next-1 arg)
  ;; inform user if at branch point
  (when (> (jump-tree-num-branches) 1) (message "Jump-Prev branch point!")))

(defun jump-tree-jump-next-1 (&optional arg)
  "Internal jump-next function.
A numeric ARG serves as a repeat count."
  (setq deactivate-mark t)
  (let ((jump-tree-in-progress t)
        pos current)
    ;; transfer entries accumulated in `jump-tree-pos-list' to
    ;; `jump-tree-pos-tree'
    (jump-tree-pos-list-transfer-to-tree)
    (dotimes (i (or (and (numberp arg) (prefix-numeric-value arg)) 1))
      ;; check if at bottom of position tree
      (setq current (jump-tree-current jump-tree-pos-tree))
      (when (null (jump-tree-node-next current))
        (user-error "No further jump-next information"))
      (setq current (nth (jump-tree-node-branch current)
                         (jump-tree-node-next current)))
      (setf (jump-tree-current jump-tree-pos-tree) current)

      (jump-tree-pos-list-jump (jump-tree-node-position current)))))

(defun jump-tree-switch-branch (branch)
  "Switch to a different BRANCH of the position tree.
This will affect which branch to descend when *jump-nexting* changes
using `jump-tree-jump-next'."
  (interactive (list (or (and prefix-arg (prefix-numeric-value prefix-arg))
                         (and (not (eq jump-tree-pos-list t))
                              (or (jump-tree-pos-list-transfer-to-tree) t)
                              (let ((b (jump-tree-node-branch
                                        (jump-tree-current
                                         jump-tree-pos-tree))))
                                (cond
                                 ;; switch to other branch if only 2
                                 ((= (jump-tree-num-branches) 2) (- 1 b))
                                 ;; prompt if more than 2
                                 ((> (jump-tree-num-branches) 2)
                                  (read-number
                                   (format "Branch (0-%d, on %d): "
                                           (1- (jump-tree-num-branches)) b)))
                                 ))))))
  (unless jump-tree-mode
    (user-error "`jump-tree-mode' not enabled in buffer"))
  ;; throw error if position is disabled in buffer
  (when (eq jump-tree-pos-list t)
    (user-error "No position information in this buffer"))
  ;; sanity check branch number
  (when (<= (jump-tree-num-branches) 1)
    (user-error "Not at position branch point"))
  (when (or (< branch 0) (> branch (1- (jump-tree-num-branches))))
    (user-error "Invalid branch number"))
  ;; transfer entries accumulated in `jump-tree-pos-list' to `jump-tree-pos-tree'
  (jump-tree-pos-list-transfer-to-tree)
  ;; switch branch
  (setf (jump-tree-node-branch (jump-tree-current jump-tree-pos-tree))
        branch)
  (message "Switched to branch %d" branch))

(defun jump-tree-set (node)
  "Set buffer to state corresponding to NODE.
Returns intersection point between path back from current node and path
back from selected NODE."
  (let ((path (make-hash-table :test 'eq))
        (n node))
    (puthash (jump-tree-root jump-tree-pos-tree) t path)
    ;; build list of nodes leading back from selected node to root, updating
    ;; branches as we go to point down to selected node
    (while (progn
             (puthash n t path)
             (when (jump-tree-node-previous n)
               (setf (jump-tree-node-branch (jump-tree-node-previous n))
                     (jump-tree-index
                      n (jump-tree-node-next (jump-tree-node-previous n))))
               (setq n (jump-tree-node-previous n)))))
    ;; work backwards from current node until we intersect path back from
    ;; selected node
    (setq n (jump-tree-current jump-tree-pos-tree))
    (while (not (gethash n path))
      (setq n (jump-tree-node-previous n)))
    ;; ascend tree until intersection node
    (while (not (eq (jump-tree-current jump-tree-pos-tree) n))
      (jump-tree-jump-prev-1 nil nil))
    ;; descend tree until selected node
    (while (not (eq (jump-tree-current jump-tree-pos-tree) node))
      (jump-tree-jump-next-1 nil nil))
    n))  ; return intersection node

(defun jump-tree-save-state-to-register (register)
  "Store current jump-tree state to REGISTER.
The saved state can be restored using
`jump-tree-restore-state-from-register'.
Argument is a character, naming the register."
  (interactive "cjump-tree state to register: ")
  (unless jump-tree-mode
    (user-error "`jump-tree-mode' not enabled in buffer"))
  ;; throw error if position is disabled in buffer
  (when (eq jump-tree-pos-list t)
    (user-error "No position information in this buffer"))
  ;; transfer entries accumulated in `jump-tree-pos-list' to `jump-tree-pos-tree'
  (jump-tree-pos-list-transfer-to-tree)
  ;; save current node to REGISTER
  (set-register
   register (registerv-make
             (jump-tree-make-register-data
              (current-buffer) (jump-tree-current jump-tree-pos-tree))
             :print-func 'jump-tree-register-data-print-func))
  ;; record REGISTER in current node, for visualizer
  (setf (jump-tree-node-register (jump-tree-current jump-tree-pos-tree))
        register))

(defun jump-tree-restore-state-from-register (register)
  "Restore jump-tree state from REGISTER.
The state must be saved using `jump-tree-save-state-to-register'.
Argument is a character, naming the register."
  (interactive "*cRestore jump-tree state from register: ")
  (unless jump-tree-mode
    (user-error "`jump-tree-mode' not enabled in buffer"))
  ;; throw error if position is disabled in buffer, or if register doesn't contain
  ;; an jump-tree node
  (let ((data (registerv-data (get-register register))))
    (cond
     ((eq jump-tree-pos-list t)
      (user-error "No position information in this buffer"))
     ((not (jump-tree-register-data-p data))
      (user-error "Register doesn't contain jump-tree state"))
     ((not (eq (current-buffer) (jump-tree-register-data-buffer data)))
      (user-error "Register contains jump-tree state for a different buffer")))
    ;; transfer entries accumulated in `jump-tree-pos-list' to `jump-tree-pos-tree'
    (jump-tree-pos-list-transfer-to-tree)
    ;; restore buffer state corresponding to saved node
    (jump-tree-set (jump-tree-register-data-node data))))

(provide 'jump-tree-pos)
;;; jump-tree-pos.el ends here
