(ns simple-git.core
  (:require [simple-git.cmds :as cmds]
            [clojure.string :as str]
            [promesa.core :as p]
            ["diff2html/lib/ui/js/diff2html-ui.js" :refer [Diff2HtmlUI]]
            ["atom" :refer [CompositeDisposable TextEditor]]
            ["path" :refer [dirname]]))

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

    (.setProperty style "max-height" "90%")
    (.setProperty style "display" "flex")
    (.setProperty style "flex-direction" "column")
    (.. div -style (setProperty "overflow" "scroll"))
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

(def ^:private translate-langs
  {"cljs" "clj"
   "cljc" "clj"
   "cljx" "clj"})

(defn- append-diff! [diff-str elem]
  (let [diff (new Diff2HtmlUI elem diff-str #js {:highlight true})]
    (.draw diff)
    (doseq [n (. elem querySelectorAll "*[data-lang]")
            :let [lang (translate-langs (.. n -dataset -lang))]
            :when lang]
      (set! (.. n -dataset -lang) lang))
   (.highlightCode diff)))

(defn diff-prompt! [placeholder diff-str]
  (let [p (p/deferred)
        html (generate-view placeholder p)
        diff-elem (doto (js/document.createElement "div")
                        (.. -classList (add "simple-git")))
        style (.-style diff-elem)
        outer-div (js/document.createElement "div")]

    (append-diff! diff-str diff-elem)
    (.. diff-elem -classList (add "native-key-bindings"))
    (.append outer-div diff-elem)
    (.append html outer-div)
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
        (when commit-msg
          (cmds/run-git-treating-errors "commit" file "-m" commit-msg)
          (refresh-repos!))))))

(defn- commit! []
  (p/let [{:keys [output]} (cmds/run-git "diff" "--staged")]
    (if (empty? output)
      (cmds/info! "No changes" "No changes staged to commit - try to add files first")
      (p/let [commit-msg (diff-prompt! "Commit message" output)]
        (when commit-msg
          (cmds/run-git-treating-errors "commit" "-m" commit-msg)
          (refresh-repos!))))))

(defn- protect-commit! [fun]
  (if (.. js/atom -config (get "simple-git.denyCommit"))
    (p/let [current-branch (cmds/current-branch)
            default (cmds/default-branch)]
      (if (= current-branch default)
        (cmds/error! "Can't commit" (str "Can't commit to " default
                                         ". Please, create a branch and commit from there"))
        (fun)))
    (fun)))

(defn- push-branch! [current]
  (p/do!
   (cmds/run-git-treating-errors "push" "--set-upstream" "origin" current)
   (refresh-repos!)))

(defn- push! []
  (p/let [current (cmds/current-branch)]
    (if (.. js/atom -config (get "simple-git.denyPush"))
      (p/let [default (cmds/default-branch)]
        (if (= default current)
          (cmds/error! "Can't push" (str "Can't push to " default
                                         ". Please, create a branch and push from there"))
          (push-branch! current)))
      (push-branch! current))))

(defn- add-cmd! [command fun]
  (.add @subscriptions
        (.. js/atom -commands (add "atom-text-editor" (str "git:" command) fun))))

(defrecord DiffClass [title file]
  Object
  (getTitle [_] title)
  (destroy [this]
    (-> (filter #(.. ^js % getItems (includes this))
                (.. js/atom -workspace getPanes))
        first
        (some-> (.removeItem this)))))

(defn- get-diff! [state pos file]
  (let [dir (dirname file)]
    (if-let [diff (get-in @state [pos 4])]
      diff
      (p/let [commit (get-in @state [pos 0])
              {:keys [output]} (cmds/run-git-in-dir ["diff"
                                                     (str commit "^.." commit)
                                                     file]
                                                    dir)]
        (swap! state assoc-in [pos 4] output)
        output))))

(defn- prepare-history [file]
  (p/let [dir (dirname file)
          logs (cmds/run-git-in-dir ["log" "--format=format:%h..%aI..%an..%s"
                                     (when file "--follow") file]
                                    dir)
          unstaged-diff (cmds/run-git-in-dir ["diff" file] dir)
          logs (->> logs
                    :output
                    str/split-lines
                    (mapv #(str/split % #"\.\." 4))
                    atom)]
    (when (-> unstaged-diff :output not-empty)
      (swap! logs
             #(->> %
                   (cons ["UNSTAGED" (.toISOString (js/Date.))
                          "<no-author>" "UNSTAGED" (:output unstaged-diff)])
                   vec)))
    logs))

(defn- replace-diff-view! [{:keys [file pos view state]}]
  (p/let [dir (dirname file)
          diff (get-diff! state pos file)]
    (append-diff! diff view)))

(defn- history-ui [state div diff-view file]
  (doseq [[[commit date author msg] idx] (map vector @state (range))
          :let [row (doto (js/document.createElement "div")
                          (.. -classList (add "row")))
                commit-link (doto (js/document.createElement "a")
                                  (aset "href" "#")
                                  (aset "innerText" commit)
                                  (aset "onclick" (fn [e]
                                                    (.preventDefault e)
                                                    (replace-diff-view! {:file file
                                                                         :pos idx
                                                                         :view diff-view
                                                                         :state state}))))]]
    (.append row (doto (js/document.createElement "div")
                       (.. -classList (add "badge" "badge-medium" "badge-info" "icon-git-commit"))
                       (.append commit-link)))
    (.append row (doto (js/document.createElement "div") (.append date)))
    (.append row (doto (js/document.createElement "div") (.append author)))
    (.append row (doto (js/document.createElement "div") (.append msg)))
    (.append div row)))

