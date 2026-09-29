ORACLE = {
"join-strings": '(defun join-strings (sep strings) (format nil (concatenate (quote string) "~{~A~^" (remove #\\~ sep) "~}") strings))',
"split-on-char": '''(defun split-on-char (ch s)
  (loop with start = 0 for pos = (position ch s :start start)
        collect (subseq s start pos) while pos do (setf start (1+ pos))))''',
"unique-strings": '(defun unique-strings (l) (remove-duplicates l :test (function equal) :from-end t))',
"command-kind": '''(defun command-kind (n) (cond ((string= n "start") :start) ((string= n "stop") :stop) ((string= n "restart") :restart) (t :unknown)))''',
"sorted-copy": '(defun sorted-copy (l) (sort (copy-list l) (function <)))',
"hash-keys-sorted": '(defun hash-keys-sorted (h) (sort (loop for k being the hash-keys of h collect k) (function string<)))',
"safe-divide": '(defun safe-divide (a b) (if (zerop b) (values nil :division-by-zero) (values (/ a b) :ok)))',
"lookup": '(defun lookup (k h d) (multiple-value-bind (v f) (gethash k h) (if f (values v t) (values d nil))))',
"flatten-tree": '(defun flatten-tree (x) (cond ((null x) nil) ((atom x) (list x)) (t (append (flatten-tree (car x)) (flatten-tree (cdr x))))))',
"make-counter": '(defun make-counter () (let ((n 0)) (lambda () (incf n))))',
"apply-n": '(defun apply-n (f n x) (dotimes (i n x) (setf x (funcall f x))))',
"alist-set": '''(defun alist-set (al k v)
  (if (assoc k al :test (function string=))
      (mapcar (lambda (e) (if (string= (car e) k) (cons k v) e)) al)
      (append al (list (cons k v)))))''',
"parse-pairs": '''(defun parse-pairs (s)
  (if (string= s "") nil
      (loop with start = 0 for semi = (position #\; s :start start)
            for piece = (subseq s start semi)
            for eq = (position #\\= piece)
            collect (cons (subseq piece 0 eq) (parse-integer piece :start (1+ eq)))
            while semi do (setf start (1+ semi)))))''',
"read-lines": '(defun read-lines (p) (with-open-file (s p) (loop for l = (read-line s nil) while l collect l)))',
"point-distance": '(defstruct point x y) (defun point-distance (p q) (sqrt (+ (expt (- (point-x p) (point-x q)) 2) (expt (- (point-y p) (point-y q)) 2))))',
"account-class": '''(defclass account () ((balance :initarg :balance :initform 0 :accessor account-balance)))
(defgeneric deposit (account amount))
(defmethod deposit ((a account) amount)
  (unless (and (realp amount) (plusp amount)) (error "bad amount ~A" amount))
  (incf (account-balance a) amount))''',
"parse-failure": '''(define-condition parse-failure (error) ((text :initarg :text :reader parse-failure-text)))
(defun parse-digits (s)
  (if (and (plusp (length s)) (every (lambda (c) (char<= #\\0 c #\\9)) s)) (parse-integer s) (error (quote parse-failure) :text s)))''',
"swap-values": '(defmacro swap-values (a b) (let ((tmp (gensym))) `(let ((,tmp ,a)) (setf ,a ,b ,b ,tmp) nil)))',
"while-macro": '(defmacro while (test &body body) `(loop (unless ,test (return nil)) ,@body))',
"safe-parse-int": '(defun safe-parse-int (s) (handler-case (parse-integer s) (error () nil)))',
"average": '(defun average (l) (when l (/ (reduce (function +) l) (float (length l)))))',
"last-n": '(defun last-n (l n) (let ((len (length l))) (if (>= n len) (copy-list l) (nthcdr (- len n) l))))',
"group-by-length": '''(defun group-by-length (ss)
  (let ((groups nil))
    (dolist (s ss) (let ((g (assoc (length s) groups))) (if g (setf (cdr g) (append (cdr g) (list s))) (setf groups (append groups (list (list (length s) s)))))))
    groups))''',
"table-string": '''(defun table-string (rows) (with-output-to-string (o) (dolist (r rows) (format o "~{~A~^~C~}~%" (loop for (x . rest) on r collect x when rest collect (code-char 9))))))''',
"fizzbuzz": '(defun fizzbuzz (n) (loop for i from 1 to n collect (cond ((zerop (mod i 15)) "FizzBuzz") ((zerop (mod i 3)) "Fizz") ((zerop (mod i 5)) "Buzz") (t i))))',
"collatz-length": '(defun collatz-length (n) (loop for steps from 0 until (= n 1) do (setf n (if (evenp n) (/ n 2) (1+ (* 3 n)))) finally (return steps)))',
"palindrome-p": '(defun palindrome-p (s) (let ((c (remove-if-not (function alphanumericp) (string-downcase s)))) (string= c (reverse c))))',
"matrix-transpose": '(defun matrix-transpose (r) (apply (function mapcar) (function list) r))',
}
# Naive versions expected to FAIL their task (proves the tests catch the classic mistakes).
NAIVE = {
"join-strings": '(defun join-strings (sep strings) (str:join sep strings))',
"split-on-char": '(defun split-on-char (ch s) (split-string s ch))',
"unique-strings": '(defun unique-strings (l) (remove-duplicates l :test (function equal)))',
"command-kind": '(defun command-kind (n) (case n ("start" :start) ("stop" :stop) ("restart" :restart) (t :unknown)))',
"sorted-copy": '(defun sorted-copy (l) (sort l (function <)))',
"hash-keys-sorted": '(defun hash-keys-sorted (h) (sort (hash-table-keys h) (function string<)))',
"lookup": '(defun lookup (k h d) (or (gethash k h) d))',
"alist-set": '(defun alist-set (al k v) (let ((e (assoc k al))) (if e (progn (setf (cdr e) v) al) (append al (list (cons k v))))))',
"swap-values": '(defmacro swap-values (a b) `(let ((tmp ,a)) (setf ,a ,b ,b tmp)))',
"safe-parse-int": '(defun safe-parse-int (s) (parse-integer s :junk-allowed t))',
"average": '(defun average (l) (when l (/ (reduce (function +) l) (length l))))',
"table-string": '(defun table-string (rows) (with-output-to-string (o) (dolist (r rows) (format o "~{~A~^\\t~}\\n" r))))',
"flatten-tree": '(defun flatten-tree (x) (cond ((atom x) (list x)) (t (mapcan (function flatten-tree) x))))',
}
