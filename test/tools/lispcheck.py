#!/usr/bin/env python3
"""Check Lisp source files for structural problems, without needing a Lisp.

    lispcheck.py [--generic] [--strict] [--eol {auto,crlf,lf,any}] FILE...

Reports, with line and column:
  - unbalanced parentheses (unclosed forms, stray closing parentheses)
  - unterminated strings and block comments
  - hints for locating the problem: a '(' in column 1 while an earlier form is still
    open usually marks where a ')' went missing (shown only when the file has an
    error, or always with --suspects)
  - mixed or unexpected line endings (warning)

Understands ; comments, nested #| |# comments, "strings", |symbols|, #\\x
character literals and backslash escapes. By default it also understands the
Corman Lisp reader extension #! ... !# (an opaque block of C declarations) and
ignores a leading #! shebang line. Use --generic to turn that off.

It does not run a Lisp reader: it cannot see unknown packages, bad #. forms or
misuse of reader macros. A clean result means "structurally balanced", not "loads".

Exit code 0 = no errors (and no warnings with --strict), 1 = problems found.
"""

import argparse
import sys

SYMBOL_CONSTITUENT_AFTER_CHAR = set(
    "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_+*/<>=!?$%&^~.:")


class Report:
    def __init__(self, path):
        self.path = path
        self.errors = []
        self.warnings = []

    def error(self, line, col, message):
        self.errors.append((line, col, message))

    def warn(self, line, col, message):
        self.warnings.append((line, col, message))


def check_text(text, path, corman=True, eol="auto", show_suspects=False):
    rep = Report(path)
    n = len(text)
    i = 0
    line = 1
    col = 1
    stack = []          # (line, col) of each open paren
    suspects = []       # column-1 '(' seen while a form was open
    at_line_start = True

    def advance(k=1):
        nonlocal i, line, col, at_line_start
        for _ in range(k):
            if i >= n:
                return
            ch = text[i]
            i += 1
            if ch == "\n":
                line += 1
                col = 1
                at_line_start = True
            else:
                col += 1
                at_line_start = False

    # shebang first line
    if text.startswith("#!") and not corman:
        while i < n and text[i] != "\n":
            advance()
    elif text.startswith("#!/") or text.startswith("#! /"):
        while i < n and text[i] != "\n":
            advance()

    while i < n:
        ch = text[i]
        start_line, start_col = line, col
        column_one = at_line_start
        if ch == ";":
            while i < n and text[i] != "\n":
                advance()
        elif ch == '"':
            advance()
            closed = False
            while i < n:
                c = text[i]
                if c == "\\":
                    advance(2)
                elif c == '"':
                    advance()
                    closed = True
                    break
                else:
                    advance()
            if not closed:
                rep.error(start_line, start_col, "unterminated string")
        elif ch == "|":
            advance()
            closed = False
            while i < n:
                c = text[i]
                if c == "\\":
                    advance(2)
                elif c == "|":
                    advance()
                    closed = True
                    break
                else:
                    advance()
            if not closed:
                rep.error(start_line, start_col, "unterminated |symbol|")
        elif ch == "#" and text.startswith("#|", i):
            depth = 1
            advance(2)
            while i < n and depth:
                if text.startswith("#|", i):
                    depth += 1
                    advance(2)
                elif text.startswith("|#", i):
                    depth -= 1
                    advance(2)
                else:
                    advance()
            if depth:
                rep.error(start_line, start_col, "unterminated #| block comment")
        elif ch == "#" and corman and text.startswith("#!", i) and not text.startswith("#!/", i):
            advance(2)
            closed = False
            while i < n:
                if text.startswith("!#", i):
                    advance(2)
                    closed = True
                    break
                advance()
            if not closed:
                rep.error(start_line, start_col, "unterminated #! ... !# block")
        elif ch == "#" and text.startswith("#\\", i):
            advance(2)
            if i < n:
                advance()           # the character itself, whatever it is
            while i < n and text[i] in SYMBOL_CONSTITUENT_AFTER_CHAR:
                advance()           # names such as #\Space, #\Newline
        elif ch == "\\":
            advance(2)              # escaped character inside a symbol
        elif ch == "(":
            if column_one and stack:
                suspects.append((start_line, start_col,
                                 "'(' in column 1 while the form opened at line %d, column %d is still "
                                 "open (missing ')' above?)" % (stack[-1][0], stack[-1][1])))
            stack.append((start_line, start_col))
            advance()
        elif ch == ")":
            if stack:
                stack.pop()
            else:
                rep.error(start_line, start_col, "unmatched ')' with no open form")
            advance()
        else:
            advance()

    for (l, c) in stack:
        rep.error(l, c, "'(' is never closed")

    # A '(' in column 1 inside an open form is normal in some styles (for example
    # arguments written flush left under an eval-when), so it is only reported as a
    # hint when the file already has a real error, to help locate a missing ')'.
    if rep.errors or show_suspects:
        for (l, c, m) in suspects:
            rep.warn(l, c, "hint: " + m)

    # line endings
    crlf = text.count("\r\n")
    lf_total = text.count("\n")
    bare_lf = lf_total - crlf
    if eol == "auto":
        if crlf and bare_lf:
            rep.warn(1, 1, "mixed line endings: %d CRLF and %d bare LF" % (crlf, bare_lf))
    elif eol == "crlf" and bare_lf:
        rep.warn(1, 1, "%d line(s) without CR (expected CRLF)" % bare_lf)
    elif eol == "lf" and crlf:
        rep.warn(1, 1, "%d line(s) with CRLF (expected LF)" % crlf)
    return rep


def main(argv=None):
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("files", nargs="+")
    parser.add_argument("--generic", action="store_true",
                        help="plain Common Lisp: no Corman #! ... !# blocks")
    parser.add_argument("--suspects", action="store_true",
                        help="always report column-1 '(' inside an open form (noisy on some styles)")
    parser.add_argument("--strict", action="store_true", help="warnings also fail the run")
    parser.add_argument("--eol", choices=("auto", "crlf", "lf", "any"), default="auto",
                        help="expected line endings (default: warn only if mixed)")
    args = parser.parse_args(argv)

    bad = 0
    for path in args.files:
        try:
            with open(path, "rb") as handle:
                text = handle.read().decode("utf-8", errors="replace")
        except OSError as exc:
            print("%s: cannot read: %s" % (path, exc))
            bad += 1
            continue
        rep = check_text(text, path, corman=not args.generic, eol=args.eol,
                         show_suspects=args.suspects)
        for (l, c, m) in rep.errors:
            print("%s:%d:%d: error: %s" % (path, l, c, m))
        for (l, c, m) in rep.warnings:
            print("%s:%d:%d: warning: %s" % (path, l, c, m))
        if rep.errors or (args.strict and rep.warnings):
            bad += 1
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
