(ns simple-git.core
  (:require [simple-git.cmds :as cmds]
            [promesa.core :as p]
            ["diff2html" :as diff]
            ["atom" :refer [CompositeDisposable TextEditor]]))

(def subscriptions (atom (CompositeDisposable.)))

(defonce atom-state (atom nil))

(defn generate-view [placeholder p]
  (let [editor (TextEditor. #js {:mini true :placeholderText placeholder})
        editor-view (.. js/atom -views (getView editor))
        div (js/document.createElement "div")
        panel (.. js/atom -workspace (addModalPanel #js {:item div}))
        style (.. js/atom -views (getView panel) -style)
        destroy-and-focus (fn []
                            (.destroy panel)
                            (.. js/atom -views (getView (.-workspace js/atom)) focus))]

    (.append div editor-view)
    (doto (.-commands js/atom)
          (.add (.-element editor) "core:confirm" (fn []
                                                    (p/resolve! p (.getText editor))
                                                    (destroy-and-focus)))
          (.add (.-element editor) "core:cancel" (fn []
                                                   (p/resolve! p nil)
                                                   (destroy-and-focus))))
    (p/do!
     (p/delay 10)
     (.focus editor-view))
    div))

(defn prompt! [placeholder]
  (let [p (p/deferred)]
    (generate-view placeholder p)
    p))

(defn- diff->html [diff-str]
  (let [parsed (.parse diff diff-str)]
    (.html diff parsed #js {:drawFileList true})))

(defn diff-prompt! [placeholder diff-str]
  (let [p (p/deferred)
        html (generate-view placeholder p)
        diff-elem (js/document.createElement "div")
        style (.-style diff-elem)]
    (.setProperty style "height" "100%")
    (.setProperty style "overflow" "scroll")
    (aset diff-elem "innerHTML" (diff->html diff-str))
    (.. diff-elem -classList (add "native-key-bindings"))
    (.append html diff-elem)
    p))

(defn- simplify [string]
  (let [size (count string)]
    (if (> size 30)
      (str "..." (subs string (- size 30)))
      string)))

(defn- refresh-repos! []
  (doseq [^js repo (.. js/atom -project getRepositories)
          :when repo]
    (doto repo
          .refreshIndex
          .refreshStatus)))

(defn- quick-commit! []
  (p/let [file (cmds/current-file!)
          {:keys [output]} (cmds/run-git "diff" "HEAD" file)]
    (if (empty? output)
      (cmds/info! "No changes" "No changes in the current file - refusing to commit")
      (p/let [commit-msg (diff-prompt! (str "Commit message for " (simplify file)) output)]
        (if commit-msg
          (do
            (cmds/run-git-treating-errors "commit" file "-m" commit-msg)
            (refresh-repos!))
          (cmds/info! "Not commiting" "Can't commit with an empty message"))))))

(defn- commit! []
  (p/let [{:keys [output]} (cmds/run-git "diff" "--staged")]
    (if (empty? output)
      (cmds/info! "No changes" "No changes staged to commit - try to add files first")
      (p/let [commit-msg (diff-prompt! "Commit message" output)]
        (if commit-msg
          (do
            (cmds/run-git-treating-errors "commit" "-m" commit-msg)
            (refresh-repos!))
          (cmds/info! "Not commiting" "Can't commit with an empty message"))))))

(defn- add-cmd! [command fun]
  (.add @subscriptions
        (.. js/atom -commands (add "atom-text-editor" (str "git:" command) fun))))

(defn activate [state]
  (reset! atom-state state)

  (.add @subscriptions (.. js/atom -commands
                           (add "atom-text-editor"
                                "git:add-current-file"
                                #(cmds/run-git-treating-errors "add" (cmds/current-file!)))))
  (add-cmd! "quick-commit-current-file" quick-commit!)
  (add-cmd! "commit" commit!))


(defn deactivate [state]
  (.dispose ^js @subscriptions))

(defn ^:dev/before-load reset-subs []
  (deactivate @atom-state))

(defn ^:dev/after-load re-activate []
  (reset! subscriptions (CompositeDisposable.))
  (activate @atom-state)
  (cmds/info! "Reloaded plug-in" ""))
