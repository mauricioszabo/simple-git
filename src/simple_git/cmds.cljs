(ns simple-git.cmds
  (:require [clojure.string :as str]
            ["child_process" :refer [spawn]]
            ["path" :refer [dirname]]
            [promesa.core :as p]))

(defn current-file! []
  (.. js/atom.workspace getActiveTextEditor getPath))

(defn run-git-in-dir [args current-dir]
  (try
    (let [p (p/deferred)
          args (remove nil? args)
          git (spawn "git" (clj->js args) #js {:cwd current-dir})
          out (atom "")
          err (atom "")
          both (atom "")]
      (.. git -stdout (on "data" (fn [data]
                                   (swap! out str data)
                                   (swap! both str data))))
      (.. git -stderr (on "data" (fn [data]
                                   (swap! err str data)
                                   (swap! both str data))))
      (.. git (on "error" (fn [error]
                            (p/reject! p {:output (.-message error) :code -1}))))
      (.. git (on "close" (fn [code]
                            (if (zero? code)
                              (p/resolve! p {:output @both :stdout @out :stderr @err})
                              (p/reject! p {:output @both :stdout @out :stderr @err :code code})))))
      p)
    (catch :default e
      (p/rejected {:output (.-message e)}))))

(defn run-git [ & args]
  (run-git-in-dir args (dirname (current-file!))))

(defn current-branch []
  (p/let [{:keys [output]} (run-git "rev-parse" "--abbrev-ref" "HEAD")]
    (str/trim output)))

(defn success! [message details]
  (.. js/atom -notifications (addSuccess message #js {:detail details})))

(defn info! [message details]
  (.. js/atom -notifications (addInfo message #js {:detail details})))

(defn error! [message details]
  (.. js/atom -notifications (addError message #js {:detail details})))

(defn run-git-treating-errors [ & args]
  (let [result (apply run-git args)]
    (-> result
        (p/then #(success! "Sucess" (:output %)))
        (p/catch #(error! "Error running command" (:output %)))
        (p/then #(constantly result)))))

(def default-branch
  (memoize (fn []
             (p/let [{:keys [output]} (run-git "remote" "show" "origin")]
               (->> output (re-find #"HEAD branch: (.*)") second)))))
