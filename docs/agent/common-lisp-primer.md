# Common Lisp primer for coding agents

Not a tutorial. This lists the mistakes that programmers and language models make most often when writing
Common Lisp (CL), each with the fix, and a short routine for checking your work. If an implementation-specific
note in the repo you are working in (for Corman Lisp: `03-lisp-notes.md`) contradicts this file, the repo note wins.

Evidence: this list has been tried on small models, and it has **not** been shown to improve their results; the errors the
models actually made were mostly not the classic traps below. Sections marked *(seen in trials)* were added because a model
made exactly that mistake. See `test/agent-eval/README.md`. Treat the file as a checklist, not as proof of anything.

## 1. Habits carried over from other languages

| Don't write | Why it is wrong | Write |
|---|---|---|
| `(define (f x) ...)`, `#t`, `#f` | Scheme | `(defun f (x) ...)`, `t`, `nil` |
| `(cond ... (else x))` | `else` is an ordinary variable, so this raises an unbound-variable error when reached | `(cond ... (t x))` |
| `(if (null x) ...)` for "empty string / zero / false" | Only `nil` is false. `0`, `""`, `#()` are all true. The empty list and `nil` are the same object | test what you mean: `(zerop n)`, `(string= s "")`, `(null list)` |
| `(f x)` where `f` is a variable holding a function | CL has separate namespaces for functions and variables | `(funcall f x)` / `(apply f args)` |
| `(mapcar square list)` | passes the variable's value | `(mapcar #'square list)` or `(mapcar (lambda (x) ...) list)` |
| `(let ((a 1) (b (+ a 1))) ...)` | `let` binds in parallel, `a` is not yet visible | `let*` for sequential binding |
| `'()` vs `nil` worries | same thing | use `nil` for false/empty; `'()` reads fine for an empty list literal |
| `[1 2 3]`, `{...}`, `x.y`, string interpolation | no such syntax | `(list 1 2 3)`, hash tables/structs, `(slot-value x 'y)` or accessors, `(format nil "~A" x)` |
| `(setq undeclared 5)` at top level | undefined behaviour; warns or errors | `(defvar *x* 5)` then `(setf *x* 6)`, or bind with `let` |

Symbols are upcased by the reader: `foo`, `Foo`, `FOO` are the same symbol. Strings are not.
`'foo` is the symbol, `"foo"` the string, `:foo` a keyword (self-evaluating).

## 2. Equality and `:test`

`eq` identity, `eql` (default for most functions) also compares numbers/characters of the same type,
`equal` compares lists/strings/pathnames structurally, `equalp` is case-insensitive and type-lax.
**The default test is `eql`, so strings and lists do not match unless you say so.**

| Wrong (silently no match) | Right |
|---|---|
| `(member "a" '("a" "b"))` | `(member "a" '("a" "b") :test #'string=)` (or `#'equal`) |
| `(assoc "a" alist)` | `(assoc "a" alist :test #'string=)` |
| `(find "x" list)`, `(position "x" list)`, `(remove "x" list)`, `(count ...)`, `(remove-duplicates list)` on strings | add `:test #'equal` |
| `(case name ("start" ...) ("stop" ...))` | `case` uses `eql` on **unevaluated** keys. Use `(cond ((string= name "start") ...) ...)` |
| `(make-hash-table)` with string keys | `(make-hash-table :test 'equal)` |
| `(case x (nil ...) (t ...))` | `nil` and `t` are special as keys: write `((nil) ...)` and `((t) ...)`; the last clause `(t ...)` or `(otherwise ...)` is the default |

`(string= a b)` is case-sensitive, `(string-equal a b)` is not. `string<` returns an index or `nil`, not `t`.
`(remove-duplicates list)` keeps the **last** occurrence of each item; add `:from-end t` to keep the first.

## 3. Destructive functions and literals

`sort`, `stable-sort`, `nreverse`, `nconc`, `delete`, `delete-duplicates`, `nsubstitute`, `(setf (nth ...))` may modify
their arguments. Always use the **returned** value, and copy first if the original must survive:

```lisp
(sort (copy-list list) #'<)      ; not (sort list #'<) and then using `list`
```

Never modify a literal: `(let ((l '(1 2 3))) (setf (car l) 9))` is undefined behaviour. Build with `(list ...)`/`copy-list`.
Non-destructive: `remove`, `reverse`, `append` (copies all but the last argument), `subseq`, `substitute`, `copy-*`.

## 4. Multiple values

`(values a b)` returns several. Most contexts use only the first. Get the rest with `multiple-value-bind`
(or `multiple-value-list`, `nth-value`). Returns you may forget about:

- `(gethash k h)` returns `(values value present-p)`. A stored `nil` looks like "missing" unless you check the second value.
- `floor`, `truncate`, `round` return quotient **and** remainder. `(floor 7 2)` is 3 and 1.
- `(parse-integer "12abc" :junk-allowed t)` returns 12 (the prefix), not `nil`; without `:junk-allowed` it signals an error.
- `(/ 7 2)` is the **rational** `7/2`, not 3 or 3.5. Use `(floor 7 2)`, `(/ 7 2.0)` or `(float x)`.
- `(find ...)` returns the item (may be `nil`); `(position ...)` returns an index (0 is true); `(member ...)` returns a tail.
- *(seen in trials)* **Wrapping a form throws away extra values.** `(let ((r (progn ,@body))) r)` and `(prog1 form ...)` return one value.
  To pass every value through, return the form itself (`(progn ,@body)`; `unwind-protect` returns the protected form's values), or use
  `multiple-value-prog1`. This matters in macros that wrap a body.
- *(seen in trials)* **`ignore-errors` is not a success flag.** On an error it returns `(values nil condition)`; on success it returns the
  form's own values. So `(multiple-value-bind (v ok) (ignore-errors (values (parse-integer s) t)) ...)` sees a condition object, which is
  true, in `ok` after a failure. Prefer `(handler-case (values (parse-integer s) t) (error () (values nil nil)))`.
- `(last list)` returns the last **cons**, `(car (last list))` the element; `(butlast list n)` drops the end.

## 5. Things that do not exist in standard CL

Do not call these. Standard replacement on the right, or write a small helper.

| Invented | Use instead |
|---|---|
| `string-join`, `str:join` | `(format nil "~{~A~^, ~}" list)` |
| `split-string`, `string-split`, `str:split` | loop with `(position #\, s :start i)` and `subseq` |
| `string-contains`, `string-index` | `(search "sub" s)`, `(position #\c s)` |
| `hash-table-keys`, `hash-table-values` (alexandria) | `(loop for k being the hash-keys of h collect k)` / `... hash-values ...` |
| `flatten`, `range`, `iota`, `take`, `drop`, `filter`, `fold`, `when-let`, `if-let` | write them, or `remove-if-not`, `reduce`, `subseq`, `loop` |
| `print-line`, `println`, `puts` | `(format t "...~%")`, `(terpri)`, `(print x)` |
| libraries (`alexandria`, `cl-ppcre`, `str`, `serapeum`, `uiop`) | do not assume they are installed or loadable; check the repo first |

If you are not sure a function exists, test it before you build on it: `(fboundp 'name)`, `(apropos "NAME")`,
`(describe 'name)`, or look it up in the HyperSpec (CLHS). Undefined-function warnings from the compiler mean a typo or an invention.

## 6. Control flow and iteration

- `dolist`, `dotimes`, `loop` establish a block named `nil`: `(return x)` exits with `x`. `dolist` returns `nil` unless given a result form: `(dolist (x l result) ...)`.
- Named functions: `(return-from fname value)`. There is no bare `return` in a `defun`.
- *(seen in trials, twice)* **`return` leaves only the innermost loop, not the function.** If any form follows the loop, that form's value is
  the function's value and yours is discarded:
  ```lisp
  (defun find-index (v x)
    (loop for i below (length v) do (when (eql (aref v i) x) (return i)))   ; leaves the loop with i ...
    nil)                                                                    ; ... and then returns NIL anyway
  ```
  Use `(return-from find-index i)`, or put the fallback inside the loop (`(loop for i below (length v) when (eql (aref v i) x) return i)`
  returns `nil` by itself when nothing matches), or make the loop the last form. Same trap when a retry loop does `(return (values result n))`
  and a `(values nil :gave-up)` follows it.
- Simple `loop` forms are enough: `(loop for x in list collect (f x))`, `(loop for i from 0 below n do ...)`,
  `(loop for x in l when (evenp x) collect x)`, `(loop for line = (read-line s nil) while line collect line)`.
  Mixing `while`/`do` with `collect` clauses in odd orders is a common source of errors; keep clauses simple.
- `when`/`unless` have an implicit `progn`; `if` takes exactly `test then [else]`: use `progn` for more than one form.
- `(setf (gethash k h) v)`, `(push x list)`, `(incf n)` work on places. `(setf x (cons ...))` in a function does not change the caller's variable.

## 7. Structures, classes, conditions

```lisp
(defstruct point x y)                    ; make-point :x :y, point-x, point-y, point-p, copy-point; accessors are setf-able
(defclass account () ((balance :initarg :balance :accessor balance :initform 0)))
(defgeneric deposit (account amount))
(defmethod deposit ((a account) amount) (incf (balance a) amount))   ; (make-instance 'account :balance 10)
(define-condition my-error (error) ((text :initarg :text :reader my-error-text)))
(handler-case (error 'my-error :text "x")            ; handler-case unwinds, then runs the clause
  (my-error (c) (my-error-text c)))
```

`(error "fmt ~A" x)` signals `simple-error`. `handler-case` unwinds before running the handler; `handler-bind` runs the handler
where the error happened (use it to log or invoke a restart). `ignore-errors` returns `(values nil condition)` on error.
`unwind-protect` guarantees cleanup. `(check-type x integer)` and `(assert (plusp n))` are the standard argument checks.
`defclass` slot options: `:initarg` (for `make-instance`), `:accessor`/`:reader`/`:writer`, `:initform`.

## 8. Macros

- Use backquote: `` `(if ,test (progn ,@body)) ``. `,` inserts a value, `,@` splices a list.
- Any variable your expansion introduces must be a fresh symbol: `(let ((tmp (gensym))) ...)`. Otherwise a caller's variable named `tmp`
  is captured. Evaluate each argument form at most once (bind it to a gensym).
- Macros are expanded when code is compiled, so helper functions they call at expansion time need
  `(eval-when (:compile-toplevel :load-toplevel :execute) ...)`, and a macro must be defined before code that uses it.
- You cannot `funcall`/`apply` a macro. Check expansions with `(macroexpand-1 '(my-macro ...))`.

## 9. I/O, strings, paths

- Read lines safely: `(with-open-file (s path) (loop for line = (read-line s nil) while line collect line))`.
  `(read-line s nil)` returns `nil` at end of file instead of signalling `end-of-file`.
- Write: `(with-open-file (s path :direction :output :if-exists :supersede) (format s "..."))`.
- `(with-output-to-string (s) (format s "~A" x))` builds a string. `(format nil ...)` returns a string, `(format t ...)` prints.
- Common `format` directives: `~A` plain, `~S` readable, `~D` integer, `~F`/`~,2F` fixed float, `~%` newline, `~&` fresh line,
  `~{ ~}` iterate over a list, `~^` stop at last item, `~(~A~)` lowercase, `~10A` pad to width.
- *(seen in trials, three tasks at once)* **`vector-push-extend` and `vector-push` need a fill pointer**: `(make-array 0 :adjustable t)` is not enough.
  Write `(make-array 0 :element-type 'character :adjustable t :fill-pointer 0)`, or better, build strings with
  `(with-output-to-string (o) (write-char c o))`. Results of such arrays are not `simple-string`s; `coerce` if you must return one.
- Text tools: `string-upcase`, `string-trim '(#\Space #\Tab)`, `subseq`, `search`, `char`, `concatenate 'string`, `string-left-trim`.
  Character literals are `#\a`, `#\Space`, `#\Newline`, `#\Tab`.
- Build file names with `merge-pathnames`/`make-pathname`, not string concatenation, unless the repo's notes say otherwise.
  Pathname behaviour varies more between implementations than almost anything else in CL.

## 10. Packages and the reader

- Put `(in-package :name)` at the top of a file after its `defpackage`. Symbols you read belong to the current package when read.
- `pkg:symbol` is exported, `pkg::symbol` reaches an internal one. `#'`, `'`, `` ` ``, `,`, `,@` are reader macros.
- `#+feature` / `#-feature` select code by implementation features (`#+sbcl`, `#+cormanlisp`, `#+win32`).
- Do not `read-from-string` untrusted text without binding `*read-eval*` to `nil`.
- `defvar` does not overwrite an existing value; `defparameter` does. Special variables are named `*like-this*`.

## 11. Work in a checkable way

1. **Balance first.** Long forms are where models fail (in trials, a small model wrote whole solutions with an extra `)` that made them
   unloadable). After editing a Lisp file run a structure check
   (`python3 test/tools/lispcheck.py FILE` in this repo). Keep functions short so each is easy to see whole.
2. **Do not guess names or argument order.** Verify with `describe`, `apropos`, `fboundp`, the HyperSpec, or the repo's own code.
3. **Run what you can.** Load the file, call each function on a normal input, an edge input (`nil`, empty string, one element)
   and an error input. Read every compiler warning: undefined function/variable usually means a typo or an invented function.
4. **If you cannot run the target implementation**, say so, and check the portable parts on another Common Lisp if one is available
   (for example `sbcl --script file.lisp`). That finds syntax and logic errors, not implementation differences.
5. **Change one thing at a time**, and match the file's existing indentation, naming and comment style.
6. Check results that involve order: hash-table iteration order is unspecified; sort before comparing.
