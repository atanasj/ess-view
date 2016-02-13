;;; ess-view.el --- View R dataframes in a spreadsheet software

;; Copyright (C) 2016 Bocci Gionata

;; Author: boccigionata <boccigionata@gmail.com>
;; URL: https://github.com/GioBo/ess-view
;; Version: 0.1
;; Package-Requires: ((ess "15") (ess-inf "0") (ess-site "0")  (s "1.8.0") (f "0.16.0"))
;; Keywords: ess


;; This file is not part of GNU Emacs.

;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:


;; When working with big R dataframes, the console is impractical for looking at
;; its content; a spreadsheet software is a much more convenient tool for this task.
;; This package allows users to have a look at R dataframes in an external
;; spreadsheet software.

;; If you simply want to have a look at a dataframe simply hit (inside a buffer running
;; an R process)

;; C-x w

;; and you will be asked for the name of the object (dataframe) to
;; view... it's a simple as that!

;; If you would like to modify the dataframe within the spreadsheet
;; software and then have the modified version loaded back in the
;; original R dataframe, use:

;; C-x q

;; When you've finished modifying the dataset, save the file (depending
;; on the spreadsheet software you use, you may be asked if you want to
;; save the file as a csv file and/or you want to overwrite the original
;; file: the answer to both question is yes) and the file content will be
;; saved in the original R dataframe.

;;; Code:

