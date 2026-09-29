;;;;	-------------------------------
;;;;	See LICENSE.txt for license information.
;;;;	-------------------------------
;;;;
;;;;	File:		harness.lisp
;;;;	Contents:	Machine-readable test harness for Corman Lisp.
;;;;
;;;;	Runs the existing test files WITHOUT modifying them and writes one JSON
;;;;	object per line (JSON Lines) describing every test result, plus an
;;;;	environment record and a summary record. Use test/tools/results.py to
;;;;	summarise a run or to diff two runs (for example the same tests on two
;;;;	different builds of the kernel).
;;;;
;;;;	Usage (from a console or the IDE, in a fresh image):
;;;;		(load "test/harness.lisp")
;;;;		(test-harness:run-all :label "vs2015-baseline")
;;;;
;;;;	Or from the command line:
;;;;		clconsole -execute test\run-tests.lisp
;;;;
;;;;	Notes:
;;;;	- The harness redefines VERIFY and DOTESTS in COMMON-LISP-USER (the same
;;;;	  names test/ansi-examples.lisp uses) so that the ANSI chapter files
;;;;	  record results instead of printing them.
;;;;	  Do not load test/ansi-examples.lisp into the same image afterwards.
;;;;	- Unlike ansi-examples.lisp, an error in one example does not abort the
;;;;	  rest of its DOTESTS group; the error is recorded and the run continues.
;;;;	- Nothing here can protect against an infinite loop or a crash of the
;;;;	  Lisp process. If a run stops early, the JSONL file written so far still
;;;;	  shows the last test that started (records are flushed as they are written).
;;;;
;;;;	Result record fields (all records have "type"):
;;;;		environment: harness_version, label, implementation, version, features, started
;;;;		result:      file, suite, index, status, expr, expected, actual, output, message, ms
;;;;		summary:     totals, files, elapsed_ms
;;;;	status is one of "pass", "fail", "error", "info".
;;;;	"info" means the expected value was IMPLEMENTATION-DEPENDENT: the example ran
;;;;	but there is nothing to compare against.
;;;;

