(ns simple-git.core
  (:require [simple-git.cmds :as cmds]
            ["atom" :refer [CompositeDisposable]]))

(def subscriptions (atom (CompositeDisposable.)))

(defonce atom-state (atom nil))

(defn activate [state]
  (reset! atom-state state)

  (.add @subscriptions (.. js/atom -commands
                           (add "atom-text-editor"
                                "git:add-current-file"
                                #(cmds/run-git-treating-errors "add" (cmds/current-file!))))))

(defn deactivate [state]
  (.dispose ^js @subscriptions))

(defn ^:dev/before-load reset-subs []
  (deactivate @atom-state))

(defn ^:dev/after-load re-activate []
  (reset! subscriptions (CompositeDisposable.))
  (activate @atom-state)
  (cmds/info! "Reloaded plug-in" ""))
