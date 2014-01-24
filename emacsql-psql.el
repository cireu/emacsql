;;; emacsql-psql.el --- PostgreSQL front-end for Emacsql -*- lexical-binding: t; -*-

;;; Code:

(require 'cl-lib)
(require 'eieio)
(require 'emacsql)

(defvar emacsql-psql-executable "psql"
  "Path to the psql (PostgreSQL client) executable.")

;;;###autoload
(defun emacsql-psql-unavailable-p ()
  "Return a reason if the psql executable is not available.
:no-executable -- cannot find the executable
:cannot-execute -- cannot run the executable
:old-version -- sqlite3 version is too old"
  (let ((psql emacsql-psql-executable))
    (if (null (executable-find psql))
        :no-executable
      (condition-case _
          (with-temp-buffer
            (call-process psql nil (current-buffer) nil "--version")
            (let ((version (cl-third (split-string (buffer-string)))))
              (if (version< version "1.0.0")
                  :old-version
                nil)))
        (error :cannot-execute)))))

(defclass emacsql-psql-connection (emacsql-connection emacsql-simple-parser)
  ((dbname :reader emacsql-psql-dbname :initarg :dbname)
   (types :allocation :class
          :reader emacsql-types
          :initform '((integer "BIGINT")
                      (float "DOUBLE PRECISION")
                      (object "TEXT")
                      (nil "TEXT"))))
  (:documentation "A connection to a PostgreSQL database."))

;;;###autoload
(cl-defun emacsql-psql (dbname &key username hostname port debug)
  "Connect to a PostgreSQL server using the psql command line program."
  (let ((args (list dbname)))
    (when username
      (push username args))
    (push "-n" args)
    (when port
      (push "-p" args)
      (push port args))
    (when hostname
      (push "-h" args)
      (push hostname args))
    (setf args (nreverse args))
    (let* ((buffer (generate-new-buffer "*emacsql-psql*"))
           (psql emacsql-psql-executable)
           (process (apply #'start-process "emacsql-psql" buffer psql args))
           (connection (make-instance 'emacsql-psql-connection
                                      :process process
                                      :dbname dbname)))
      (prog1 connection
        (setf (process-sentinel process)
              (lambda (_proc _) (kill-buffer buffer)))
        (when debug
          (setf (emacsql-log-buffer connection)
                (generate-new-buffer "*emacsql-log*")))
        (emacsql-register connection)
        (mapc (lambda (s) (emacsql-send-string connection s :no-log))
              '("\\pset pager off"
                "\\pset null nil"
                "\\a"
                "\\t"
                "\\f ' '"
                "\\set PROMPT1 ]"
                "EMACSQL;")) ; error message flush
        (emacsql-wait connection)))))

(defmethod emacsql-close ((connection emacsql-psql-connection))
  (let ((process (emacsql-process connection)))
    (when (process-live-p process)
      (process-send-string process "\\q\n"))))

(provide 'emacsql-psql)

;;; emacsql-psql.el ends here