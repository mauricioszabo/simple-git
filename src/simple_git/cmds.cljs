(ns simple-git.cmds
  (:require ["child_process" :refer [spawn]]
            ["path" :refer [dirname]]
            [promesa.core :as p]))

(defn current-file! []
  (.. js/atom.workspace getActiveTextEditor getPath))

(defn run-git [ & args]
  (try
    (let [p (p/deferred)
          git (spawn "git" (clj->js args) #js {:cwd (dirname (current-file!))})
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