(defpackage :test-harness
	(:use :common-lisp)
	(:export
		#:run-all
		#:run-file
		#:*label*
		#:*capture-output*
		#:*max-text*
		#:*max-failures-shown*
		#:*trace-begin*))

(in-package :test-harness)

(defparameter *harness-version* 1)

;;; Free-form tag stored in the environment record, e.g. "vs2015" or "vs2022-clang".
(defvar *label* "")
;;; When true, output printed by a test expression is captured and stored in the
;;; result record instead of appearing on the console.
(defvar *capture-output* t)
;;; Longest text stored for any single expression, expected or actual value.
(defvar *max-text* 400)
(defvar *max-failures-shown* 60)
;;; When true, a "begin" record is written and flushed before each test runs. If the
;;; Lisp process crashes or hangs, the last "begin" record identifies the culprit.
(defvar *trace-begin* nil)

(defvar *stream* nil)			; JSONL output stream
(defvar *current-file* "")
(defvar *current-suite* "")
(defvar *index* 0)
(defvar *totals* nil)			; hash table: status string => count
(defvar *file-totals* nil)		; hash table: file name => hash table like *totals*
(defvar *failures-shown* 0)

;;; A tag the harness catches to survive errors that escape HANDLER-CASE in
;;; Corman Lisp (the system uses the catch tag COMMON-LISP::%ERROR internally).
(defparameter *error-catch-tag*
	#+cormanlisp 'common-lisp::%error
	#-cormanlisp (gensym "ERROR-TAG"))

;;;
;;; Small helpers (kept simple on purpose: this file must run on Corman Lisp)
;;;

(defun symbol-named-p (x name)
	(and (symbolp x) (string= (symbol-name x) name)))

(defun truncate-text (text)
	(if (> (length text) *max-text*)
		(concatenate 'string (subseq text 0 *max-text*) "...")
		text))

(defun safe-prin1 (object)
	(truncate-text
		(handler-case
			(let ((*print-length* 20)
				  (*print-level* 6)
				  (*print-circle* nil)
				  (*print-pretty* nil)
				  (*package* (find-package "COMMON-LISP-USER")))
				(prin1-to-string object))
			(error () "#<unprintable object>"))))

(defun safe-princ (object)
	(truncate-text
		(handler-case (princ-to-string object)
			(error () "#<unprintable condition>"))))

(defun pad2 (n)
	(if (< n 10) (format nil "0~D" n) (format nil "~D" n)))

(defun iso-timestamp (universal-time)
	(multiple-value-bind (second minute hour day month year)
		(decode-universal-time universal-time 0)
		(format nil "~D-~A-~AT~A:~A:~AZ"
			year (pad2 month) (pad2 day) (pad2 hour) (pad2 minute) (pad2 second))))

(defun elapsed-ms (start end)
	(truncate (* 1000 (- end start)) internal-time-units-per-second))

;;;
;;; JSON output. Values: string, integer, :true, :false, NIL (null),
;;; (:array item...), (:object (key . value)...). Anything else is printed
;;; with PRIN1 and written as a string.
;;;

(defun write-hex4 (code stream)
	(let ((digits "0123456789ABCDEF"))
		(write-char (char digits (logand (ash code -12) 15)) stream)
		(write-char (char digits (logand (ash code -8) 15)) stream)
		(write-char (char digits (logand (ash code -4) 15)) stream)
		(write-char (char digits (logand code 15)) stream)))

(defun json-write-string (string stream)
	(write-char #\" stream)
	(dotimes (i (length string))
		(let* ((ch (char string i))
			   (code (char-code ch)))
			(cond
				((char= ch #\") (write-string "\\\"" stream))
				((char= ch #\\) (write-string "\\\\" stream))
				((= code 10) (write-string "\\n" stream))
				((= code 13) (write-string "\\r" stream))
				((= code 9) (write-string "\\t" stream))
				((or (< code 32) (> code 126))
				 (write-string "\\u" stream)
				 (write-hex4 (if (> code 65535) 65533 code) stream))
				(t (write-char ch stream)))))
	(write-char #\" stream))

(defun json-write (value stream)
	(cond
		((null value) (write-string "null" stream))
		((eq value :true) (write-string "true" stream))
		((eq value :false) (write-string "false" stream))
		((stringp value) (json-write-string value stream))
		((integerp value) (format stream "~D" value))
		((and (consp value) (eq (car value) :array))
		 (write-char #\[ stream)
		 (let ((first t))
			(dolist (item (cdr value))
				(if first (setq first nil) (write-char #\, stream))
				(json-write item stream)))
		 (write-char #\] stream))
		((and (consp value) (eq (car value) :object))
		 (write-char #\{ stream)
		 (let ((first t))
			(dolist (pair (cdr value))
				(if first (setq first nil) (write-char #\, stream))
				(json-write-string (car pair) stream)
				(write-char #\: stream)
				(json-write (cdr pair) stream)))
		 (write-char #\} stream))
		(t (json-write-string (safe-prin1 value) stream))))

(defun emit (fields)
	"Write one JSON object as a line and flush, so a crash loses at most the current test."
	(when *stream*
		(json-write (cons :object fields) *stream*)
		(terpri *stream*)
		(finish-output *stream*)))

;;;
;;; Counting
;;;

(defun make-counter-table () (make-hash-table :test 'equal))

(defun bump (table key)
	(setf (gethash key table) (1+ (gethash key table 0))))

(defun count-status (status)
	(bump *totals* status)
	(let ((table (gethash *current-file* *file-totals*)))
		(unless table
			(setq table (make-counter-table))
			(setf (gethash *current-file* *file-totals*) table))
		(bump table status)))

(defun table-to-json (table)
	(let ((pairs '()))
		(maphash (lambda (k v) (push (cons k v) pairs)) table)
		(cons :object (sort pairs #'string< :key #'car))))

;;;
;;; Recording a result
;;;

(defun emit-begin (expr)
	(when *trace-begin*
		(emit (list (cons "type" "begin")
					(cons "file" *current-file*)
					(cons "suite" *current-suite*)
					(cons "index" *index*)
					(cons "expr" (safe-prin1 expr))))))

(defun record-result (status expr expected actual output message ms)
	(count-status status)
	(emit (list (cons "type" "result")
				(cons "file" *current-file*)
				(cons "suite" *current-suite*)
				(cons "index" *index*)
				(cons "status" status)
				(cons "expr" (safe-prin1 expr))
				(cons "expected" (if (eq expected :none) nil (safe-prin1 expected)))
				(cons "actual" (if (eq actual :none) nil (safe-prin1 actual)))
				(cons "output" (if (and output (plusp (length output))) (truncate-text output) nil))
				(cons "message" message)
				(cons "ms" ms)))
	(when (and (member status '("fail" "error") :test #'string=)
			   (< *failures-shown* *max-failures-shown*))
		(incf *failures-shown*)
		(format t "~&  ~A  ~A #~D: ~A~%" (string-upcase status) *current-suite* *index*
			(safe-prin1 expr))
		(when message (format t "        ~A~%" message))
		(when (string= status "fail")
			(format t "        expected: ~A~%        actual:   ~A~%"
				(if (eq expected :none) "-" (safe-prin1 expected))
				(if (eq actual :none) "-" (safe-prin1 actual))))))

;;;
;;; Evaluating one form
;;;

(defun evaluate-form (form &optional (capture *capture-output*))
	"Evaluate FORM, catching errors. Standard output is captured when CAPTURE is true.
Returns (values kind results output message) where KIND is :ok or :error."
	(let ((out (make-string-output-stream))
		  (kind :ok)
		  (results nil)
		  (message nil)
		  (completed nil))
		(catch *error-catch-tag*
			(handler-case
				(let ((*standard-output* (if capture out *standard-output*)))
					(setq results (multiple-value-list (eval form)))
					(setq completed t))
				(error (condition)
					(setq kind :error)
					(setq message (safe-princ condition))
					(setq completed t))))
		(unless completed
			(setq kind :error)
			(setq message "aborted: non-local exit out of the error system"))
		(values kind results (get-output-stream-string out) message)))

;;;
;;; Comparison. These mirror VERIFY in test/ansi-examples.lisp so that
;;; results are comparable with the original runner.
;;;

(defun test-equalp (a b)
	"Like EQUALP, but the second list may contain TRUE / FALSE designators."
	(or (equalp a b)
		(and (listp a)
			 (listp b)
			 (= (length a) (length b))
			 (every (lambda (x y)
						(or (and x (symbol-named-p y "TRUE"))
							(and (not x) (symbol-named-p y "FALSE"))
							(equalp x y)))
					a b))))

(defun judge (results expected)
	"Returns :pass, :fail or :info for the list of RESULTS against EXPECTED."
	(cond
		((symbol-named-p expected "TRUE") (if (car results) :pass :fail))
		((symbol-named-p expected "FALSE") (if (car results) :fail :pass))
		((symbol-named-p expected "IMPLEMENTATION-DEPENDENT") :info)
		((and (consp expected) (symbol-named-p (car expected) "VALUES"))
		 (if (test-equalp results (cdr expected)) :pass :fail))
		(t (if (equalp (car results) expected) :pass :fail))))

(defun status-string (keyword)
	(cond ((eq keyword :pass) "pass")
		  ((eq keyword :fail) "fail")
		  ((eq keyword :info) "info")
		  (t "error")))

(defun actual-for-report (results expected)
	(if (and (consp expected) (symbol-named-p (car expected) "VALUES"))
		(cons 'values results)
		(if (and (consp results) (null (cdr results)))
			(car results)
			(if results (cons 'values results) nil))))

;;;
;;; DOTESTS groups (the format used by test/ansi-chapter-*.lisp)
;;;

(defun run-dotests (suite examples)
	(let ((*current-suite* (if (symbolp suite) (symbol-name suite) (safe-prin1 suite)))
		  (*index* 0))
		(do ((x examples (cdddr x)))
			((null x))
			(let ((expr (first x))
				  (arrow (second x))
				  (expected (third x)))
				(incf *index*)
				(unless (symbol-named-p arrow "=>")
					(record-result "error" expr :none :none nil
						"malformed test: expected '=>' after the expression; rest of group skipped" 0)
					(return))
				(emit-begin expr)
				(let ((start (get-internal-real-time)))
					(multiple-value-bind (kind results output message)
						(evaluate-form expr)
						(let ((ms (elapsed-ms start (get-internal-real-time))))
							(if (eq kind :error)
								(record-result "error" expr expected :none output message ms)
								(let ((verdict (judge results expected)))
									(record-result (status-string verdict) expr expected
										(actual-for-report results expected)
										output nil ms))))))))))

;;;
;;; TESTKIT suites (DEFINE-TEST-SUITE in test/testkit.lisp): each suite is a function
;;; that prints its own failures and returns the number of problems. We record one
;;; result per suite. This is coarser than DOTESTS, but the suite output is kept.
;;;

(defun run-testkit-suite (name)
	(let* ((*current-suite* (string-upcase name))
		   (*index* 1)
		   (symbol (find-symbol (string-upcase name) "COMMON-LISP-USER"))
		   (start (get-internal-real-time)))
		(if (not (and symbol (fboundp symbol)))
			(record-result "error" (list (intern (string-upcase name) "COMMON-LISP-USER"))
				:none :none nil "suite function is not defined" 0)
			(multiple-value-bind (kind results output message)
				(progn (emit-begin (list symbol))
					(evaluate-form (list symbol)))
				(let ((ms (elapsed-ms start (get-internal-real-time)))
					  (problems (car results)))
					(cond
						((eq kind :error)
						 (record-result "error" (list symbol) :none :none output message ms))
						((eql problems 0)
						 (record-result "pass" (list symbol) 0 problems output nil ms))
						(t
						 (record-result "fail" (list symbol) 0 problems output
							"suite reported problems; see output" ms))))))))

;;;
;;; The manifest: which test files the harness runs and how.
;;; Files that need a human (Y-OR-N-P), are benchmarks, or are not tests
;;; (test/bugs.lisp is a saved mailing-list message) are deliberately excluded.
;;;

(defparameter *manifest*
	'(("ansi-chapter-2.lisp" :dotests)
	  ("ansi-chapter-3.lisp" :dotests)
	  ("ansi-chapter-4.lisp" :dotests)
	  ("ansi-chapter-5.lisp" :dotests)
	  ("ansi-chapter-6.lisp" :dotests)
	  ("ansi-chapter-7.lisp" :dotests)
	  ("ansi-chapter-8.lisp" :dotests)
	  ("test-sequences.lisp" :testkit
	   ("test-position" "test-count" "test-fill" "test-replace" "test-mismatch"
		"test-search" "test-remove" "test-delete" "test-remove-duplicates"
		"test-merge" "test-sort" "test-reverse" "test-substitute"
		"test-nsubstitute" "test-reduce"))))

;;; The directory holding this file. It must be captured while the file is being
;;; loaded, because *LOAD-TRUENAME* is not bound once LOAD has finished.
(defparameter *test-directory*
	(let ((where (or *load-truename* *load-pathname*)))
		(if where
			(directory-namestring where)
			"test/")))

(defun harness-directory () *test-directory*)

(defun file-in-test-directory (name)
	(concatenate 'string (harness-directory) name))

(defun ensure-testkit-loaded ()
	(unless (find "TESTKIT" *modules* :test #'string=)
		(load (file-in-test-directory "testkit.lisp"))))

(defun run-file (name &key (kind :dotests) suites)
	"Run one test file from the test directory. KIND is :DOTESTS or :TESTKIT."
	(let ((*current-file* name)
		  (*current-suite* "<load>")
		  (*index* 0)
		  (*package* (find-package "COMMON-LISP-USER")))
		(format t "~&~A~%" name)
		(let ((start (get-internal-real-time)))
			(multiple-value-bind (kind-of-load results output message)
				(evaluate-form
					(list 'progn
						(when (eq kind :testkit) (list 'test-harness::ensure-testkit-loaded))
						(list 'load (file-in-test-directory name)))
					nil)
				(declare (ignore results))
				(when (eq kind-of-load :error)
					(record-result "error" (list 'load name) :none :none output
						(concatenate 'string "file failed to load: " (or message ""))
						(elapsed-ms start (get-internal-real-time))))
				(when (and (eq kind :testkit) (not (eq kind-of-load :error)))
					(dolist (suite suites)
						(run-testkit-suite suite)))))))

;;;
;;; Entry point
;;;

(defun total (status)
	(gethash status *totals* 0))

(defun run-all (&key (output-file "test-results.jsonl")
					 (label *label*)
					 (files nil)
					 (trace-tests nil)
					 (exit nil))
	"Run every file in the manifest (or just those named in FILES) and write OUTPUT-FILE.
Returns T when there are no failures or errors. With TRACE-TESTS true, begin records are
written before each test (see *TRACE-BEGIN*). With EXIT true, the process is ended
with exit code 0 (all good) or 1, when the Win32 ExitProcess function is available."
	(let ((*totals* (make-counter-table))
		  (*file-totals* (make-counter-table))
		  (*failures-shown* 0)
		  (*label* label)
		  (*trace-begin* trace-tests)
		  (start (get-internal-real-time))
		  (all-good nil))
		(with-open-file (stream output-file :direction :output :if-exists :supersede)
			(let ((*stream* stream))
				(emit (list (cons "type" "environment")
							(cons "harness_version" *harness-version*)
							(cons "label" label)
							(cons "implementation" (lisp-implementation-type))
							(cons "version" (safe-princ (lisp-implementation-version)))
							(cons "features" (cons :array (mapcar #'safe-prin1 *features*)))
							(cons "started" (iso-timestamp (get-universal-time)))))
				(dolist (entry *manifest*)
					(when (or (null files) (member (first entry) files :test #'string=))
						(run-file (first entry) :kind (second entry) :suites (third entry))))
				(let ((elapsed (elapsed-ms start (get-internal-real-time))))
					(emit (list (cons "type" "summary")
								(cons "totals" (table-to-json *totals*))
								(cons "files"
									(let ((pairs '()))
										(maphash (lambda (k v) (push (cons k (table-to-json v)) pairs))
											*file-totals*)
										(cons :object (sort pairs #'string< :key #'car))))
								(cons "elapsed_ms" elapsed)))
					(format t "~&~%Results: ~D pass, ~D fail, ~D error, ~D info  (~D ms)~%Written to ~A~%"
						(total "pass") (total "fail") (total "error") (total "info")
						elapsed output-file))))
		(setq all-good (and (zerop (total "fail")) (zerop (total "error"))))
		(when exit
			(let* ((win32 (find-package "WIN32"))
				   (exit-process (and win32 (find-symbol "EXITPROCESS" win32))))
				(when (and exit-process (fboundp exit-process))
					(funcall exit-process (if all-good 0 1)))))
		all-good))

;;;
;;; Compatibility shims: the ANSI chapter files call DOTESTS, which expands into
;;; a call to VERIFY. Both live in COMMON-LISP-USER, as in test/ansi-examples.lisp.
;;;

(in-package :common-lisp-user)

(defun verify (symbol examples)
	(test-harness::run-dotests symbol examples))

(defmacro dotests (symbol &rest examples)
	`(verify ',symbol ',examples))

(in-package :test-harness)
