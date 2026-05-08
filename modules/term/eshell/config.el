;;; term/eshell/config.el -*- lexical-binding: t; -*-

;; see:
;;   + `+eshell/here': open eshell in the current window
;;   + `+eshell/toggle': toggles an eshell popup
;;   + `+eshell/frame': converts the current frame into an eshell-dedicated
;;   frame. Once the last eshell process is killed, the old frame configuration
;;   is restored.

(defvar +eshell-config-dir
  (expand-file-name "eshell/" doom-user-dir)
  "Where to store eshell configuration files, as opposed to
`eshell-directory-name', which is where Doom will store temporary/data files.")

(defvar eshell-directory-name (file-name-concat doom-profile-data-dir "eshell")
  "Where to store temporary/data files, as opposed to `eshell-config-dir',
which is where Doom will store eshell configuration files.")

(defvar +eshell-enable-new-shell-on-split t
  "If non-nil, spawn a new eshell session after splitting from an eshell
buffer.")

(defvar +eshell-kill-window-on-exit nil
  "If non-nil, eshell will close windows along with its eshell buffers.")

(defvar +eshell-aliases
  '(("q"  "exit")           ; built-in
    ("f"  "find-file $1")
    ("ff" "find-file-other-window $1")
    ("d"  "dired $1")
    ("bd" "eshell-up $1")
    ("rg" "rg --color=always $*")
    ("l"  "ls -lh $*")
    ("ll" "ls -lah $*")
    ("git" "git --no-pager $*")
    ("gg" "magit-status")
    ("cdp" "cd-to-project")
    ("clear" "clear-scrollback")) ; more sensible than default
  "An alist of default eshell aliases, meant to emulate useful shell utilities,
like fasd and bd. Note that you may overwrite these in your
`eshell-aliases-file'. This is here to provide an alternative, elisp-centric way
to define your aliases.

You should use `set-eshell-alias!' to change this.")

;; These files are exceptions, because they may contain configuration
(defvar eshell-aliases-file (concat +eshell-config-dir "aliases"))
(defvar eshell-rc-script    (concat +eshell-config-dir "profile"))
(defvar eshell-login-script (concat +eshell-config-dir "login"))

(defvar +eshell--default-aliases nil)


;;
;;; Packages

(after! eshell ; built-in
  (set-lookup-handlers! 'eshell-mode
    :documentation #'+eshell-lookup-documentation)

  (setq eshell-banner-message
        '(format "%s %s\n"
                 (propertize (format " %s " (string-trim (buffer-name)))
                             'face 'mode-line-highlight)
                 (propertize (current-time-string)
                             'face 'font-lock-keyword-face))
        eshell-scroll-to-bottom-on-input 'all
        eshell-scroll-to-bottom-on-output 'all
        eshell-kill-processes-on-exit t
        eshell-hist-ignoredups t
        ;; Don't record command in history if prefixed with whitespace
        ;; TODO: Use `eshell-input-filter-initial-space' when Emacs 25 support is dropped
        eshell-input-filter (lambda (input) (not (string-match-p "\\`\\s-+" input)))
        ;; em-prompt
        eshell-prompt-regexp "^[^#$\n]* [#$λ] "
        eshell-prompt-function #'+eshell-default-prompt-fn
        ;; em-glob
        eshell-glob-case-insensitive t
        eshell-error-if-no-glob t)

  ;; Keep track of open eshell buffers
  (add-hook 'eshell-mode-hook #'+eshell-init-h)
  (add-hook 'eshell-exit-hook #'+eshell-cleanup-h)

  ;; UX: Temporarily disable undo history between command executions. Otherwise,
  ;;   undo could destroy output while it's being printed or delete buffer
  ;;   contents past the boundaries of the current prompt.
  (add-hook 'eshell-pre-command-hook #'buffer-disable-undo)
  (add-hook! 'eshell-post-command-hook
    (defun +eshell--enable-undo-h ()
      (buffer-enable-undo (current-buffer))
      (setq buffer-undo-list nil)))

  ;; UX: Prior output in eshell buffers should be read-only. Otherwise, it's
  ;;   trivial to make edits in visual modes (like evil's or term's
  ;;   term-line-mode) and leave the buffer in a half-broken state (which you
  ;;   must flush out with a couple RETs, which may execute the broken text in
  ;;   the buffer),
  (add-hook! 'eshell-pre-command-hook
    (defun +eshell-protect-input-in-visual-modes-h ()
      (when (and eshell-last-input-start
                 eshell-last-input-end)
        (add-text-properties eshell-last-input-start
                             (1- eshell-last-input-end)
                             '(read-only t)))))
  (add-hook! 'eshell-post-command-hook
    (defun +eshell-protect-output-in-visual-modes-h ()
      (when (and eshell-last-input-end
                 eshell-last-output-start)
        (add-text-properties eshell-last-input-end
                             eshell-last-output-start
                             '(read-only t)))))

  ;; Enable autopairing in eshell
  (add-hook 'eshell-mode-hook #'electric-pair-local-mode)

  ;; Persp-mode/workspaces integration
  (when (modulep! :ui workspaces)
    (add-hook 'persp-activated-functions #'+eshell-switch-workspace-fn)
    (add-hook 'persp-before-switch-functions #'+eshell-save-workspace-fn))

  ;; UI enhancements
  (add-hook! 'eshell-mode-hook
    (defun +eshell-enable-text-wrapping-h ()
      (visual-line-mode +1)
      (set-display-table-slot standard-display-table 0 ?\ )))

  (add-hook 'eshell-mode-hook #'mode-line-invisible-mode)

  ;; Remove hscroll-margin in shells, otherwise you get jumpiness when the
  ;; cursor comes close to the left/right edges of the window.
  (setq-hook! 'eshell-mode-hook hscroll-margin 0)

  ;; Recognize prompts as Imenu entries.
  (setq-hook! 'eshell-mode-hook
    imenu-generic-expression
    `((,(propertize "λ" 'face 'eshell-prompt)
       ,(concat eshell-prompt-regexp "\\(.*\\)") 1)))

  ;; Don't auto-write our aliases! Let us manage our own `eshell-aliases-file'
  ;; or configure `+eshell-aliases' via elisp.
  (advice-add #'eshell-write-aliases-list :override #'ignore)

  (add-to-list 'eshell-modules-list 'eshell-tramp)

  ;; Visual commands require a proper terminal. Eshell can't handle that, so
  ;; it delegates these commands to a term buffer.
  (after! em-term
    (dolist (cmd '("tmux" "htop" "vim" "nvim" "ncmpcpp"))
      (add-to-list 'eshell-visual-commands cmd)))

  (after! em-alias
    (setq +eshell--default-aliases eshell-command-aliases-list
          eshell-command-aliases-list
          (append eshell-command-aliases-list
                  +eshell-aliases))))


(after! esh-mode
  (map! :map eshell-mode-map
        :n  "RET"    #'+eshell/goto-end-of-prompt
        :n  [return] #'+eshell/goto-end-of-prompt
        :ni "C-j"    #'eshell-next-matching-input-from-input
        :ni "C-k"    #'eshell-previous-matching-input-from-input
        :ig "C-d"    #'+eshell/quit-or-delete-char
        :i  "C-c h"  #'evil-window-left
        :i  "C-c j"  #'evil-window-down
        :i  "C-c k"  #'evil-window-up
        :i  "C-c l"  #'evil-window-right
        "C-s"   #'+eshell/search-history
        ;; Emacs bindings
        "C-e"   #'end-of-line
        ;; Tmux-esque prefix keybinds
        "C-c s" #'+eshell/split-below
        "C-c v" #'+eshell/split-right
        "C-c x" #'+eshell/kill-and-close
        [remap split-window-below]  #'+eshell/split-below
        [remap split-window-right]  #'+eshell/split-right
        [remap doom/backward-to-bol-or-indent] #'eshell-bol
        [remap doom/backward-kill-to-bol-and-indent] #'eshell-kill-input
        [remap evil-delete-back-to-indentation] #'eshell-kill-input
        [remap evil-window-split]   #'+eshell/split-below
        [remap evil-window-vsplit]  #'+eshell/split-right
        ;; To emulate terminal keybinds
        "C-l"   (cmd! (eshell/clear-scrollback) (eshell-emit-prompt))
        (:localleader
         "b" #'eshell-insert-buffer-name
         "e" #'eshell-insert-envvar
         "s" #'+eshell/search-history)))

(use-package! eat
  :config
  (add-hook! 'eshell-load-hook #'eat-eshell-mode))

(use-package! eshell-up
  :commands eshell-up eshell-up-peek)


(use-package! eshell-z
  :after eshell
  :config
  ;; Use zsh's db if it exists, otherwise, store it in `doom-cache-dir'
  (unless (file-exists-p eshell-z-freq-dir-hash-table-file-name)
    (setq eshell-z-freq-dir-hash-table-file-name
          (expand-file-name "z" eshell-directory-name))))


(use-package! esh-help
  :after eshell
  :config
  (setup-esh-help-eldoc)
  ;; HACK: Fixes tom-tan/esh-help#7.
  (defadvice! +eshell-esh-help-eldoc-man-minibuffer-string-a (cmd)
    "Return minibuffer help string for the shell command CMD.
Return nil if there is none."
    :override #'esh-help-eldoc-man-minibuffer-string
    (if-let* ((cache-result (gethash cmd esh-help-man-cache)))
        (unless (eql 'none cache-result)
          cache-result)
      (let ((str (split-string (esh-help-man-string cmd) "\n")))
        (if (equal (concat "No manual entry for " cmd) (car str))
            (ignore (puthash cmd 'none esh-help-man-cache))
          (puthash
           cmd (when-let* ((str (seq-drop-while (fn! (not (string-match-p "^SYNOPSIS$" %))) str))
                           (str (nth 1 str)))
                 (substring str (string-match-p "[^\s\t]" str)))
           esh-help-man-cache))))))


(use-package! eshell-did-you-mean
  :after esh-mode ; Specifically esh-mode, not eshell
  :config (eshell-did-you-mean-setup)

  ;; HACK: `pcomplete-completions' returns a function, but
  ;;   `eshell-did-you-mean--get-all-commands' unconditionally expects it to
  ;;   return a list of strings, causing wrong-type-arg errors in many cases.
  ;;   `all-completions' handles all these cases.
  (defadvice! +eshell--fix-eshell-did-you-mean-a (&rest _)
    :override #'eshell-did-you-mean--get-all-commands
    (unless eshell-did-you-mean--all-commands
      (setq eshell-did-you-mean--all-commands
            (all-completions "" (pcomplete-completions))))))


(use-package! eshell-syntax-highlighting
  :hook (eshell-mode . eshell-syntax-highlighting-mode)
  :config
  (defadvice! +eshell-filter-history-from-highlighting-a (&rest _)
    "Selectively inhibit `eshell-syntax-highlighting-mode'.
So that mathces from history show up with highlighting."
    :before-until #'eshell-syntax-highlighting--enable-highlighting
    (memq this-command '(eshell-previous-matching-input-from-input
                         eshell-next-matching-input-from-input)))

  (defun +eshell-syntax-highlight-maybe-h ()
    "Hook added to `pre-command-hook' to restore syntax highlighting
when inhibited to show history matches."
    (when (and eshell-syntax-highlighting-mode
               (memq last-command '(eshell-previous-matching-input-from-input
                                    eshell-next-matching-input-from-input)))
      (eshell-syntax-highlighting--enable-highlighting)))

  (add-hook! 'eshell-syntax-highlighting-elisp-buffer-setup-hook
    (defun +eshell-syntax-highlighting-mode-h ()
      "Hook to enable `+eshell-syntax-highlight-maybe-h'."
      (if eshell-syntax-highlighting-mode
          (add-hook 'pre-command-hook #'+eshell-syntax-highlight-maybe-h nil t)
        (remove-hook 'pre-command-hook #'+eshell-syntax-highlight-maybe-h t))))

  (when (fboundp 'highlight-quoted-mode)
    (add-hook 'eshell-syntax-highlighting-elisp-buffer-setup-hook #'highlight-quoted-mode)))


(use-package! pcmpl-args
  :after eshell
  :config
  (dolist (cmd '("doom" "nix-shell"))
    (defalias (intern (concat "pcomplete/" cmd))
      #'pcmpl-args-pcomplete-on-help))
  (dolist (cmd '("fd" "rg" "exa" "emacsclient"))
    (defalias (intern (concat "pcomplete/" cmd))
      #'pcmpl-args-pcomplete-on-man)))

;;; ============================================================
;;; Internal helpers
;;; (private; not meant to be called directly from Eshell)
;;; ============================================================

(defun qol--has (cmd)
  "Return non-nil when CMD is available on PATH."
  (executable-find cmd))

(defun qol--command-output (program &rest args)
  "Run PROGRAM with ARGS synchronously and return trimmed stdout, or nil on error."
  (with-temp-buffer
    (let ((status (apply #'process-file program nil t nil args)))
      (when (zerop status)
        (string-trim (buffer-string))))))

(defun qol--read-lines (program &rest args)
  "Run PROGRAM with ARGS and return non-empty output lines as a list."
  (let ((out (apply #'qol--command-output program args)))
    (when (and out (not (string-empty-p out)))
      (split-string out "\n" t))))

(defun qol--completing-read (prompt choices &optional initial)
  "Completing-read wrapper that ignores case."
  (let ((completion-ignore-case t))
    (completing-read prompt choices nil t initial)))

(defun qol--warn-once (key fmt &rest args)
  "Emit a one-shot warning keyed by KEY."
  (unless (gethash key qol--warned)
    (puthash key t qol--warned)
    (apply #'message (concat "[qol] ⚠ " fmt) args)))

(defvar qol--warned (make-hash-table :test 'equal)
  "Keys of already-emitted `qol--warn-once' warnings.")

(defvar qol--features (make-hash-table :test 'equal)
  "Registry of active qol feature names → backend strings.")

(defun qol--feature (name value)
  "Record that feature NAME is backed by VALUE."
  (puthash name value qol--features))


;;; ============================================================
;;; qol-run-mode — lightweight output buffer for async commands
;;; ============================================================
;;
;; A dedicated major mode similar to compilation-mode but lighter.
;; Every `qol--run-buffer' call produces one of these buffers.
;;
;; Normal-state keybindings (set after Evil loads):
;;   g    re-run the exact same command
;;   k    interrupt (SIGINT)
;;   K    kill (SIGKILL)
;;   q    bury the window
;;   Y    yank all output to kill ring
;;   e    jump back to eshell
;;   d    show working directory in minibuffer

(defvar-local qol--run-command nil
  "The command list (program + args) that produced this run buffer.")

(defvar-local qol--run-directory nil
  "The `default-directory' at the time the run buffer was created.")

(defun qol-run-rerun ()
  "Re-run the command that produced the current qol run buffer."
  (interactive)
  (unless qol--run-command
    (user-error "[qol] No command stored for this buffer"))
  (let ((default-directory (or qol--run-directory default-directory)))
    (qol--run-buffer (car qol--run-command)
                     (cdr qol--run-command)
                     (buffer-name)
                     t)))

(defun qol-run-kill ()
  "Interrupt (SIGINT) the process in the current qol run buffer."
  (interactive)
  (if-let ((proc (get-buffer-process (current-buffer))))
      (progn (interrupt-process proc)
             (message "[qol] Sent SIGINT to %s" (process-name proc)))
    (message "[qol] No live process in this buffer")))

(defun qol-run-kill-sigkill ()
  "Kill (SIGKILL) the process in the current qol run buffer."
  (interactive)
  (if-let ((proc (get-buffer-process (current-buffer))))
      (progn (kill-process proc)
             (message "[qol] Sent SIGKILL to %s" (process-name proc)))
    (message "[qol] No live process in this buffer")))

(defun qol-run-copy-output ()
  "Copy the entire output of the current qol run buffer to the kill ring."
  (interactive)
  (kill-new (buffer-substring-no-properties (point-min) (point-max)))
  (message "[qol] Buffer output copied to kill ring"))

(defun qol-run-open-in-eshell ()
  "Switch to the most recent eshell buffer, or create one."
  (interactive)
  (if-let ((buf (seq-find (lambda (b)
                            (with-current-buffer b
                              (derived-mode-p 'eshell-mode)))
                          (buffer-list))))
      (pop-to-buffer buf)
    (eshell)))

(defvar qol-run-mode-map (make-sparse-keymap)
  "Keymap for `qol-run-mode' buffers.")

(define-derived-mode qol-run-mode special-mode "qol-run"
  "Major mode for qol async output buffers.

Key bindings:
\\{qol-run-mode-map}")

(after! evil
  (evil-define-key* 'normal qol-run-mode-map
    (kbd "g")     #'qol-run-rerun
    (kbd "k")     #'qol-run-kill
    (kbd "K")     #'qol-run-kill-sigkill
    (kbd "q")     #'quit-window
    (kbd "Y")     #'qol-run-copy-output
    (kbd "e")     #'qol-run-open-in-eshell
    (kbd "d")     (lambda ()
                    (interactive)
                    (message "[qol] dir: %s"
                             (abbreviate-file-name
                              (or qol--run-directory default-directory))))
    (kbd "C-c C-c") #'qol-run-kill
    (kbd "C-c C-k") #'qol-run-kill-sigkill))


;;; ============================================================
;;; qol--run-buffer — canonical async command runner
;;; ============================================================

(defun qol--run-buffer (program args &optional buffer-name reuse)
  "Run PROGRAM with ARGS in a dedicated qol run buffer.

BUFFER-NAME overrides the auto-generated buffer name.
When REUSE is non-nil the existing buffer is erased and reused.
Returns the buffer object."
  (unless (qol--has program)
    (user-error "[qol] Missing command: %s" program))
  (let* ((cmd   (cons program args))
         (bname (or buffer-name
                    (format "*qol:run:%s*" (string-join cmd " "))))
         (buf   (if (and reuse (get-buffer bname))
                    (get-buffer bname)
                  (generate-new-buffer bname)))
         (dir   default-directory))
    ;; Kill any existing process in the buffer.
    (when-let ((old (get-buffer-process buf)))
      (when (process-live-p old)
        (delete-process old)))
    ;; Set up the buffer.
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (erase-buffer))
      (qol-run-mode)
      (setq qol--run-command cmd
            qol--run-directory dir)
      (let ((inhibit-read-only t))
        (insert
         (propertize
          (format "[qol] run: %s\n[qol] dir: %s\n[qol] started: %s\n\n"
                  (string-join cmd " ")
                  (abbreviate-file-name dir)
                  (format-time-string "%Y-%m-%d %H:%M:%S"))
          'face 'font-lock-comment-face))))
    ;; Start the process.
    (let ((proc
           (make-process
            :name            (format "qol:%s" program)
            :buffer          buf
            :command         cmd
            :connection-type 'pipe
            :noquery         t
            :filter
            (lambda (proc output)
              (when-let ((b (process-buffer proc)))
                (when (buffer-live-p b)
                  (with-current-buffer b
                    (let ((inhibit-read-only t)
                          (moving (= (point) (process-mark proc))))
                      (save-excursion
                        (goto-char (process-mark proc))
                        (insert output)
                        (set-marker (process-mark proc) (point)))
                      (when moving
                        (goto-char (process-mark proc))))))))
            :sentinel
            (lambda (proc event)
              (when (memq (process-status proc) '(exit signal))
                (when-let ((b (process-buffer proc)))
                  (when (buffer-live-p b)
                    (with-current-buffer b
                      (let* ((inhibit-read-only t)
                             (code (process-exit-status proc))
                             (face (if (zerop code)
                                       'font-lock-string-face
                                     'error))
                             (msg  (format "\n[qol] finished (exit %d): %s  %s\n"
                                           code
                                           (string-trim event)
                                           (format-time-string "%H:%M:%S"))))
                        (save-excursion
                          (goto-char (point-max))
                          (insert (propertize msg 'face face))))))))))))
      (set-marker (process-mark proc)
                  (with-current-buffer buf (point-max))
                  buf))
    (pop-to-buffer buf)
    buf))


;;; ============================================================
;;; qol--run — inline async runner (streams into Eshell buffer)
;;; ============================================================

(defun qol--run (&rest args)
  "Run ARGS asynchronously, streaming output into the current Eshell buffer.

For commands that benefit from a dedicated rerunnable buffer,
prefer `qol--run-buffer' or the `run' Eshell command instead."
  (let* ((program      (car args))
         (program-args (cdr args))
         (buffer       (current-buffer))
         (name         (format "qol:%s" program)))
    (unless (qol--has program)
      (user-error "[qol] Missing command: %s" program))
    (make-process
     :name            name
     :buffer          buffer
     :command         (cons program program-args)
     :connection-type 'pipe
     :noquery         t
     :filter
     (lambda (proc output)
       (when (buffer-live-p buffer)
         (with-current-buffer buffer
           (let ((inhibit-read-only t)
                 (moving (= (point) (process-mark proc))))
             (save-excursion
               (goto-char (process-mark proc))
               (insert output)
               (set-marker (process-mark proc) (point)))
             (when moving
               (goto-char (process-mark proc)))))))
     :sentinel
     (lambda (proc event)
       (when (memq (process-status proc) '(exit signal))
         (when (buffer-live-p buffer)
           (with-current-buffer buffer
             (let ((inhibit-read-only t)
                   (code (process-exit-status proc)))
               (save-excursion
                 (goto-char (process-mark proc))
                 (unless (zerop code)
                   (insert (format "\n[qol] %s finished: %s"
                                   (process-name proc)
                                   (string-trim event))))
                 (set-marker (process-mark proc) (point)))))))))))

(defun qol--sh (&rest command-parts)
  "Run COMMAND-PARTS via `sh -lc' asynchronously into the current buffer."
  (qol--run "sh" "-lc" (string-join command-parts " ")))

(defun qol--terminal-buffer (name command)
  "Open an Eat terminal buffer named NAME and run COMMAND in it."
  (eat nil)
  (rename-buffer (format "*qol:%s*" name) t)
  (eat-line-mode)
  (eat-term-send-string eat-terminal command)
  (eat-term-send-string eat-terminal "\n"))


;;; ============================================================
;;; PATH management
;;; ============================================================

(defun qol-path-list ()
  "Return the current PATH as a list of strings."
  (split-string (or (getenv "PATH") "") path-separator t))

(defun qol-path-set (parts)
  "Set PATH and `exec-path' from PARTS (a list of directory strings).
Returns the new PATH string."
  (setenv "PATH" (mapconcat #'identity parts path-separator))
  (setq exec-path (append parts (list exec-directory)))
  (getenv "PATH"))

(defun eshell/path (&rest _args)
  "Print PATH one entry per line."
  (mapconcat #'identity (qol-path-list) "\n"))

(defun eshell/path_add (dir)
  "Prepend DIR to PATH without duplicates."
  (let* ((dir   (file-truename (expand-file-name dir)))
         (parts (qol-path-list)))
    (unless (file-directory-p dir) (user-error "[qol] Not a directory: %s" dir))
    (qol-path-set (cons dir (delete dir parts)))
    (format "[qol] Added to PATH: %s" dir)))

(defun eshell/path_add_back (dir)
  "Append DIR to PATH without duplicates."
  (let* ((dir   (file-truename (expand-file-name dir)))
         (parts (delete dir (qol-path-list))))
    (unless (file-directory-p dir) (user-error "[qol] Not a directory: %s" dir))
    (qol-path-set (append parts (list dir)))
    (format "[qol] Appended to PATH: %s" dir)))

(defun eshell/path_rm (&rest dirs)
  "Remove DIRS from PATH."
  (let ((remove (mapcar (lambda (d) (file-truename (expand-file-name d))) dirs)))
    (qol-path-set (cl-remove-if (lambda (p) (member (file-truename p) remove))
                                (qol-path-list)))
    "[qol] PATH updated"))

(defun eshell/path_dedupe (&rest _args)
  "Deduplicate PATH, preserving first occurrence of each entry."
  (let (seen new)
    (dolist (p (qol-path-list))
      (let ((canon (ignore-errors (file-truename p))))
        (unless (member canon seen)
          (push canon seen)
          (push p new))))
    (qol-path-set (nreverse new))
    "[qol] PATH deduped"))

(defun eshell/path_contains (dir)
  "Check whether DIR is on PATH."
  (let ((canon (file-truename (expand-file-name dir))))
    (if (member canon (mapcar (lambda (p) (ignore-errors (file-truename p)))
                              (qol-path-list)))
        (format "[qol] PATH contains: %s" canon)
      (format "[qol] PATH does not contain: %s" canon))))


;;; ============================================================
;;; Navigation & directory helpers
;;; ============================================================

(defun eshell/up (&optional n)
  "Move up N directory levels (default 1).

  up
  up 3"
  (let* ((n      (max 1 (or n 1)))
         (target default-directory))
    (dotimes (_ n)
      (setq target (file-name-directory (directory-file-name target))))
    (eshell/cd target)
    (format "[qol] %s" (abbreviate-file-name target))))

(defun eshell/mkcd (dir)
  "Create DIR and cd into it."
  (make-directory dir t)
  (eshell/cd dir)
  (format "[qol] Created and entered: %s" (expand-file-name dir)))

(defun eshell/mktempd (&rest _args)
  "Create a temporary directory, cd into it, and print its path."
  (let ((dir (make-temp-file "qol." t)))
    (eshell/cd dir)
    (format "[qol] Created and entered: %s" dir)))

(defun eshell/proot (&rest _args)
  "Cd to the current project root (Projectile or project.el)."
  (let ((root (cond
               ((and (fboundp 'projectile-project-root)
                     (fboundp 'projectile-project-p)
                     (projectile-project-p))
                (projectile-project-root))
               ((fboundp 'project-current)
                (when-let ((proj (project-current nil)))
                  (project-root proj)))
               (t default-directory))))
    (eshell/cd root)
    (format "[qol] %s" (abbreviate-file-name root))))

(defun eshell/groot (&rest _args)
  "Cd to the current Git repository root."
  (let ((root (or (qol--command-output "git" "rev-parse" "--show-toplevel")
                  (user-error "[qol] Not in a git repository"))))
    (eshell/cd root)
    (format "[qol] %s" (abbreviate-file-name root))))

(defun eshell/fcd (&optional root)
  "Fuzzy-jump to a directory using consult-dir, fd, or find."
  (cond
   ((require 'consult-dir nil t)
    (call-interactively #'consult-dir))
   (t
    (let* ((root (or root default-directory))
           (dirs (if (qol--has "fd")
                     (qol--read-lines "fd" "--type" "d" "." root)
                   (qol--read-lines "find" root "-type" "d")))
           (dir  (qol--completing-read "Directory: " dirs)))
      (eshell/cd dir)))))

(defun eshell/zi (&rest _args)
  "Interactive zoxide jump; falls back to `fcd' when zoxide is unavailable."
  (if (qol--has "zoxide")
      (let ((dest (qol--completing-read "zoxide: "
                                        (qol--read-lines "zoxide" "query" "-l"))))
        (eshell/cd dest)
        (start-process "zoxide-add" nil "zoxide" "add" dest))
    (eshell/fcd default-directory)))


;;; ============================================================
;;; Named Eshell buffers (tmux-session analogue)
;;; ============================================================

(defun qol--eshell-buffer-p (&optional buffer)
  "Return non-nil when BUFFER (default: current) is an Eshell buffer."
  (with-current-buffer (or buffer (current-buffer))
    (derived-mode-p 'eshell-mode)))

(defun qol--goto-eshell-buffer (name &optional directory)
  "Create or switch to Eshell buffer *qol:NAME*.
DIRECTORY is used as `default-directory' when creating a new buffer."
  (let* ((bufname (format "*qol:%s*" name))
         (buf     (get-buffer bufname)))
    (if buf
        (pop-to-buffer-same-window buf)
      (let ((default-directory
             (file-name-as-directory
              (expand-file-name (or directory default-directory)))))
        (eshell t)
        (rename-buffer bufname t)))
    (current-buffer)))

(defun qol--read-eshell-buffer (&optional prompt)
  "Select an active Eshell buffer with completion."
  (let* ((buffers (cl-remove-if-not #'qol--eshell-buffer-p (buffer-list)))
         (names   (mapcar #'buffer-name buffers))
         (name    (qol--completing-read (or prompt "Eshell buffer: ") names)))
    (get-buffer name)))

;; tmux-session-like commands
(defun eshell/t (&optional session)
  "Attach to or create named Eshell buffer SESSION (default: \"main\")."
  (qol--goto-eshell-buffer (or session "main")))

(defun eshell/tn (&optional session)
  "Create a new named Eshell buffer, prompting for a name when SESSION is nil."
  (qol--goto-eshell-buffer (or session (read-string "Session name: "))))

(defun eshell/tls (&rest _args)
  "List all live Eshell buffers (tmux ls analogue)."
  (mapconcat #'buffer-name
             (cl-remove-if-not #'qol--eshell-buffer-p (buffer-list))
             "\n"))

(defun eshell/ta (&optional session)
  "Switch to Eshell buffer SESSION via completion (tmux attach analogue)."
  (if session
      (qol--goto-eshell-buffer session)
    (pop-to-buffer (qol--read-eshell-buffer "Switch Eshell buffer: "))))

(defun eshell/tk (&optional session)
  "Kill named Eshell buffer SESSION after confirmation (tmux kill-session)."
  (let ((buf (if session
                 (get-buffer (format "*qol:%s*" session))
               (qol--read-eshell-buffer "Kill Eshell buffer: "))))
    (unless buf (user-error "[qol] No such Eshell buffer"))
    (when (yes-or-no-p (format "Kill %s? " (buffer-name buf)))
      (kill-buffer buf)
      "[qol] Eshell buffer killed")))

(defun eshell/trn (new-name)
  "Rename the current Eshell buffer to *qol:NEW-NAME*."
  (rename-buffer (format "*qol:%s*" new-name) t))

(defun eshell/tw (&optional name &rest command)
  "Open a new Eshell buffer, optionally running COMMAND in it.
Analogous to `tmux new-window'."
  (let ((buf (qol--goto-eshell-buffer (or name (format-time-string "shell-%H%M%S")))))
    (when command (qol--insert-send-eshell (string-join command " ") buf))
    (buffer-name buf)))

(defun eshell/tx (target &rest command)
  "Send COMMAND to TARGET Eshell buffer (by name or qol session name)."
  (let ((buf (or (get-buffer target)
                 (get-buffer (format "*qol:%s*" target)))))
    (unless buf (user-error "[qol] No target Eshell buffer: %s" target))
    (qol--insert-send-eshell (string-join command " ") buf)))

(defun eshell/tf (&optional name)
  "Open a new frame with a dedicated Eshell buffer."
  (let ((name (or name "frame-shell")))
    (select-frame-set-input-focus (make-frame))
    (eshell/tw name)))

(defun eshell/scratch (&rest _args)
  "Open a fresh throwaway Eshell buffer."
  (let ((name (format "scratch-%s" (format-time-string "%H%M%S"))))
    (qol--goto-eshell-buffer name)
    (format "[qol] Opened scratch buffer: *qol:%s*" name)))

(defun qol--insert-send-eshell (command &optional buffer)
  "Insert COMMAND into Eshell BUFFER at point-max and send it."
  (let ((buf (or buffer (current-buffer))))
    (unless (buffer-live-p buf)
      (user-error "[qol] Buffer is not live"))
    (with-current-buffer buf
      (unless (derived-mode-p 'eshell-mode)
        (user-error "[qol] Target buffer is not an Eshell buffer"))
      (goto-char (point-max))
      (insert command)
      (eshell-send-input))))

(defun qol-tf (&optional name)
  "Create a new frame with an Eshell buffer (interactive version of `eshell/tf')."
  (interactive (list (read-string "Eshell frame name: " nil nil "frame-shell")))
  (eshell/tf (or name "frame-shell")))


;;; ============================================================
;;; run / rls / ratt — dedicated output buffers
;;; ============================================================

(defun eshell/run (&rest args)
  "Run ARGS in a dedicated, rerunnable output buffer.

Usage:
  run <command> [args...]
  run -n <name> <command> [args...]

In the output buffer:
  g  re-run     k  interrupt     K  kill     q  bury
  Y  yank       e  jump to eshell"
  (unless args (user-error "Usage: run [-n <name>] <command> [args...]"))
  (let (bname cmd)
    (if (equal (car args) "-n")
        (progn
          (unless (cddr args)
            (user-error "[qol] run -n requires a name and a command"))
          (setq bname (format "*qol:run:%s*" (cadr args))
                cmd   (cddr args)))
      (setq cmd args))
    (unless cmd (user-error "[qol] run: no command specified"))
    (qol--run-buffer (car cmd) (cdr cmd) bname)))

(defun eshell/rls (&rest _args)
  "List all live qol run buffers with their status, command, and directory."
  (let ((bufs (cl-remove-if-not
               (lambda (b)
                 (with-current-buffer b (derived-mode-p 'qol-run-mode)))
               (buffer-list))))
    (if (null bufs)
        "[qol] No run buffers"
      (mapconcat
       (lambda (b)
         (with-current-buffer b
           (let* ((proc   (get-buffer-process b))
                  (status (if (and proc (process-live-p proc)) "running" "done"))
                  (cmd    (when qol--run-command (string-join qol--run-command " ")))
                  (dir    (when qol--run-directory
                            (abbreviate-file-name qol--run-directory))))
             (format "%-8s  %-30s  %s  [%s]"
                     status (buffer-name b) (or cmd "?") (or dir "?")))))
       bufs "\n"))))

(defun eshell/ratt (&optional name)
  "Switch to a qol run buffer by completion, or by NAME substring."
  (let* ((bufs  (cl-remove-if-not
                 (lambda (b)
                   (with-current-buffer b (derived-mode-p 'qol-run-mode)))
                 (buffer-list)))
         (names (mapcar #'buffer-name bufs))
         (target (if name
                     (or (seq-find (lambda (n)
                                     (string-match-p (regexp-quote name) n))
                                   names)
                         (user-error "[qol] No run buffer matching: %s" name))
                   (qol--completing-read "Run buffer: " names))))
    (pop-to-buffer (get-buffer target))))


;;; ============================================================
;;; File operations
;;; ============================================================

(defun eshell/extract (&rest files)
  "Extract one or more archive FILES into a dedicated run buffer.
Supports: tar.gz/tgz, tar.bz2/tbz2, tar.xz/txz, tar.zst, tar,
          bz2, gz, xz, zst, zip, Z, 7z, rar, deb."
  (unless files (user-error "Usage: extract <archive> [archive2 ...]"))
  (dolist (file files)
    (unless (file-exists-p file) (user-error "[qol] File not found: %s" file))
    (let ((bname (format "*qol:run:extract:%s*" (file-name-nondirectory file))))
      (cond
       ((string-match-p "\\.tar\\.bz2\\'\\|\\.tbz2\\'" file)  (qol--run-buffer "tar"       (list "xjf" file) bname))
       ((string-match-p "\\.tar\\.gz\\'\\|\\.tgz\\'" file)    (qol--run-buffer "tar"       (list "xzf" file) bname))
       ((string-match-p "\\.tar\\.xz\\'\\|\\.txz\\'" file)    (qol--run-buffer "tar"       (list "xJf" file) bname))
       ((string-match-p "\\.tar\\.zst\\'" file)               (qol--run-buffer "tar"       (list "--zstd" "-xf" file) bname))
       ((string-match-p "\\.tar\\'" file)                     (qol--run-buffer "tar"       (list "xf" file) bname))
       ((string-match-p "\\.bz2\\'" file)                     (qol--run-buffer "bunzip2"   (list file) bname))
       ((string-match-p "\\.gz\\'" file)                      (qol--run-buffer "gunzip"    (list file) bname))
       ((string-match-p "\\.xz\\'" file)                      (qol--run-buffer "unxz"      (list file) bname))
       ((string-match-p "\\.zst\\'" file)                     (qol--run-buffer "zstd"      (list "-d" file) bname))
       ((string-match-p "\\.zip\\'" file)                     (qol--run-buffer "unzip"     (list file) bname))
       ((string-match-p "\\.Z\\'" file)                       (qol--run-buffer "uncompress" (list file) bname))
       ((string-match-p "\\.7z\\'" file)                      (qol--run-buffer "7z"        (list "x" file) bname))
       ((string-match-p "\\.rar\\'" file)                     (qol--run-buffer "unrar"     (list "x" file) bname))
       ((string-match-p "\\.deb\\'" file)                     (qol--run-buffer "dpkg"      (list "-x" file (file-name-sans-extension file)) bname))
       (t (user-error "[qol] Unknown archive format: %s" file)))))
  "[qol] Extract launched (see run buffer)")

(defun eshell/backup (&rest paths)
  "Create timestamped .bak copies of PATHS."
  (unless paths (user-error "Usage: backup <path> [path2 ...]"))
  (let ((stamp (format-time-string "%Y%m%d-%H%M%S"))
        made)
    (dolist (src paths)
      (unless (file-exists-p src) (user-error "[qol] Not found: %s" src))
      (let ((dest (format "%s.bak.%s" src stamp)))
        (if (file-directory-p src)
            (copy-directory src dest t t t)
          (copy-file src dest t t t t))
        (push (format "%s -> %s" src dest) made)))
    (concat "[qol] Backed up:\n" (string-join (nreverse made) "\n"))))

(defun eshell/sha256 (&rest files)
  "Print SHA-256 checksums of FILES in a dedicated run buffer."
  (cond
   ((qol--has "sha256sum") (qol--run-buffer "sha256sum" files "*qol:run:sha256*"))
   ((qol--has "shasum")    (qol--run-buffer "shasum" (append '("-a" "256") files) "*qol:run:sha256*"))
   (t (user-error "[qol] sha256 requires sha256sum or shasum"))))

(defun eshell/sizeof (&rest paths)
  "Show human-readable disk usage for PATHS (default: current directory)."
  (let ((targets (or paths (list "."))))
    (cond
     ((qol--has "du")
      (apply #'qol--run-buffer "du" (append '("-sh") targets)
             (list "*qol:run:sizeof*")))
     (t
      (mapconcat
       (lambda (p)
         (if (file-exists-p p)
             (format "%s\t%s"
                     (file-size-human-readable
                      (if (file-directory-p p)
                          (apply #'+ (mapcar (lambda (f)
                                               (or (file-attribute-size
                                                    (file-attributes f))
                                                   0))
                                             (directory-files-recursively p "." nil t)))
                        (or (file-attribute-size (file-attributes p)) 0)))
                     p)
           (format "[qol] Not found: %s" p)))
       targets "\n")))))

(defun eshell/age (&rest files)
  "Print the age of each FILE in human-readable form."
  (unless files (user-error "Usage: age <file> [file2 ...]"))
  (mapconcat
   (lambda (f)
     (if-let ((attrs (file-attributes f)))
         (let* ((mtime (file-attribute-modification-time attrs))
                (age   (float-time (time-subtract (current-time) mtime)))
                (human (cond ((< age 60)    (format "%.0fs" age))
                             ((< age 3600)  (format "%.0fm" (/ age 60)))
                             ((< age 86400) (format "%.1fh" (/ age 3600)))
                             (t             (format "%.1fd" (/ age 86400))))))
           (format "%-40s %s ago" f human))
       (format "[qol] Not found: %s" f)))
   files "\n"))


;;; ============================================================
;;; Process / system helpers
;;; ============================================================

(defun eshell/serve (&optional port host)
  "Start a local HTTP server in `default-directory' on PORT (default 8080).

Falls back through python3 → python → ruby → npx serve."
  (let* ((port  (format "%s" (or port 8080)))
         (host  (or host "localhost"))
         (bname (format "*qol:run:serve:%s*" port)))
    (cond
     ((qol--has "python3") (qol--run-buffer "python3" (list "-m" "http.server" port "--bind" host) bname))
     ((qol--has "python")  (qol--run-buffer "python"  (list "-m" "SimpleHTTPServer" port) bname))
     ((qol--has "ruby")    (qol--run-buffer "ruby"    (list "-run" "-e" "httpd" "." "-p" port) bname))
     ((qol--has "npx")     (qol--run-buffer "npx"     (list "--yes" "serve" "-l" port ".") bname))
     (t (user-error "[qol] No suitable HTTP server found (need python3, ruby, or npx)")))))

(defun eshell/ports (&rest _args)
  "List listening ports in a dedicated run buffer."
  (cond
   ((qol--has "ss")      (qol--run-buffer "ss"      '("-tulnp") "*qol:run:ports*"))
   ((qol--has "netstat") (qol--run-buffer "netstat" '("-tulnp") "*qol:run:ports*"))
   ((qol--has "lsof")    (qol--run-buffer "lsof"    '("-iTCP" "-sTCP:LISTEN" "-n" "-P") "*qol:run:ports*"))
   (t (user-error "[qol] No suitable tool: need ss, netstat, or lsof"))))

(defun eshell/port_kill (port)
  "Kill the process listening on PORT, with confirmation."
  (let* ((pids (delete-dups
                (or (when (qol--has "lsof")
                      (qol--read-lines "lsof" "-ti" (format "TCP:%s" port) "-sTCP:LISTEN"))
                    (when (qol--has "fuser")
                      (qol--read-lines "fuser" (format "%s/tcp" port))))))  )
    (if (null pids)
        (format "[qol] Nothing listening on port %s" port)
      (when (yes-or-no-p (format "Kill PIDs %s on port %s? "
                                 (string-join pids ", ") port))
        (dolist (pid pids) (signal-process (string-to-number pid) 'term))
        (format "[qol] Sent SIGTERM to: %s" (string-join pids ", "))))))

(defun eshell/psg (&optional pattern)
  "Search running processes by PATTERN (regexp).  No arg = list all."
  (let* ((case-fold-search t)
         (lines   (split-string (shell-command-to-string "ps aux") "\n" t))
         (header  (car lines))
         (procs   (cdr lines))
         (matches (if (or (null pattern) (string-empty-p pattern))
                      procs
                    (cl-remove-if-not
                     (lambda (l) (string-match-p (regexp-quote pattern) l))
                     procs))))
    (if matches
        (mapconcat #'identity (cons header matches) "\n")
      (format "[qol] No processes matching: %s" pattern))))

(defun eshell/fkill (&rest _args)
  "Fuzzy-pick and SIGTERM a running process."
  (let* ((lines  (split-string (shell-command-to-string "ps aux") "\n" t))
         (line   (qol--completing-read "Kill process: " (cdr lines)))
         (fields (split-string line "[[:space:]]+" t))
         (pid    (nth 1 fields)))
    (when (and pid (yes-or-no-p (format "SIGTERM PID %s? " pid)))
      (signal-process (string-to-number pid) 'term)
      (format "[qol] Sent SIGTERM to PID %s" pid))))

(defun eshell/fenv (&optional query)
  "Fuzzy-search environment variables and echo the selected one."
  (qol--completing-read "Env: " process-environment query))


;;; ============================================================
;;; History / fuzzy helpers
;;; ============================================================

(defun eshell/fh (&optional query)
  "Fuzzy-pick a history entry and insert it at the prompt for editing."
  (let* ((history (when (boundp 'eshell-history-ring)
                    (ring-elements eshell-history-ring)))
         (cmd     (qol--completing-read "History: " (delete-dups history) query)))
    (goto-char (point-max))
    (delete-region eshell-last-output-end (point-max))
    (insert cmd)))


;;; ============================================================
;;; Environment loading
;;; ============================================================

(defun eshell/envload (&optional file)
  "Load KEY=VALUE pairs from FILE (default: .env) into Emacs' environment.
Handles export prefix, inline comments, and single/double-quoted values.
Blocked: shell-special keys like BASH_ENV, PROMPT_COMMAND, IFS, etc."
  (let ((file    (or file ".env"))
        (count   0)
        (blocked '("BASH_ENV" "ENV" "SHELLOPTS" "BASHOPTS" "PROMPT_COMMAND"
                   "PS1" "PS2" "PS4" "CDPATH" "IFS")))
    (unless (file-readable-p file) (user-error "[qol] File not found: %s" file))
    (dolist (line (split-string
                   (with-temp-buffer
                     (insert-file-contents file)
                     (buffer-string))
                   "\n"))
      (setq line (string-trim
                  (replace-regexp-in-string "^export[[:space:]]+" "" line)))
      ;; Strip trailing inline comment (simple heuristic)
      (setq line (replace-regexp-in-string "[[:space:]]+#.*\\'" "" line))
      (unless (or (string-empty-p line) (string-prefix-p "#" line))
        (when (string-match "\\`\\([A-Za-z_][A-Za-z0-9_]*\\)=\\(.*\\)\\'" line)
          (let* ((key (match-string 1 line))
                 (raw (match-string 2 line))
                 (val (cond
                       ((and (string-prefix-p "\"" raw) (string-suffix-p "\"" raw))
                        (substring raw 1 (1- (length raw))))
                       ((and (string-prefix-p "'" raw) (string-suffix-p "'" raw))
                        (substring raw 1 (1- (length raw))))
                       (t raw))))
            (unless (member key blocked)
              (setenv key val)
              (cl-incf count))))))
    (format "[qol] Loaded %d variable(s) from %s" count file)))

(defun eshell/envunload (&optional file)
  "Unset all KEY=VALUE variables defined in FILE (default: .env)."
  (let ((file  (or file ".env"))
        (count 0))
    (unless (file-readable-p file) (user-error "[qol] File not found: %s" file))
    (dolist (line (split-string
                   (with-temp-buffer
                     (insert-file-contents file)
                     (buffer-string))
                   "\n"))
      (setq line (string-trim
                  (replace-regexp-in-string "^export[[:space:]]+" "" line)))
      (unless (or (string-empty-p line) (string-prefix-p "#" line))
        (when (string-match "\\`\\([A-Za-z_][A-Za-z0-9_]*\\)=" line)
          (setenv (match-string 1 line) nil)
          (cl-incf count))))
    (format "[qol] Unset %d variable(s) from %s" count file)))

(defun eshell/envshow (&optional pattern)
  "Pretty-print environment variables, optionally filtered by PATTERN (regexp)."
  (let* ((env      (sort (copy-sequence process-environment) #'string<))
         (filtered (if (and pattern (not (string-empty-p pattern)))
                       (cl-remove-if-not
                        (lambda (e) (string-match-p pattern e))
                        env)
                     env)))
    (if filtered
        (mapconcat #'identity filtered "\n")
      (format "[qol] No env vars matching: %s" pattern))))


;;; ============================================================
;;; HTTP / JSON helpers
;;; ============================================================

(defun eshell/GET (&rest args)
  "HTTP GET ARGS in a dedicated run buffer (httpie → curl → wget)."
  (cond ((qol--has "http")  (qol--run-buffer "http"  (cons "GET" args)            "*qol:run:GET*"))
        ((qol--has "curl")  (qol--run-buffer "curl"  (append '("-sSL") args)       "*qol:run:GET*"))
        ((qol--has "wget")  (qol--run-buffer "wget"  (append '("-qO-") args)       "*qol:run:GET*"))
        (t (user-error "[qol] GET requires httpie, curl, or wget"))))

(defun eshell/POST (&rest args)
  "HTTP POST ARGS in a dedicated run buffer (httpie → curl)."
  (cond ((qol--has "http")  (qol--run-buffer "http"  (cons "POST" args)            "*qol:run:POST*"))
        ((qol--has "curl")  (qol--run-buffer "curl"  (append '("-sSL" "-X" "POST") args) "*qol:run:POST*"))
        (t (user-error "[qol] POST requires httpie or curl"))))

(defun eshell/jpp (&optional file)
  "Pretty-print JSON from FILE using jq (or Emacs' json library as fallback)."
  (cond
   ((and file (qol--has "jq"))
    (qol--run-buffer "jq" (list "." file) "*qol:run:jpp*"))
   (file
    (with-current-buffer (find-file-noselect file)
      (json-pretty-print-buffer)
      (buffer-string)))
   (t (user-error "[qol] Usage: jpp <file>"))))

(defun eshell/jq (filter &optional file)
  "Run jq FILTER on FILE, or on the most recently visited JSON buffer."
  (unless (qol--has "jq") (user-error "[qol] jq not found"))
  (if file
      (qol--run-buffer "jq" (list filter file) "*qol:run:jq*" t)
    (let ((json-buf (seq-find (lambda (b)
                                (with-current-buffer b
                                  (or (derived-mode-p 'json-mode 'json-ts-mode)
                                      (string-suffix-p ".json"
                                                       (or buffer-file-name "")))))
                              (buffer-list))))
      (if json-buf
          (let ((tmp (make-temp-file "qol-jq-" nil ".json")))
            (with-current-buffer json-buf
              (write-region (point-min) (point-max) tmp))
            (qol--run-buffer "jq" (list filter tmp) "*qol:run:jq*" t))
        (user-error "[qol] Usage: jq <filter> <file>")))))

(defun eshell/jkeys (&optional file)
  "Print top-level keys of a JSON FILE via jq."
  (if (qol--has "jq")
      (qol--run "jq" "keys[]" (or file "-"))
    (user-error "[qol] jq not found")))

(defun eshell/jlen (&optional file)
  "Print the length of the root JSON value in FILE via jq."
  (if (qol--has "jq")
      (qol--run "jq" "length" (or file "-"))
    (user-error "[qol] jq not found")))


;;; ============================================================
;;; Git helpers
;;; ============================================================

(defun qol--git-root ()
  "Return the current Git repo root, or signal an error."
  (or (qol--command-output "git" "rev-parse" "--show-toplevel")
      (user-error "[qol] Not in a git repository")))

(defun qol--git-default-branch ()
  "Return the default remote branch (main, master, etc.)."
  (or (qol--command-output "git" "symbolic-ref" "--short"
                            "refs/remotes/origin/HEAD")
      "main"))

(defun eshell/gundo (&rest _args)
  "Undo the last commit (soft reset to HEAD~1)."
  (qol--run "git" "reset" "--soft" "HEAD~1"))

(defun eshell/gsave (&rest _args)
  "Stage all changes and create a timestamped WIP commit."
  (let ((msg (concat "WIP: " (format-time-string "%Y-%m-%d %H:%M"))))
    (qol--run-buffer "sh"
                     (list "-lc" (format "git add -A && git commit -m %s"
                                         (shell-quote-argument msg)))
                     "*qol:run:gsave*" t)))

(defun eshell/gwip (&rest _args)
  "Stash all changes (including untracked) with a timestamped WIP message."
  (qol--run "git" "stash" "push" "-u" "-m"
            (concat "WIP: " (format-time-string "%Y-%m-%d %H:%M"))))

(defun eshell/grestore (&rest _args)
  "Unstage all staged changes."
  (qol--run "git" "restore" "--staged" "."))

(defun eshell/gmain (&rest _args)
  "Switch to the default remote branch."
  (qol--run "git" "switch" (qol--git-default-branch)))

(defun eshell/gsync (&rest _args)
  "Fetch all remotes and rebase onto the current branch in a run buffer."
  (qol--run-buffer "sh"
                   (list "-lc" "git fetch --all --prune && git pull --rebase --autostash")
                   "*qol:run:gsync*"))

(defun eshell/gclean_merged (&rest _args)
  "Delete local branches already merged into the current branch.
Protects main, master, develop, dev, and the current branch."
  (let* ((current (qol--command-output "git" "branch" "--show-current"))
         (branches (qol--read-lines "git" "branch" "--merged"))
         (keep     (list current "main" "master" "develop" "dev"))
         (delete   (cl-remove-if
                    (lambda (b)
                      (member (string-trim
                               (replace-regexp-in-string "^\\*" "" b))
                              keep))
                    branches)))
    (if (null delete)
        "[qol] No merged branches to clean"
      (when (yes-or-no-p (format "Delete merged branches: %s? "
                                 (string-join delete ", ")))
        (dolist (b delete)
          (qol--run "git" "branch" "-d"
                    (string-trim (replace-regexp-in-string "^\\*" "" b))))
        "[qol] Cleaned merged branches"))))

(defun eshell/gbranch (&optional query)
  "Fuzzy-pick and switch to a git branch."
  (let* ((branches (qol--read-lines "git" "branch" "-a" "--format=%(refname:short)"))
         (branch   (qol--completing-read "Branch: " branches query)))
    (when (and branch (not (string-empty-p branch)))
      (qol--run "git" "switch" branch))))

(defun eshell/gpick (&rest _args)
  "Fuzzy-pick a commit from git log and cherry-pick it onto HEAD."
  (let* ((log    (qol--read-lines "git" "log" "--oneline" "--all" "--no-decorate"))
         (choice (qol--completing-read "Cherry-pick commit: " log))
         (hash   (car (split-string choice))))
    (when (and hash (not (string-empty-p hash)))
      (qol--run "git" "cherry-pick" hash))))

(defun eshell/gstash (&optional action)
  "Fuzzy-pick a stash entry to pop (default) or apply.
ACTION: \"pop\" (default) or \"apply\"."
  (let* ((stashes (qol--read-lines "git" "stash" "list"))
         (choice  (qol--completing-read "Stash: " stashes))
         (ref     (and choice (car (split-string choice ":"))))
         (action  (or action "pop")))
    (when (and ref (not (string-empty-p ref)))
      (qol--run "git" "stash" action ref))))

(defun eshell/grecent (&optional count)
  "Show recently touched branches (default: 15)."
  (qol--run "git" "for-each-ref"
            "--sort=-committerdate"
            (format "--count=%s" (or count "15"))
            "--format=%(committerdate:relative)%09%(refname:short)%09%(subject)"
            "refs/heads/"))

(defun eshell/gignored (&rest paths)
  "Show which of PATHS are ignored by .gitignore."
  (apply #'qol--run "git" "check-ignore" "-v" paths))

(defun eshell/gfixup (commit)
  "Create a fixup commit targeting COMMIT."
  (qol--run "git" "commit" "--fixup" commit))

(defun eshell/grbi (&optional base)
  "Interactive rebase onto BASE (default: detected default branch)."
  (qol--run "git" "rebase" "-i" (or base (qol--git-default-branch))))

(defun eshell/HEAD (&rest _args)
  "Print the current branch and most recent commit in one line."
  (let ((branch (qol--command-output "git" "branch" "--show-current"))
        (log    (qol--command-output "git" "log" "--oneline" "-1")))
    (cond ((and branch log)
           (format "%s  →  %s"
                   (propertize branch 'face 'magit-branch-local)
                   log))
          ((null branch) "[qol] Not in a git repository")
          (t             "[qol] No commits yet"))))

(defun eshell/gpr (&rest _args)
  "Open a PR for the current branch in the browser (requires gh)."
  (unless (qol--has "gh") (user-error "[qol] gh CLI required"))
  (qol--run-buffer "gh" '("pr" "view" "--web") "*qol:run:gpr*" t))


;;; ============================================================
;;; GitHub CLI helpers
;;; ============================================================

(defun eshell/ghopen (&rest args)
  "Open the current repo (or a path within it) in the browser via gh."
  (apply #'qol--run "gh" "repo" "view" "--web" args))

(defun eshell/ghmine (&rest _args)
  "List GitHub issues assigned to me and PRs authored by me."
  (qol--sh "gh issue list --assignee @me ; gh pr list --author @me"))


;;; ============================================================
;;; Docker / Podman / Kubernetes
;;; ============================================================

(defun qol--logs-buffer (runtime container)
  "Tail logs for CONTAINER from RUNTIME in a dedicated run buffer."
  (qol--run-buffer runtime
                   (list "logs" "-f" "--tail=100" container)
                   (format "*qol:%s-logs:%s*" runtime container)
                   t))

;; Docker
(defun eshell/dkc (&rest args)
  "Run docker compose (or docker-compose) ARGS in a run buffer."
  (if (zerop (process-file "docker" nil nil nil "compose" "version"))
      (apply #'qol--run "docker" "compose" args)
    (apply #'qol--run "docker-compose" args)))

(defun eshell/dksh (&optional container)
  "Open an interactive shell inside a running Docker container.
Picks bash if available, otherwise sh."
  (let* ((container (or container
                         (qol--completing-read
                          "Docker container: "
                          (qol--read-lines "docker" "ps" "--format" "{{.Names}}"))))
         (shell     (if (= 0 (call-process "docker" nil nil nil
                                            "exec" container "command" "-v" "bash"))
                        "bash" "sh")))
    (qol--terminal-buffer
     (format "docker:%s" container)
     (mapconcat #'shell-quote-argument
                (list "docker" "exec" "-it" container shell) " "))))

(defun eshell/dkstop (&optional container)
  "Stop a running Docker container (with completion if omitted)."
  (let ((c (or container
               (qol--completing-read
                "Stop container: "
                (qol--read-lines "docker" "ps" "--format" "{{.Names}}")))))
    (qol--run "docker" "stop" c)))

(defun eshell/dklogs (&optional container)
  "Tail logs for a Docker container in a dedicated buffer."
  (qol--logs-buffer
   "docker"
   (or container
       (qol--completing-read
        "Docker logs for container: "
        (qol--read-lines "docker" "ps" "--format" "{{.Names}}")))))

(defun eshell/dkclean (&rest _args)
  "Prune stopped Docker containers, dangling images, and unused networks."
  (qol--run "docker" "system" "prune" "-f"))

(defun eshell/dkclean_all (&rest _args)
  "Prune ALL unused Docker resources including volumes (asks for confirmation)."
  (when (yes-or-no-p "Prune all unused Docker resources, including volumes? ")
    (qol--run "docker" "system" "prune" "-af" "--volumes")))

;; Podman
(defun eshell/pmc (&rest args)
  "Run podman compose (or podman-compose) ARGS in a run buffer."
  (if (zerop (process-file "podman" nil nil nil "compose" "version"))
      (apply #'qol--run "podman" "compose" args)
    (apply #'qol--run "podman-compose" args)))

(defun eshell/pmsh (&optional container)
  "Open an interactive shell inside a running Podman container."
  (let* ((container (or container
                         (qol--completing-read
                          "Podman container: "
                          (qol--read-lines "podman" "ps" "--format" "{{.Names}}"))))
         (shell     (if (= 0 (call-process "podman" nil nil nil
                                            "exec" container "which" "bash"))
                        "bash" "sh")))
    (qol--terminal-buffer
     (format "podman:%s" container)
     (mapconcat #'shell-quote-argument
                (list "podman" "exec" "-it" container shell) " "))))

(defun eshell/pmstop (&optional container)
  "Stop a running Podman container (with completion if omitted)."
  (let ((c (or container
               (qol--completing-read
                "Stop container: "
                (qol--read-lines "podman" "ps" "--format" "{{.Names}}")))))
    (qol--run "podman" "stop" c)))

(defun eshell/pmlogs (&optional container)
  "Tail logs for a Podman container in a dedicated buffer."
  (qol--logs-buffer
   "podman"
   (or container
       (qol--completing-read
        "Podman logs for container: "
        (qol--read-lines "podman" "ps" "--format" "{{.Names}}")))))

(defun eshell/pmclean (&rest _args)
  "Prune stopped Podman containers and dangling images."
  (qol--run "podman" "system" "prune" "-f"))

(defun eshell/pmclean_all (&rest _args)
  "Prune ALL unused Podman resources including volumes (asks for confirmation)."
  (when (yes-or-no-p "Prune all unused Podman resources, including volumes? ")
    (qol--run "podman" "system" "prune" "-af" "--volumes")))

(defun eshell/pmip (container)
  "Print the IP address of a running Podman CONTAINER."
  (qol--run "podman" "inspect" "-f" "{{.NetworkSettings.IPAddress}}" container))

;; Kubernetes
(defun eshell/kpf (&optional local-port remote-port)
  "kubectl port-forward: pick a pod via completion, then forward ports."
  (unless (qol--has "kubectl") (user-error "[qol] kubectl required"))
  (let* ((pods   (qol--read-lines "kubectl" "get" "pods" "--no-headers"
                                  "-o" "custom-columns=NAME:.metadata.name"))
         (pod    (qol--completing-read "Pod: " pods))
         (rport  (format "%s" (or remote-port (read-string "Remote port: " "8080"))))
         (lport  (format "%s" (or local-port rport))))
    (qol--run-buffer "kubectl"
                     (list "port-forward" pod (format "%s:%s" lport rport))
                     (format "*qol:run:kpf:%s*" pod) t)))

(defun eshell/kubens (&optional namespace)
  "Switch the current Kubernetes namespace via completion."
  (let ((ns (or namespace
                (qol--completing-read
                 "Namespace: "
                 (split-string (or (qol--command-output
                                    "sh" "-c"
                                    "kubectl get namespaces -o jsonpath='{.items[*].metadata.name}'")
                                   "")
                               " " t)))))
    (qol--run "kubectl" "config" "set-context" "--current"
              (concat "--namespace=" ns))))

(defun eshell/kubectx (&optional context)
  "Switch the current Kubernetes context via completion."
  (let ((ctx (or context
                 (qol--completing-read
                  "Context: "
                  (qol--read-lines "kubectl" "config" "get-contexts" "-o" "name")))))
    (qol--run "kubectl" "config" "use-context" ctx)))


;;; ============================================================
;;; Miscellaneous utilities
;;; ============================================================

(defun eshell/wh (&rest names)
  "Show where each NAME resolves: alias, eshell function, Emacs fn, or executable."
  (unless names (user-error "Usage: wh <name> [name2 ...]"))
  (mapconcat
   (lambda (name)
     (cond
      ((eshell-lookup-alias name)
       (format "%s -> alias: %s" name (cadr (eshell-lookup-alias name))))
      ((fboundp (intern (concat "eshell/" name)))
       (format "%s -> eshell built-in function" name))
      ((fboundp (intern name))
       (format "%s -> Emacs function: %s" name (intern name)))
      ((executable-find name)
       (format "%s -> %s" name (executable-find name)))
      (t (format "%s -> not found" name))))
   names "\n"))

(defun eshell/open (&rest paths)
  "Open each PATH with the system default application (xdg-open or open)."
  (unless paths (user-error "Usage: open <path-or-url> [...]"))
  (let ((cmd (cond ((qol--has "xdg-open") "xdg-open")
                   ((qol--has "open")     "open")
                   (t (user-error "[qol] Need xdg-open or open")))))
    (dolist (p paths)
      (start-process (format "qol:open:%s" p) nil cmd p))
    (format "[qol] Opened %d item(s)" (length paths))))

(defun eshell/please (&rest _args)
  "Re-run the last Eshell command prefixed with sudo."
  (let ((cmd (cl-find-if
              (lambda (entry)
                (and (stringp entry)
                     (not (string-empty-p entry))
                     (not (string-match-p "\\`please\\(?: .+\\)?\\'" entry))))
              (ring-elements eshell-history-ring)))
        (buf (current-buffer)))
    (unless cmd (user-error "[qol] No previous command in history"))
    (run-at-time
     0 nil
     (lambda (buffer command)
       (when (buffer-live-p buffer)
         (with-current-buffer buffer
           (goto-char (point-max))
           (insert (concat "sudo " command))
           (eshell-send-input))))
     buf cmd)
    ""))

(defvar qol-notes-file (expand-file-name "~/notes.org")
  "Default file for `eshell/note' quick-capture.")

(defun eshell/note (&rest words)
  "Append a timestamped note to `qol-notes-file'.
Called with no args, opens the notes file instead."
  (if (null words)
      (find-file qol-notes-file)
    (let ((text (string-join words " "))
          (file (or (getenv "QOL_NOTES_FILE") qol-notes-file)))
      (write-region
       (format "* [%s] %s\n" (format-time-string "%Y-%m-%d %H:%M") text)
       nil file 'append)
      (format "[qol] Noted → %s" file))))

(defvar qol--timers (make-hash-table :test 'equal)
  "Hash table of named stopwatch start times.")

(defun eshell/timer (&optional name action)
  "Named stopwatch.

  timer            – list all running timers
  timer NAME       – start or show elapsed time for NAME
  timer NAME stop  – stop and report NAME"
  (cond
   ((null name)
    (if (hash-table-empty-p qol--timers)
        "[qol] No active timers"
      (let (rows)
        (maphash (lambda (k v)
                   (push (format "  %-20s %.1fs elapsed"
                                 k (float-time (time-subtract (current-time) v)))
                         rows))
                 qol--timers)
        (concat "[qol] Timers:\n"
                (string-join (sort rows #'string<) "\n")))))
   ((equal action "stop")
    (if-let ((start (gethash name qol--timers)))
        (let ((elapsed (float-time (time-subtract (current-time) start))))
          (remhash name qol--timers)
          (format "[qol] Timer %s: %.3f seconds" name elapsed))
      (format "[qol] No timer named: %s" name)))
   (t
    (if-let ((start (gethash name qol--timers)))
        (format "[qol] Timer %s: %.1fs elapsed (still running)" name
                (float-time (time-subtract (current-time) start)))
      (puthash name (current-time) qol--timers)
      (format "[qol] Timer %s started" name)))))

(defun eshell/reload (&rest _args)
  "Reload the qol eshell config without restarting Emacs."
  (load (expand-file-name "modules/term/eshell/config.el" doom-emacs-dir) nil t)
  "[qol] Config reloaded")

(defun eshell/qol (&rest _args)
  "Show a dashboard of active qol features and their backends."
  (let (rows)
    (maphash (lambda (k v) (push (cons k v) rows)) qol--features)
    (setq rows (sort rows (lambda (a b) (string< (car a) (car b)))))
    (concat
     (propertize "[qol] Active features\n" 'face 'bold)
     (mapconcat (lambda (r) (format "  %-12s %s" (car r) (cdr r))) rows "\n"))))


;;; ============================================================
;;; Smart alias setup
;;; (runs at load time; defines aliases based on what's installed)
;;; ============================================================

(defun qol--eshell-alias (name body)
  "Define Eshell alias NAME with BODY string."
  (require 'em-alias)
  (eshell/alias name body))

;; ls / listing — prefer eza > exa > built-in ls
(cond
 ((qol--has "eza")
  (qol--feature "ls" "eza")
  (qol--eshell-alias "ls" "eza --group-directories-first $*")
  (qol--eshell-alias "l"  "eza -lh --group-directories-first $*")
  (qol--eshell-alias "ll" "eza -lah --group-directories-first --git $*")
  (qol--eshell-alias "lt" "eza --tree --level=2 --group-directories-first $*"))
 ((qol--has "exa")
  (qol--feature "ls" "exa")
  (qol--eshell-alias "ls" "exa --group-directories-first $*")
  (qol--eshell-alias "l"  "exa -lh --group-directories-first $*")
  (qol--eshell-alias "ll" "exa -lah --group-directories-first --git $*")
  (qol--eshell-alias "lt" "exa --tree --level=2 $*"))
 (t
  (qol--feature "ls" "eshell/ls")
  (qol--eshell-alias "l"  "ls -lh $*")
  (qol--eshell-alias "ll" "ls -lAh $*")))

;; cat — prefer bat > batcat > built-in
(cond
 ((qol--has "bat")
  (qol--feature "cat" "bat")
  (qol--eshell-alias "cat"  "bat --paging=never $*")
  (qol--eshell-alias "batp" "bat --paging=always $*"))
 ((qol--has "batcat")
  (qol--feature "cat" "batcat")
  (qol--eshell-alias "cat"  "batcat --paging=never $*")
  (qol--eshell-alias "batp" "batcat --paging=always $*"))
 (t (qol--warn-once "bat" "Install bat for syntax-highlighted file viewing.")))

;; grep — prefer ripgrep
(if (qol--has "rg")
    (progn
      (qol--feature "grep" "ripgrep")
      (qol--eshell-alias "grep"  "rg --color=auto $*")
      (qol--eshell-alias "rgp"   "rg --color=auto $*")
      (qol--eshell-alias "rgrep" "rg $*"))
  (qol--feature "grep" "grep")
  (qol--eshell-alias "grep" "grep --color=auto $*")
  (qol--warn-once "rg" "Install ripgrep for faster search."))

;; diff — prefer delta > colordiff
(cond
 ((qol--has "delta")     (qol--feature "diff" "delta")     (qol--eshell-alias "diff" "delta $*"))
 ((qol--has "colordiff") (qol--feature "diff" "colordiff") (qol--eshell-alias "diff" "colordiff $*"))
 (t                       (qol--feature "diff" "diff")))

;; find — prefer fd
(if (qol--has "fd")
    (progn
      (qol--feature "find" "fd")
      (qol--eshell-alias "ff"   "fd $*")
      (qol--eshell-alias "find" "fd $*"))
  (qol--feature "find" "find")
  (qol--warn-once "fd" "Install fd for friendlier find."))

;; Safe destructive-operation aliases
(qol--eshell-alias "rm"    "rm -i $*")
(qol--eshell-alias "cp"    "cp -i $*")
(qol--eshell-alias "mv"    "mv -i $*")
(qol--eshell-alias "ln"    "ln -i $*")
(qol--eshell-alias "mkdir" "mkdir -pv $*")
(qol--eshell-alias "wget"  "wget -c $*")

;; Navigation shorthands
(qol--eshell-alias ".."   "cd ..")
(qol--eshell-alias "..."  "cd ../..")
(qol--eshell-alias "...." "cd ../../..")
(qol--eshell-alias "-"    "cd -")
(qol--eshell-alias "~"    "cd ~")

;; Common one-letter shorthands
(qol--eshell-alias "c" "clear")
(qol--eshell-alias "h" "history")
(qol--eshell-alias "j" "jobs")

;; System info — always prefer human-readable
(qol--eshell-alias "df"   "df -h $*")
(qol--eshell-alias "du"   "du -h $*")
(qol--eshell-alias "free" "free -h $*")

;; Git short-form aliases (only when git is present)
(when (qol--has "git")
  (qol--feature "git" "enabled")
  (dolist (a '(("gs"   . "git status -sb $*")
               ("ga"   . "git add $*")
               ("gaa"  . "git add -A $*")
               ("gc"   . "git commit $*")
               ("gcm"  . "git commit -m $*")
               ("gca"  . "git commit --amend $*")
               ("gco"  . "git checkout $*")
               ("gcob" . "git checkout -b $*")
               ("gd"   . "git diff $*")
               ("gds"  . "git diff --staged $*")
               ("gf"   . "git fetch --all --prune $*")
               ("gp"   . "git push $*")
               ("gpf"  . "git push --force-with-lease $*")
               ("gl"   . "git pull --rebase $*")
               ("gb"   . "git branch $*")
               ("gba"  . "git branch -a $*")
               ("gsw"  . "git switch $*")
               ("gswc" . "git switch -c $*")
               ("gst"  . "git stash $*")
               ("gstp" . "git stash pop $*")
               ("glog" . "git log --oneline --graph --decorate --all $*")))
    (qol--eshell-alias (car a) (cdr a))))

;; GitHub CLI
(when (qol--has "gh")
  (qol--feature "gh" "enabled")
  (qol--eshell-alias "ghpr"  "gh pr status $*")
  (qol--eshell-alias "ghprs" "gh pr list $*")
  (qol--eshell-alias "ghci"  "gh run list --limit 10 $*"))

;; Docker
(when (qol--has "docker")
  (qol--feature "docker" "enabled")
  (qol--eshell-alias "dk"    "docker $*")
  (qol--eshell-alias "dkps"  "docker ps --format 'table {{.Names}}\\t{{.Status}}\\t{{.Ports}}' $*")
  (qol--eshell-alias "dkpsa" "docker ps -a --format 'table {{.Names}}\\t{{.Status}}\\t{{.Ports}}' $*")
  (qol--eshell-alias "dki"   "docker images --format 'table {{.Repository}}\\t{{.Tag}}\\t{{.Size}}' $*"))

;; Podman
(when (qol--has "podman")
  (qol--feature "podman" "enabled")
  (qol--eshell-alias "pm"    "podman $*")
  (qol--eshell-alias "pmps"  "podman ps --format 'table {{.Names}}\\t{{.Status}}\\t{{.Ports}}' $*")
  (qol--eshell-alias "pmpsa" "podman ps -a --format 'table {{.Names}}\\t{{.Status}}\\t{{.Ports}}' $*")
  (qol--eshell-alias "pmi"   "podman images --format 'table {{.Repository}}\\t{{.Tag}}\\t{{.Size}}' $*")
  (qol--eshell-alias "pmv"   "podman volume ls $*")
  (qol--eshell-alias "pmn"   "podman network ls $*"))

;; kubectl
(when (qol--has "kubectl")
  (qol--feature "k8s" "enabled")
  (qol--eshell-alias "k"    "kubectl $*")
  (qol--eshell-alias "kgp"  "kubectl get pods $*")
  (qol--eshell-alias "kgpa" "kubectl get pods -A $*")
  (qol--eshell-alias "kgs"  "kubectl get svc $*")
  (qol--eshell-alias "kgn"  "kubectl get nodes $*")
  (qol--eshell-alias "kd"   "kubectl describe $*")
  (qol--eshell-alias "kl"   "kubectl logs -f $*")
  (qol--eshell-alias "ke"   "kubectl exec -it $*")
  (qol--eshell-alias "kns"  "kubectl config set-context --current --namespace $*"))

(qol--feature "fuzzy" "consult/vertico")
(when (qol--has "zoxide") (qol--feature "zoxide" "enabled"))
