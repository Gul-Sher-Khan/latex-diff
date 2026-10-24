---
name: latex-diff
description: Generate a change-marked PDF (latexdiff; deletions in red strikethrough, additions in blue underline) between two versions of a LaTeX paper, such as two Overleaf .zip exports or two project folders. Use when the user asks for a LaTeX diff, a tracked-changes or "what changed" PDF between paper versions, revisions, or submissions.
compatibility: Needs bash (Git Bash on Windows), perl, Python 3, and either Docker (texlive/texlive image) or a local TeX Live install.
metadata:
  version: "1.0"
---

# LaTeX diff

All the work happens in `scripts/make_diff.sh`, which is in the same folder as this
SKILL.md. Run it with bash and give it the skill folder's absolute path. The script
already includes every known latexdiff workaround, so don't rebuild the pipeline
by hand or drop any of its flags.

## Steps

1. **Find the two versions.** Ask the user which one is OLD and which is NEW, unless
   the request already says. Each one can be an Overleaf `.zip` or a project folder.
   If the user says something like "the latest two zips", list the `.zip` files in
   the working directory by modification time and confirm the pair with the user.
2. **Pick the output name.** Use the name the user gives. If they give none, follow
   any naming pattern already in the folder (for example `Latest_Diff_<A>x<B>.pdf`).
   If there is no pattern either, let the script use its default.
3. **Run the script** from the folder where the PDF should go:

   ```bash
   bash "<skill-dir>/scripts/make_diff.sh" "OLD.zip" "NEW.zip" -o "Diff_AxB.pdf"
   ```

   Pass `run_in_background` or a long timeout. The first Docker run pulls a ~9 GB
   image, and a normal compile takes 1–3 minutes.

   Options you may need:
   - `--old-root FILE` / `--new-root FILE`: the root `.tex` is auto-detected
     (a top-level file containing `\documentclass`, preferring `main.tex`). Pass
     this when the script reports several candidates.
   - `--engine xelatex|lualatex`: use it when the paper loads `fontspec` or
     `unicode-math`, or when the user says the paper compiles with XeLaTeX or LuaLaTeX.
   - `--bib biber|bibtex|none`: forces the bibliography tool. By default the script
     picks biber when the paper uses `biblatex` and bibtex when it uses `\bibliography{}`.
   - `--docker`: compile in Docker even when TeX is installed locally.
4. **Read the output and report back.**
   - If the script stops with "Docker is not running", ask the user to start Docker
     Desktop. Don't keep retrying.
   - Every line under `checks` must be `0`. If one isn't, open
     [references/troubleshooting.md](references/troubleshooting.md) and look up the
     bug it matches.
   - If `LaTeX errors in log` is non-zero, compare the errors with the "benign"
     list in troubleshooting.md. Only investigate errors that aren't on that list.
   - Tell the user the PDF path, the page count, the number of additions and
     deletions, and anything that isn't benign.
5. **Optional spot-check.** If the user wants to see one changed page, render it
   to PNG (troubleshooting.md has the command) and look at it.

## Rules

- Keep the latexdiff flags and the `fix_colspec.py` / `fix_mblock.py` steps exactly
  as they are. Each one fixes a corruption that has actually happened. In particular,
  don't add `textbf` to `--exclude-textcmd`: it breaks headings.
- Leave the user's input zips and folders alone. All scratch work happens in
  `.latexdiff-work/` next to the output, and the script recreates it on every run.
