r"""Merge a tabular column spec onto its \begin{tabular} line.

Some sources write the column spec on the line AFTER \begin{tabular}, often
behind a leftover comment such as "%{|c|c|c|c|c|}":

    \begin{tabular}%{|c|c|c|c|c|}
    {|p{19mm}|p{20mm}|p{20mm}|}

latexdiff then cannot recognize "{|p{19mm}...}" as the tabular argument, marks
it up token-by-token, and the array package rejects it
(Illegal pream-token \DIFaddFL).

Merging the spec onto the \begin line is rendering-neutral; applied identically
to old and new it introduces no spurious diff. Runs in binary mode so LF line
endings are never rewritten to CRLF (a Windows text-mode write would do that).

Usage: python fix_colspec.py <file-or-dir> [...]
       Directories are searched recursively for *.tex files.
"""
import os
import re
import sys

# \begin{tabular} or \begin{array}, optional trailing comment, newline, then a
# line starting with "{" (the column spec).
PATTERN = re.compile(rb"(\\begin\{(?:tabular|array)\})[ \t]*(?:%[^\r\n]*)?\r?\n[ \t]*(?=\{)")


def tex_files(paths):
    for p in paths:
        if os.path.isdir(p):
            for root, _, names in os.walk(p):
                for n in names:
                    if n.endswith(".tex"):
                        yield os.path.join(root, n)
        elif p.endswith(".tex") and os.path.isfile(p):
            yield p


total = 0
for path in tex_files(sys.argv[1:]):
    data = open(path, "rb").read()
    new, n = PATTERN.subn(rb"\1", data)
    if n:
        open(path, "wb").write(new)
        print(f"{path}: merged {n} column spec(s)")
        total += n
print(f"fix_colspec: {total} column spec(s) merged")