(defn view-provider [{:keys [file]}]
  (let [file (if (= "<project>" file) nil file)
        diff-view (doto (js/document.createElement "div")
                        (.. -classList (add "native-key-bindings" "simple-git" "diff-view"))
                        (.setAttribute "tabindex" 1)
                        (.. -style (setProperty "overflow" "scroll")))
        history-view (doto (js/document.createElement "div")
                           (.. -classList (add "native-key-bindings" "simple-git" "history"))
                           (.setAttribute "tabindex" 2)
                           (.. -style (setProperty "overflow" "scroll"))
                           (.. -style (setProperty "flex-direction" "column")))
        root (doto (js/document.createElement "div")
                   (.. -classList (add "native-key-bindings")))]
    (p/let [history (prepare-history file)
            diff (get-diff! history 0 file)]
      (.. root -style (setProperty "display" "flex"))
      (history-ui history history-view diff-view file)
      (append-diff! diff diff-view)
      (.append root diff-view)
      (.append root history-view))
    root))

(defn- aggregate-commit [blame-str]
  (->> blame-str
       str/split-lines
       (map #(-> %
                 (str/split #"\t" 4)
                 (update 3 str/split #"\)" 2)))
       (reduce (fn [acc val]
                 (let [[last-commit] (peek acc)
                       commit (first val)]
                   (if (= last-commit commit)
                     acc
                     (conj acc val))))
               [])))

(defn- decorate-editor! [^js editor]
  (p/let [path (.getPath editor)
          {:keys [output]} (cmds/run-git-in-dir ["blame" "-M" "-w" "-c" path]
                                                (dirname path))
          blame (aggregate-commit output)
          blames (for [[commit author time [row-str]] blame
                       :let [row (-> row-str js/parseInt dec)
                             div (doto (js/document.createElement "div")
                                       (.. -classList (add "simple-git" "blame")))
                             mark (. editor markScreenPosition #js [row, 0])]]
                    (do
                      (.append div (doto (js/document.createElement "div")
                                         (aset "innerText" commit)))
                      (.append div (doto (js/document.createElement "div")
                                         (aset "innerText" (subs author 1))))
                      (.append div (doto (js/document.createElement "div")
                                         (aset "innerText" time)))
                      (. editor decorateMarker mark #js {:type "block"
                                                         :position "before"
                                                         :item div})
                      mark))]

    (aset editor "__blames" (doall blames))
    (.. js/atom -workspace getActiveTextEditor scrollToCursorPosition)))

(defn- blame! []
  (let [editor (.. js/atom -workspace getActiveTextEditor)]
    (if-let [blames (.-__blames editor)]
      (do
        (aset editor "__blames" nil)
        (doseq [^js b blames] (.destroy b))
        (. editor scrollToCursorPosition))
      (decorate-editor! (.. js/atom -workspace getActiveTextEditor)))))

(defn activate [state]
  (reset! atom-state state)

  (.add @subscriptions
        (.. js/atom
            -workspace
            (addOpener #(when-let [[_ uri] (re-matches #"diff://(.*)" %)]
                          (->DiffClass (str "Diff for " uri) uri)))))

  (.add @subscriptions
        (.. js/atom -views (addViewProvider DiffClass view-provider)))
  (add-cmd! "add-current-file" #(cmds/run-git-treating-errors "add" (cmds/current-file!)))
  (add-cmd! "quick-commit-current-file" #(protect-commit! quick-commit!))
  (add-cmd! "commit" #(protect-commit! commit!))
  (add-cmd! "push-current-branch" push!)
  (add-cmd! "new-branch-from-current"
            #(p/let [branch-name (prompt! "Type a valid branch name")]
               (cmds/run-git-treating-errors "checkout" "-b" branch-name)))

  (add-cmd! "show-diff-for-current-file"
            #(.. js/atom -workspace (open (str "diff://" (cmds/current-file!)))))
  (add-cmd! "show-diff-for-project"
            #(.. js/atom -workspace (open (str "diff://<project>"))))
  (add-cmd! "toggle-blame" blame!)
  (add-cmd! "checkout-and-update-default-branch"
            #(p/let [default (cmds/default-branch)]
               (cmds/run-git "checkout" default)
               (cmds/run-git-treating-errors "pull")
               (refresh-repos!))))

(defn deactivate [state]
  (.dispose ^js @subscriptions))

(defn ^:dev/before-load reset-subs []
  (deactivate @atom-state))

(defn ^:dev/after-load re-activate []
  (reset! subscriptions (CompositeDisposable.))
  (activate @atom-state)
  (cmds/info! "Reloaded plug-in" ""))

(def config
  (clj->js
   {:denyCommit {:description "Deny commits on default (master/main) branch"
                 :type "boolean"
                 :default true}
    :denyPush {:description "Deny pushes to remote default (master/main) branch"
               :type "boolean"
               :default true}}))
