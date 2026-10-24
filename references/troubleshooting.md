# latexdiff troubleshooting

## What the script does

1. Extracts OLD and NEW into `.latexdiff-work/old` and `.latexdiff-work/new`.
2. Runs `fix_colspec.py` on every `.tex` file in both trees (bug 3).
3. Creates `build/` by copying OLD and then copying NEW over it. Figures that were deleted still exist, so the struck-through versions can render.
4. Runs `latexdiff --flatten` with the bug 1 and bug 2 flags, writing `build/ldiff.tex`.
5. Runs `fix_mblock.py` on the result (bug 4).
6. Compiles: engine → biber or bibtex → engine → engine. Two runs after the bibliography step are needed to settle references and page numbers.

The vendored copy is latexdiff 1.4.1a (`scripts/latexdiff.pl`). Its only dependency, `Algorithm::Diff`, is in `scripts/perllib/`.

## The four latexdiff bugs

### Bug 1: dropped `{` around adjacent `\textit`
- **Symptom:** garbled text, or `Paragraph ended before \text@command was complete`.
- **Cause:** when a deleted `\textit{}` sits next to an added one, latexdiff loses the opening `\textit{`.
- **Fix:** `--exclude-textcmd="textit" --append-safecmd="textit"`.
- **Warning:** keep the list to `textit` only. Adding `textbf` makes `\subsection{\textbf{X}}` render as a bare number with no title, because latexdiff comments the title out.

### Bug 2: `\textsuperscript` inside ulem markup
- **Symptom:** many `Extra }, or forgotten \endgroup` / `Missing } inserted` errors pointing at one caption.
- **Fix:** `--exclude-safecmd="textsuperscript"`.

### Bug 3: column spec on its own line (`fix_colspec.py`)
- **Symptom:** `Package array Error: Illegal pream-token (\DIFaddFL)`.
- **Cause:** `\begin{tabular}` followed by a newline (often after a `%` comment) and then `{|p{..}|...}`. latexdiff doesn't treat the spec as an argument and marks it up token by token.
- **Fix:** merge the spec onto the `\begin{tabular}` line in both trees. This doesn't change the rendering. The script uses binary mode so line endings never flip to CRLF.
- **Permanent fix:** put the spec on the same line as `\begin{tabular}` in the source.

### Bug 4: orphaned `\MBLOCKRIGHTBRACE` heading (`fix_mblock.py`)
- **Symptom:** `Paragraph ended before \@sect was complete` together with `Too many }'s`.
- **Cause:** when a heading and its whole body change together, latexdiff loses the heading's closing brace and the added heading's `\subsection{`.
- **Fix:** the script closes the orphaned heading and restores the missing command. When the bug isn't present it reports `repaired 0` and changes nothing.

## Pre-compile checks (on `ldiff.tex`, all should be 0)

| Check | Means |
|---|---|
| `DIFaddFL{\|p}` | bug 3 not fixed: a table spec has a different shape. Extend the regex in `fix_colspec.py`. |
| `MBLOCK` | bug 4 not fixed: `fix_mblock.py` saw unexpected context. Read its output. |
| dropped brace: `\DIFadd{word}}` without a `{` before it | bug 1: a brace was dropped. `\texttt{\DIFadd{x}}` is fine and isn't counted. |
| headings hidden in comments | a heading's title was commented out (often bug 1 with `textbf`) |

## Reading the compile log

**Benign:**
- `Command \definition already defined` (svjour3) and `There's no line here to end`. These come from the paper itself. Compiling the unmodified paper shows the same errors.
- `??` in struck-through text: the deleted text refers to a `\label` that exists only in the old version. latexdiff is doing the right thing here.
- latexdiff stderr (`.latexdiff-work/latexdiff.log`): a missing `.bbl`, no `kpsewhich`, `Missing characters ... |20|`.

**Real:** `Illegal pream-token`, `Extra }`, `Missing }`, `Paragraph ended before \@sect`, `File ... not found`. Check them against the four bugs first.

## Common failures

| Symptom | Cause / fix |
|---|---|
| `Docker is not running` | Start Docker Desktop and wait for `docker run --rm hello-world` to work. The daemon pipe comes up about 30 s before containers can run. |
| `working directory 'C:/Program Files/Git/work' is invalid` | Git Bash rewrote the path. The script sets `MSYS_NO_PATHCONV=1`; check that it's still there. |
| `Can't locate Algorithm/Diff.pm` | The `-I scripts/perllib` flag is missing. |
| `several root candidates` | Pass `--old-root` / `--new-root`. Older Overleaf exports may root at `template.tex`. Mismatched roots still diff fine. |
| `File 'xyz.cls' not found` | The class isn't in TeX Live, so it has to ship inside the zip. |
| Bibliography missing or every citation `?` | Wrong tool. Force it with `--bib biber` or `--bib bibtex`, and check `build/ldiff.bibtool.log`. |
| `fontspec` error under pdflatex | Use `--engine xelatex`. |
| A regex fix silently matches nothing | The file has CRLF line endings. Use binary mode, as the scripts do. |

## Handy commands

Render one page to PNG. The TeX Live image has `gs` but not `pdftotext`. Run this from the build dir, in Git Bash:

```bash
MSYS_NO_PATHCONV=1 docker run --rm -v "$(pwd -W):/work" -w /work texlive/texlive:latest \
  gs -dNOPAUSE -dBATCH -sDEVICE=png16m -r110 -dFirstPage=5 -dLastPage=5 -sOutputFile=pg5.png ldiff.pdf
```

Find the page a label is on. The last number is the page:

```bash
grep -o "newlabel{tab:foo}{{[^}]*}{[0-9]*}" ldiff.aux
```

List which files changed, and by how many lines:

```bash
cd .latexdiff-work && for f in new/*.tex; do b=$(basename "$f"); n=$(diff "old/$b" "$f" 2>/dev/null | grep -c '^[<>]'); [ "$n" -gt 0 ] && echo "$b: $n"; done
```
