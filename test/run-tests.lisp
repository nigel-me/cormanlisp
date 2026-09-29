;;;;	-------------------------------
;;;;	See LICENSE.txt for license information.
;;;;	-------------------------------
;;;;
;;;;	File:		run-tests.lisp
;;;;	Contents:	Command-line entry point for the test harness (test/harness.lisp).
;;;;
;;;;	From the Corman Lisp directory:
;;;;		clconsole -execute test\run-tests.lisp
;;;;
;;;;	Results are written to test-results.jsonl in the current directory.
;;;;	Summarise or compare runs with test/tools/results.py (needs Python 3).
;;;;	Edit :label to name the build being tested (e.g. "vs2015" or "vs2022"),
;;;;	add :trace-tests t to make a crashed run identify the test that was running,
;;;;	and remove :exit t if you want the console to stay open afterwards.
;;;;

(load (concatenate 'string (directory-namestring *load-truename*) "harness.lisp"))

(test-harness:run-all :label "" :exit t)