(require 'ess)
(require 'ess-inf)
(require 'ess-site)
(require 'f)
(require 's)


(defvar ess-view--spreadsheet-program (or
				       (executable-find "libreoffice")
				       (executable-find "openoffice")
				       (executable-find "gnumeric")
				       (executable-find "soffice"))
  
  "Spreadsheet software to be used to show data.")


(defvar  deh (or
	      (executable-find "gatto")
	      nil)
     "docstring")

(defvar ess-view--rand-str
  "Random string to be used for temp files.")

(defvar ess-view-oggetto
  "Name of the R dataframe to work with.")

(defvar ess-view-newobj
  "Temp name to be used for the temporary copy of R object")

(defvar ess-view-temp-file
  "Temporary file to be used to save the csv version of the dataframe")

(defvar ess-view-string-command
  "Command - as a string - to be passed to the R interpreter.")

(defvar ess-view-spr-proc
  "Process of the called spreadsheet software.")

(defun ess-view-print-vector (obj)
  "Print content of vector OBJ in another buffer.
In case the passed object is a vector it is not convenient to use
an external spreadsheet sofware to look at its content."
  (let
      ((header (concat obj " contains the following elements: \n")))
    (ess-execute (concat "cat(" obj ",sep='\n')") nil "*BUFF*" header)))


(defun ess-view-random-string ()
  "This function create a random string of 20 characters."
  (interactive)
  (setq ess-view--rand-str "")
  (let ((mycharset '("a" "b" "c" "d" "e" "f" "g" "h" "i" "j" "k" "l" "m" "n" "o" "p" "q" "r" "s" "t" "y" "v" "w" "x" "y" "z")))
    (dotimes (i 20)
      (setq ess-view--rand-str (concat ess-view--rand-str (elt mycharset (random (length mycharset)))))))
  ess-view--rand-str)


(defun ess-view-create-env ()
  "Create a temporary R environment.
This is done in order not to pollute user's environments with a temporary
copy of the passed object which is used to create the temporary .csv file."
  (interactive)
  (let*
      ((nome_env
	(ess-view-random-string)))
    ;; it is very unlikely that the user has an environment which
    ;; has the same name of our random generated 20-char string,
    ;; but just to be sure, we run this cycle recursively
    ;; until we find an environment name which does not exist yet
    (if
	(ess-boolean-command
	 (concat "is.environment(" nome_env ")\n"))
	(ess-view-create-env))
    nome_env))


(defun ess-view-send-to-R (STRINGCMD)
  "A wrapper function to send commands to the R process.
Argument STRINGCMD  is the command - as a string - to be passed to the R process."
  (ess-send-string (get-process "R") STRINGCMD nil))

(defun ess-view-write--sentinel (process signal)
  "Chech the spreadsheet (PROCESS) to intercepts when it is closed (SIGNAL).
The saved version of the file - in the csv fomat -is than converted back
to the R dataframe."
  (cond
   ((equal signal "finished\n")
    (progn
      (check_separator ess-view-temp-file)
      (ess-view-send-to-R (format "%s <- read.table('%s',header=TRUE,sep=',',stringsAsFactors=FALSE)\n" ess-view-oggetto ess-view-temp-file))))))
  
(defun ess-view-clean-data-frame (obj)
  "This function cleans the dataframe of interest.
Factors are converted to characters (less problems when exporting), NA and
'NA' are removed so that reading the dataset within the spreadsheet software
is clearer.
Argument OBJ is the name of the dataframe to be cleaned."
  (ess-view-send-to-R (format "%s[sapply(%s,is.factor)]<-lapply(%s[sapply(%s,is.factor)],as.character)" obj obj obj obj))
  (ess-view-send-to-R (format "%s[is.na(%s)]<-''\n" obj obj))
  (ess-view-send-to-R (format "%s[%s=='NA']<-''\n" obj obj)))

(defun ess-view-data-frame-view (object save)
  "This function is used in case the passed OBJECT is a data frame.
Argument SAVE if t means that the user wants to store the spreadsheet-modified
version of the dataframe in the original object."
  ;;  (interactive)
  (save-excursion

    ;; create a temp environment where we will work
    (let
	((envir (ess-view-create-env))
	 (win_place (current-window-configuration)))

      (ess-send-string (get-process "R") (concat envir "<-new.env()\n") nil)
      ;; create a copy of the passed object in the custom environment
      (ess-send-string (get-process "R") (concat envir "$obj<-" object "\n") nil)
      ;; create a variable containing the complete name of the object
      ;; (in the form environm$object
      (setq ess-view-newobj (concat envir "$obj"))
      ;; remove NA and NAN so that objects is easier to read in spreadsheet file
      (ess-view-clean-data-frame ess-view-newobj)
      ;; create a csv temp file
      (setq ess-view-temp-file (make-temp-file nil nil ".csv"))
      ;; write the passed object to the csv tempfile
      (setq ess-view-string-command (concat "write.table(" ess-view-newobj ",file='" ess-view-temp-file "',sep='|',row.names=FALSE)\n"))
      (ess-send-string (get-process "R") ess-view-string-command)
      ;; wait a little just to be sure that the file has been written (is this necessary? to be checked)
      (sit-for 1)

      ;; start the spreadsheet software to open the temp csv file
      (setq ess-view-spr-proc (start-process "spreadsheet" nil ess-view--spreadsheet-program ess-view-temp-file))
      (if save
	  (set-process-sentinel ess-view-spr-proc 'ess-view-write--sentinel))

      (set-window-configuration win_place)
      ;; remove the temporary environment
      (ess-send-string (get-process "R") (format "rm(%s)" envir)))))


(defun check_separator (filePath)
  "Try to convert the tmp file to the csv format.
This is a tentative strategy to obtain a csv content from the file - specified
by FILEPATH - separated by commas, reagardless of the default field separator
used by the spreadsheet software."
  (let
      ((testo (s-split "\n" (f-read filePath) t)))
    (setq testo (mapcar (lambda (x) (s-replace-all '(("\t" . ",") ("|" . ",") (";" . ",")) x)) testo))
    (setq testo (s-join "\n" testo))
    (f-write-text testo 'utf-8 filePath)))

(defun ess-view-inspect-df ()
  "Used to view the content of the dataframe."
  (interactive)
  (setq ess-view-oggetto (ess-read-object-name "object to inspect:"))
  ;;(setq ess-view-oggetto (car ess-view-oggetto))
  (setq ess-view-oggetto (substring-no-properties (car ess-view-oggetto)))
  ;;(setq test (ess-boolean-command (concat "is.vector('" ess-view-oggetto "')\n")))

  (cond
   ((ess-boolean-command (concat "is.vector(" ess-view-oggetto ")\n")) (ess-view-print-vector ess-view-oggetto))
   ((ess-boolean-command (concat "is.data.frame(" ess-view-oggetto ")\n")) (ess-view-data-frame-view ess-view-oggetto nil))
   (t (message "the object is neither a vector or a data.frame; don't know how to show it..."))))


(defun ess-view-modify-df ()
  "Used to view and modify the object of interest."
  (interactive)
  (setq ess-view-oggetto (ess-read-object-name "object to modify:"))
  ;;(setq ess-view-oggetto (car ess-view-oggetto))
  (setq ess-view-oggetto (substring-no-properties (car ess-view-oggetto)))
  ;;(setq test (ess-boolean-command (concat "is.vector('" ess-view-oggetto "')\n")))

  (cond
   ((ess-boolean-command (concat "is.vector(" ess-view-oggetto ")\n")) (ess-view-print-vector ess-view-oggetto))
   ((ess-boolean-command (concat "is.data.frame(" ess-view-oggetto ")\n")) (ess-view-data-frame-view ess-view-oggetto t))
   (t (message "the object is neither a vector or a data.frame; don't know how to show it..."))))



(define-minor-mode ess-view-mode
  "Have a look ad dataframes."
  :lighter " ess-v"
  :keymap (let ((map (make-sparse-keymap)))
	    (define-key map (kbd "C-x w") 'ess-view-inspect-df)
	    (define-key map (kbd "C-x q") 'ess-view-modify-df)
	    map))


(add-hook 'ess-post-run-hook 'ess-view-mode)
(provide 'ess-view)


;;; ess-view.el ends here
