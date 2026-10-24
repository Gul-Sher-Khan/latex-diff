r"""Repair latexdiff's unmatched \MBLOCKRIGHTBRACE around sectioning commands.

latexdiff sometimes fails to match up the closing brace of a sectioning command
when a heading AND its whole body change together. It then emits its internal
placeholder as a comment and drops the replacement heading's own sectioning
command, producing e.g.:

    \subsection{\DIFdelbegin \textbf{\DIFdel{Old title}}%DIFAUXCMD
    %DIFDELCMD < \MBLOCKRIGHTBRACE          <- the real "}" is lost in a comment
    ...deleted body, including blank lines...
    on each }\DIFdelend \DIFaddbegin \textbf{\DIFadd{New title}}}

The \subsection{ then swallows the deleted body, and because that body contains
a blank line LaTeX reports "Paragraph ended before \@sect was complete" plus
"Too many }'s". latexdiff's own source documents this as a known rare case that
it deliberately leaves for downstream repair.

The repair, applied per occurrence:
  1. close the orphaned sectioning command (add "}" before its %DIFAUXCMD), and
  2. give the added heading back its sectioning command, so its three closing
     braces balance \subsection{\textbf{\DIFadd{...}}}.

Usage: python fix_mblock.py <diff.tex>
"""
import re
import sys

path = sys.argv[1]
lines = open(path, encoding="utf-8", newline="").read().split("\n")

SECT = re.compile(r"\\(sub)*section\{")
fixed = 0

for i, line in enumerate(lines):
    if "%DIFDELCMD < \\MBLOCKRIGHTBRACE" not in line:
        continue

    # 1. Close the orphaned sectioning command on the preceding line.
    prev = lines[i - 1]
    m = SECT.search(prev)
    if not m or not prev.endswith("%DIFAUXCMD"):
        print(f"  line {i+1}: unexpected context, skipped")
        continue
    sect_cmd = m.group(0)  # e.g. "\subsection{"
    lines[i - 1] = prev[: -len("%DIFAUXCMD")] + "}%DIFAUXCMD"

    # 2. Restore the sectioning command on the added heading that follows.
    for j in range(i + 1, min(i + 60, len(lines))):
        if "\\DIFaddbegin \\textbf{\\DIFadd{" in lines[j] and lines[j].rstrip().endswith("}}}"):
            lines[j] = lines[j].replace(
                "\\DIFaddbegin \\textbf{\\DIFadd{",
                "\\DIFaddbegin " + sect_cmd + "\\textbf{\\DIFadd{",
                1,
            )
            fixed += 1
            print(f"  repaired {sect_cmd} heading pair at lines {i}/{j+1}")
            break
    else:
        print(f"  line {i+1}: no matching added heading found")

open(path, "w", encoding="utf-8", newline="").write("\n".join(lines))
print(f"{path}: repaired {fixed} MBLOCKRIGHTBRACE occurrence(s)")
