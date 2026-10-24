# latex-diff

An [Agent Skill](https://agentskills.io) that turns two versions of a LaTeX paper into a
change-marked PDF: deletions in red strikethrough, additions in blue underline. The
versions can be Overleaf `.zip` exports or project folders.

Tested with **Claude Code**, **OpenAI Codex**, and **Cursor**. All three use the same
`SKILL.md` format, so one folder works in each.

```
/latex-diff old.zip new.zip     # Claude Code, Cursor
$latex-diff old.zip new.zip     # Codex
```

You can also just ask, for example: *"make a latex diff between paper_v1.zip and paper_v2.zip"*.

## Requirements

| Tool | Notes |
|---|---|
| bash | On Windows, use Git Bash (it ships with Git for Windows) |
| perl | Comes with Git Bash. latexdiff and its `Algorithm::Diff` dependency are included in this repo |
| Python 3 | |
| Docker **or** TeX Live | When `pdflatex` isn't on your PATH, the PDF is compiled in the `texlive/texlive` image (about 9 GB, downloaded once) |

## Install

Each tool looks for skills in its own folder:

| Tool | Folder it reads |
|---|---|
| Claude Code | `~/.claude/skills/` |
| Codex | `~/.agents/skills/` |
| Cursor | `~/.cursor/skills/` or `~/.agents/skills/`, plus `~/.claude/skills/` |

### Option A: skills CLI (installs for all three)

```bash
npx skills add Gul-Sher-Khan/latex-diff
```

When it asks which agents to install for, choose Claude Code, Codex and Cursor.

### Option B: git clone, then link

Clone once into the Claude Code folder, then link it into `~/.agents/skills` for Codex.
Cursor reads both folders.

**macOS / Linux / Git Bash**

```bash
git clone https://github.com/Gul-Sher-Khan/latex-diff.git ~/.claude/skills/latex-diff
```

```bash
mkdir -p ~/.agents/skills && ln -s ~/.claude/skills/latex-diff ~/.agents/skills/latex-diff
```

**Windows (PowerShell)**

```powershell
git clone https://github.com/Gul-Sher-Khan/latex-diff.git "$env:USERPROFILE\.claude\skills\latex-diff"
```

```powershell
New-Item -ItemType Directory -Force "$env:USERPROFILE\.agents\skills" | Out-Null; New-Item -ItemType Junction -Path "$env:USERPROFILE\.agents\skills\latex-diff" -Target "$env:USERPROFILE\.claude\skills\latex-diff"
```

A junction doesn't need admin rights. Because the folder is linked, `git pull` in one
place updates every tool.

### Project-only install

To use the skill in a single repository, clone it into that repository instead:
`.claude/skills/latex-diff` for Claude Code and Cursor, or `.agents/skills/latex-diff`
for Codex and Cursor.

### Update

```bash
git -C ~/.claude/skills/latex-diff pull
```

Restart the tool, or open a new chat, so it picks up the new skill.

## Running the script directly

The skill is a thin wrapper around one script, and you can also run that script yourself:

```bash
bash ~/.claude/skills/latex-diff/scripts/make_diff.sh OLD.zip NEW.zip -o Diff_v1xv2.pdf
```

| Option | Default |
|---|---|
| `-o, --out FILE.pdf` | `./Diff_<old>_x_<new>.pdf`. The marked-up `.tex` is written next to it |
| `--old-root` / `--new-root FILE` | Auto-detected: the top-level `.tex` file with `\documentclass`, preferring `main.tex` |
| `--engine pdflatex\|xelatex\|lualatex` | `pdflatex` |
| `--bib auto\|biber\|bibtex\|none` | `auto`: biber if the paper uses biblatex, bibtex if it uses `\bibliography{}` |
| `--docker` | Use a local TeX install if there is one, otherwise Docker |
| `--work DIR` | `<output dir>/.latexdiff-work`, recreated on every run |

When it finishes, the script prints a set of pre-compile checks (each should be 0), the
page count, the number of additions and deletions, and any LaTeX errors.

## What it does

1. Extracts both versions. If a zip has a single wrapper folder, the script goes into it.
2. Merges column specs that sit on their own line onto `\begin{tabular}` (see bug 3 below).
3. Builds the compile directory from the old files with the new files copied over them, so struck-through figures that were deleted can still render.
4. Runs `latexdiff --flatten` with the flags that work around known corruptions.
5. Repairs orphaned `\MBLOCKRIGHTBRACE` headings (bug 4).
6. Compiles: engine → biber or bibtex → engine → engine.

latexdiff can silently corrupt its output in four known ways, and each latexdiff flag
and fix script exists to prevent one of them. Don't remove any of them. Each bug, how
it shows up in the log, and the fix are described in
[references/troubleshooting.md](references/troubleshooting.md).

## Layout

```
SKILL.md                     instructions the agent follows
scripts/make_diff.sh         the pipeline
scripts/fix_colspec.py       bug 3 workaround
scripts/fix_mblock.py        bug 4 workaround
scripts/latexdiff.pl         latexdiff 1.4.1a (vendored)
scripts/perllib/Algorithm/   Algorithm::Diff (vendored)
references/troubleshooting.md
```

## License

The scripts and docs in this repo are MIT-licensed (see [LICENSE](LICENSE)). The two
vendored components keep their own licenses:

- `scripts/latexdiff.pl`: [latexdiff](https://github.com/ftilmann/latexdiff) by F. J. Tilmann, GPL-3.0-or-later.
- `scripts/perllib/Algorithm/`: [Algorithm::Diff](https://metacpan.org/pod/Algorithm::Diff), under the same terms as Perl itself (Artistic or GPL).
