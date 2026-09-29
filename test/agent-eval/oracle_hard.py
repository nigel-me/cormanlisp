ORACLE = {
"word-frequencies": '''(defun word-frequencies (s)
  (let ((h (make-hash-table :test (quote equal))) (words nil) (i 0) (n (length s)))
    (loop while (< i n) do
      (if (alpha-char-p (char s i))
          (let ((j (or (position-if-not (function alpha-char-p) s :start i) n)))
            (incf (gethash (string-downcase (subseq s i j)) h 0)) (setf i j))
          (incf i)))
    (maphash (lambda (k v) (push (cons k v) words)) h)
    (sort words (lambda (a b) (or (> (cdr a) (cdr b)) (and (= (cdr a) (cdr b)) (string< (car a) (car b))))))))''',
"csv-parse-line": '''(defun csv-parse-line (line)
  (let ((fields nil) (cur (make-string-output-stream)) (inq nil) (i 0) (n (length line)))
    (loop while (< i n) do
      (let ((c (char line i)))
        (cond (inq (cond ((and (char= c #\\") (< (1+ i) n) (char= (char line (1+ i)) #\\")) (write-char #\\" cur) (incf i))
                         ((char= c #\\") (setf inq nil))
                         (t (write-char c cur))))
              ((char= c #\\") (setf inq t))
              ((char= c #\\,) (push (get-output-stream-string cur) fields))
              (t (write-char c cur))))
      (incf i))
    (push (get-output-stream-string cur) fields)
    (nreverse fields)))''',
"roman-numeral": '(defun roman-numeral (n) (format nil "~@R" n))',
"merge-sorted": '(defun merge-sorted (a b) (merge (quote list) (copy-list a) (copy-list b) (function <)))',
"retry-call": '''(defun retry-call (fn n)
  (dotimes (i n (values nil :gave-up))
    (handler-case (return (values (funcall fn) (1+ i))) (error () nil))))''',
"with-cleanup": '(defmacro with-cleanup ((var init cleanup) &body body) `(let ((,var ,init)) (unwind-protect (progn ,@body) ,cleanup)))',
"skip-bad-entries": '''(define-condition bad-entry (error) ((text :initarg :text :reader bad-entry-text)))
(defun parse-entry (s)
  (restart-case (handler-case (parse-integer s) (parse-error () (error (quote bad-entry) :text s)))
    (skip-entry () nil)))
(defun parse-all-skipping (ss)
  (let ((r nil))
    (dolist (s ss (nreverse r))
      (let ((v (handler-bind ((bad-entry (lambda (c) (declare (ignore c)) (invoke-restart (quote skip-entry))))) (parse-entry s))))
        (when v (push v r))))))''',
"format-money": '''(defun format-money (c) (multiple-value-bind (d r) (floor (abs c) 100) (format nil "~A$~D.~2,'0D" (if (minusp c) "-" "") d r)))''',
"interleave": '''(defun interleave (a b) (cond ((null a) (copy-list b)) ((null b) (copy-list a)) (t (list* (car a) (car b) (interleave (cdr a) (cdr b))))))''',
"capitalize-words": '''(defun capitalize-words (s)
  (let ((out (copy-seq s)) (start t))
    (dotimes (i (length out) out)
      (let ((c (char out i)))
        (cond ((char= c #\\Space) (setf start t))
              (start (setf (char out i) (char-upcase c) start nil))
              (t (setf (char out i) (char-downcase c))))))))''',
"plist-to-alist": '(defun plist-to-alist (p) (loop for (k v) on p by (function cddr) collect (cons k v)))',
"label-methods": '''(defclass animal () ((name :initarg :name :reader animal-name)))
(defclass dog (animal) ())
(defgeneric label (x))
(defmethod label ((x animal)) (format nil "animal ~A" (animal-name x)))
(defmethod label ((x dog)) (format nil "dog ~A / ~A" (animal-name x) (call-next-method)))
(defmethod label :around ((x animal)) (format nil "<~A>" (call-next-method)))''',
"sum-by": '(defun sum-by (l &key key (initial 0)) (reduce (function +) l :key key :initial-value initial))',
"read-config": '''(defun read-config (s)
  (let ((out nil) (start 0))
    (loop
      (let* ((nl (position #\\Newline s :start start)) (line (string-trim " " (subseq s start nl))))
        (when (and (plusp (length line)) (char/= (char line 0) #\\#))
          (let ((eq (position #\\= line)))
            (when eq (push (cons (string-trim " " (subseq line 0 eq)) (string-trim " " (subseq line (1+ eq)))) out))))
        (if nl (setf start (1+ nl)) (return))))
    (nreverse out)))''',
"binary-search": '''(defun binary-search (v x)
  (let ((lo 0) (hi (1- (length v))))
    (loop while (<= lo hi) do
      (let* ((mid (floor (+ lo hi) 2)) (e (aref v mid)))
        (cond ((= e x) (return-from binary-search mid)) ((< e x) (setf lo (1+ mid))) (t (setf hi (1- mid))))))
    nil))''',
"permutations": '''(defun permutations (l) (if (null l) (list nil) (loop for x in l append (mapcar (lambda (p) (cons x p)) (permutations (remove x l :count 1))))))''',
"matrix-multiply": '(defun matrix-multiply (a b) (let ((cols (apply (function mapcar) (function list) b))) (mapcar (lambda (row) (mapcar (lambda (col) (reduce (function +) (mapcar (function *) row col))) cols)) a)))',
}
NAIVE = {
"capitalize-words": '(defun capitalize-words (s) (string-capitalize s))',
"merge-sorted": '(defun merge-sorted (a b) (sort (nconc a b) (function <)))',
"format-money": '(defun format-money (c) (format nil "$~,2F" (/ c 100)))',
"sum-by": '(defun sum-by (l &key key (initial 0)) (reduce (function +) (mapcar key l) :initial-value initial))',
"roman-numeral": '(defun roman-numeral (n) (format nil "~R" n))',
}
