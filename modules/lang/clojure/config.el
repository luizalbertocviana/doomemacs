;;; lang/clojure/config.el -*- lexical-binding: t; -*-

(after! projectile
  (pushnew! projectile-project-root-files "project.clj" "build.boot" "deps.edn"))

;; Large clojure buffers tend to be slower than large buffers of other modes, so
;; it should have a lower threshold too.
(add-to-list 'doom-large-file-size-alist '("\\.\\(?:clj[sc]?\\|dtm\\|edn\\)\\'" . 0.5))

(defvar +clojure-load-clj-refactor-with-lsp nil
  "Whether or not to include clj-refactor along with clojure-lsp.")


;;
;;; Packages

(use-package! clojure-mode
  :defer t
  :config
  (set-formatter! 'cljfmt '("cljfmt" "fix" "-") :modes '(clojure-mode clojurec-mode clojurescript-mode))

  (when (modulep! +lsp)
    (add-hook! '(clojure-mode-local-vars-hook
                 clojurec-mode-local-vars-hook
                 clojurescript-mode-local-vars-hook)
               :append
               (defun +clojure-disable-lsp-indentation-h ()
                 (setq-local lsp-enable-indentation nil))
               #'lsp!)
    (after! lsp-clojure
      (dolist (m '(clojure-mode
                   clojurec-mode
                   clojurescript-mode
                   clojurex-mode))
        (add-to-list 'lsp-language-id-configuration (cons m "clojure")))))

  (when (modulep! +tree-sitter)
    (add-hook! '(clojure-mode-local-vars-hook
                 clojurec-mode-local-vars-hook
                 clojurescript-mode-local-vars-hook)
               :append
               #'tree-sitter!)
    ;; TODO: PR this upstream
    (after! tree-sitter-langs
      (add-to-list 'tree-sitter-major-mode-language-alist '(clojurec-mode . clojure))
      (add-to-list 'tree-sitter-major-mode-language-alist '(clojurescript-mode . clojure)))))


;; `cider-mode' is used instead of the typical `cider' package due to the main
;; library being loaded only when is absolutely needed, which is too late for
;; reconfiguration in many cases.
(use-package! cider-mode
  ;; NOTE if `org-directory' doesn't exist, `cider-jack' in won't work
  :hook (clojure-mode-local-vars . cider-mode)
  :init
  (after! clojure-mode
    (set-repl-handler! '(clojure-mode clojurec-mode) #'+clojure/open-repl :persist t)
    (set-repl-handler! 'clojurescript-mode #'+clojure/open-cljs-repl :persist t)
    (set-eval-handler! '(clojure-mode clojurescript-mode clojurec-mode) #'cider-eval-region))

  ;; HACK Fix radian-software/radian#446: CIDER tries to calculate the frame's
  ;;   background too early; sometimes before the initial frame has been
  ;;   initialized, causing errors.
  (defvar cider-docview-code-background-color nil)
  (defvar cider-stacktrace-frames-background-color nil)
  (add-transient-hook! #'cider-docview-fontify-code-blocks (cider--docview-adapt-to-theme))
  (add-transient-hook! #'cider-stacktrace-render-cause     (cider--stacktrace-adapt-to-theme))
  :config
  (add-hook 'cider-mode-hook #'eldoc-mode)
  (unless (modulep! +lsp)
    (set-lookup-handlers! '(cider-mode cider-repl-mode)
      :definition #'+clojure-cider-lookup-definition
      :documentation #'cider-doc))
  (set-popup-rules!
    '(("^\\*cider-error*" :ignore t)
      ("^\\*cider-repl" :quit nil :ttl nil)
      ("^\\*cider-repl-history" :vslot 2 :ttl nil)))

  (setq nrepl-hide-special-buffers t
        nrepl-log-messages nil
        cider-font-lock-dynamically '(macro core function var deprecated)
        cider-overlays-use-font-lock t
        cider-print-options '(("length" 100))
        cider-prompt-for-symbol nil
        cider-repl-history-display-duplicates nil
        cider-repl-history-display-style 'one-line
        cider-repl-history-file (concat doom-cache-dir "cider-repl-history")
        cider-repl-history-highlight-current-entry t
        cider-repl-history-quit-action 'delete-and-restore
        cider-repl-history-highlight-inserted-item t
        cider-repl-history-size 1000
        cider-repl-result-prefix ";; => "
        cider-repl-use-clojure-font-lock t
        cider-repl-use-pretty-printing t
        cider-repl-wrap-history nil
        cider-stacktrace-default-filters '(tooling dup)

        ;; Don't focus the CIDER REPL when it starts. Since it can take so long
        ;; to start up, you either wait for a minute doing nothing or be
        ;; prepared for your cursor to suddenly change buffers without warning.
        ;; See https://github.com/clojure-emacs/cider/issues/1872
        cider-repl-pop-to-buffer-on-connect 'display-only)

  (when (modulep! +lsp)
    (setq cider-eldoc-display-for-symbol-at-point nil
          cider-font-lock-dynamically nil)
    (add-hook! 'cider-mode-hook
      (defun +clojure--cider-disable-completion ()
        "Use lsp completion instead of cider."
        (remove-hook 'completion-at-point-functions #'cider-complete-at-point t))))

  ;; UX: CIDER's error messages get quietly funneled into *nrepl-server*. That
  ;; sort of information would be more helpful displayed front and center when
  ;; opening a *cider-repl*.
  (add-hook! 'cider-connected-hook
    (defun +clojure--cider-dump-nrepl-server-log-h ()
      "Copy contents of *nrepl-server* to beginning of *cider-repl*."
      (when (buffer-live-p nrepl-server-buffer)
        (save-excursion
          (goto-char (point-min))
          (insert
           (with-current-buffer nrepl-server-buffer
             (buffer-string)))))))

  (after! evil
    (if (modulep! :editor evil +everywhere)
        ;; Match evil-collection keybindings to debugging overlay
        (after! cider-debug
          (mapc
           (lambda (replacement)
             (let* ((from (car replacement))
                    (to (cadr replacement))
                    (item (assoc from cider-debug-prompt-commands)))
               (when item
                 ;; Position matters, hence the update-in-place
                 (setf (car item) (car to))
                 (setf (cdr item) (cdr to)))))
           '((?h (?H "here" "Here"))
             (?i (?I "in" "In"))
             (?j (?J "inject" "inJect"))
             (?l (?L "locals" "Locals"))))

          ;; Prevent evil-snipe from overriding evil-collection
          (add-hook! 'cider--debug-mode-hook
                     #'turn-off-evil-snipe-mode
                     #'turn-off-evil-snipe-override-mode))

      ;; When in cider-debug-mode, override evil keys to not interfere with debug keys
      (add-hook! 'cider--debug-mode-hook
        (defun +clojure--cider-setup-debug ()
          "Setup cider debug to override evil keys cleanly"
          (evil-make-overriding-map cider--debug-mode-map 'normal)
          (evil-normalize-keymaps)))))

  (when (modulep! :ui modeline +light)
    (defvar-local cider-modeline-icon nil)

    (defun +clojure--cider-set-modeline (face label)
      "Update repl icon on modeline with cider information."
      (setq cider-modeline-icon (concat
                                 " "
                                 (+modeline-format-icon 'faicon "nf-fa-terminal" "" face label -0.0575)
                                 " "))
      (add-to-list 'global-mode-string
                   '(t (:eval cider-modeline-icon))
                   'append))

    (add-hook! '(cider-connected-hook
                 cider-disconnected-hook
                 cider-mode-hook)
      (defun +clojure--cider-connected-update-modeline ()
        "Update modeline with cider connection state."
        (let* ((connected (cider-connected-p))
               (face (if connected 'warning 'shadow))
               (label (if connected "Cider connected" "Cider disconnected")))
          (+clojure--cider-set-modeline face label))))

    (add-hook! 'cider-before-eval-hook
      (defun +clojure--cider-before-eval-hook-update-modeline ()
        "Update modeline with cider state before eval."
        (+clojure--cider-set-modeline 'warning "Cider evaluating")))

    (add-hook! 'cider-after-eval-done-hook
      (defun +clojure--cider-after-eval-done-hook-update-modeline ()
        "Update modeline with cider state after eval."
        (+clojure--cider-set-modeline 'success "Cider syncronized")))

    (add-hook! 'cider-file-loaded-hook
      (defun +clojure--cider-file-loaded-update-modeline ()
        "Update modeline with cider file loaded state."
        (+clojure--cider-set-modeline 'success "Cider syncronized"))))

  ;; Ensure that CIDER is used for sessions in org buffers.
  (when (modulep! :lang org)
    (after! ob-clojure
      (setq! org-babel-clojure-backend 'cider)))

  ;; The CIDER welcome message obscures error messages that the above code is
  ;; supposed to be make visible.
  (setq cider-repl-display-help-banner nil)

  (map! (:localleader
          (:map (cider-inspector-mode-map)
            "d" #'cider-inspector-def-current-val)
          (:map (clojure-mode-map clojurescript-mode-map clojurec-mode-map)
            "'"  #'cider-jack-in-clj
            "\"" #'cider-jack-in-cljs
            "c"  #'cider-connect-clj
            "C"  #'cider-connect-cljs
            "m"  #'cider-macroexpand-1
            "M"  #'cider-macroexpand-all
            (:prefix ("d" . "debug")
             "d" #'cider-debug-defun-at-point)
            (:prefix ("e" . "eval")
              "b" #'cider-eval-buffer
              "d" #'cider-eval-defun-at-point
              "D" #'cider-insert-defun-in-repl
              "e" #'cider-eval-last-sexp
              "E" #'cider-insert-last-sexp-in-repl
              "r" #'cider-eval-region
              "R" #'cider-insert-region-in-repl
              "u" #'cider-undef)
            (:prefix ("g" . "goto")
              "b" #'cider-pop-back
              "g" #'cider-find-var
              "n" #'cider-find-ns)
            (:prefix ("h" . "help")
              "n" #'cider-find-ns
              "a" #'cider-apropos
              "c" #'cider-clojuredocs
              "d" #'cider-doc
              "j" #'cider-javadoc
              "w" #'cider-clojuredocs-web)
            (:prefix ("i" . "inspect")
              "e" #'cider-enlighten-mode
              "i" #'cider-inspect
              "r" #'cider-inspect-last-result)
            (:prefix ("n" . "namespace")
              "n" #'cider-browse-ns
              "N" #'cider-browse-ns-all
              "r" #'cider-ns-refresh)
            (:prefix ("p" . "print")
              "p" #'cider-pprint-eval-last-sexp
              "P" #'cider-pprint-eval-last-sexp-to-comment
              "d" #'cider-pprint-eval-defun-at-point
              "D" #'cider-pprint-eval-defun-to-comment
              "r" #'cider-pprint-eval-last-sexp-to-repl)
            (:prefix ("r" . "repl")
              "n" #'cider-repl-set-ns
              "q" #'cider-quit
              "r" #'cider-ns-refresh
              "R" #'cider-restart
              "b" #'cider-switch-to-repl-buffer
              "B" #'+clojure/cider-switch-to-repl-buffer-and-switch-ns
              "c" #'cider-find-and-clear-repl-output
              "l" #'cider-load-buffer
              "L" #'cider-load-buffer-and-switch-to-repl-buffer)
            (:prefix ("t" . "test")
              "a" #'cider-test-rerun-test
              "l" #'cider-test-run-loaded-tests
              "n" #'cider-test-run-ns-tests
              "p" #'cider-test-run-project-tests
              "r" #'cider-test-rerun-failed-tests
              "s" #'cider-test-run-ns-tests-with-filters
              "t" #'cider-test-run-test)))

        (:when (modulep! :editor evil +everywhere)
          :map cider-repl-mode-map
          :i [S-return] #'cider-repl-newline-and-indent
          :i [M-return] #'cider-repl-return
          (:localleader
            "n" #'cider-repl-set-ns
            "q" #'cider-quit
            "r" #'cider-ns-refresh
            "R" #'cider-restart
            "c" #'cider-repl-clear-buffer)
          :map cider-repl-history-mode-map
          :i [return]  #'cider-repl-history-insert-and-quit
          :i "q"  #'cider-repl-history-quit
          :i "l"  #'cider-repl-history-occur
          :i "s"  #'cider-repl-history-search-forward
          :i "r"  #'cider-repl-history-search-backward
          :i "U"  #'cider-repl-history-undo-other-window)))


(use-package! clj-refactor
  :when (or (modulep! -lsp)
            +clojure-load-clj-refactor-with-lsp)
  :hook (clojure-mode . clj-refactor-mode)
  :config
  (set-lookup-handlers! 'clj-refactor-mode
    :references #'cljr-find-usages)
  (map! :map clojure-mode-map
        :localleader
        :desc "refactor" "R" #'hydra-cljr-help-menu/body))


;; clojure-lsp already uses clj-kondo under the hood
(use-package! flycheck-clj-kondo
  :when (modulep! -lsp)
  :when (modulep! :checkers syntax -flymake)
  :after flycheck)


(use-package! neil
  :commands (neil-find-clojure-package)
  :config
  (setq neil-prompt-for-version-p nil
        neil-inject-dep-to-project-p t)
  (map! :map (clojure-mode-map clojurescript-mode-map clojurec-mode-map)
        :localleader
        "f"  #'neil-find-clojure-package))


(use-package! jet
  :commands (jet)
  :config
  (map! :map (clojure-mode-map clojurescript-mode-map clojurec-mode-map)
        :localleader
        "j" #'jet))
