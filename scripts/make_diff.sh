#!/usr/bin/env bash
# Build a change-marked PDF (latexdiff) between two versions of a LaTeX project.
#
#   bash make_diff.sh OLD NEW [options]
#
# OLD / NEW   an Overleaf .zip export or a project directory.
#
# Options:
#   -o, --out FILE.pdf   output PDF (default: ./Diff_<old>_x_<new>.pdf).
#                        The marked-up source is written next to it as FILE.tex.
#   --old-root FILE      root .tex inside OLD (default: auto-detected)
#   --new-root FILE      root .tex inside NEW (default: auto-detected)
#   --engine NAME        pdflatex (default) | xelatex | lualatex
#   --bib TOOL           auto (default) | biber | bibtex | none
#   --docker             compile in Docker even if a local TeX install exists
#   --work DIR           scratch directory (default: <out dir>/.latexdiff-work)
#
# The latexdiff flags and the two fix scripts are load-bearing: each one works
# around a diagnosed latexdiff corruption. See references/troubleshooting.md.
set -euo pipefail

SCRIPTS="$(cd "$(dirname "$0")" && pwd)"
TEXLIVE_IMAGE="${TEXLIVE_IMAGE:-texlive/texlive:latest}"

die() { echo "ERROR: $*" >&2; exit 1; }

OLD="" NEW="" OUT="" OLDROOT="" NEWROOT="" ENGINE="pdflatex" BIB="auto" FORCE_DOCKER=0 WORK=""
while [ $# -gt 0 ]; do
  case "$1" in
    -o|--out)    OUT="$2"; shift 2 ;;
    --old-root)  OLDROOT="$2"; shift 2 ;;
    --new-root)  NEWROOT="$2"; shift 2 ;;
    --engine)    ENGINE="$2"; shift 2 ;;
    --bib)       BIB="$2"; shift 2 ;;
    --docker)    FORCE_DOCKER=1; shift ;;
    --work)      WORK="$2"; shift 2 ;;
    -h|--help)   sed -n '2,20p' "$0"; exit 0 ;;
    -*)          die "unknown option $1" ;;
    *)           if [ -z "$OLD" ]; then OLD="$1"; elif [ -z "$NEW" ]; then NEW="$1"; else die "too many arguments"; fi; shift ;;
  esac
done
[ -n "$OLD" ] && [ -n "$NEW" ] || die "usage: make_diff.sh OLD NEW [-o out.pdf] (see --help)"
[ -e "$OLD" ] || die "not found: $OLD"
[ -e "$NEW" ] || die "not found: $NEW"

# --- tools ------------------------------------------------------------------
PY=""
for c in python3 python; do
  if command -v "$c" >/dev/null 2>&1 && "$c" -c 'import sys; sys.exit(sys.version_info[0] < 3)' 2>/dev/null; then PY="$c"; break; fi
done
[ -n "$PY" ] || die "Python 3 not found"
command -v perl >/dev/null 2>&1 || die "perl not found (on Windows, run this from Git Bash)"

USE_DOCKER=1
if [ "$FORCE_DOCKER" = 0 ] && command -v "$ENGINE" >/dev/null 2>&1; then USE_DOCKER=0; fi
if [ "$USE_DOCKER" = 1 ]; then
  command -v docker >/dev/null 2>&1 || die "no local $ENGINE and no docker. Install Docker Desktop or TeX Live."
  docker info >/dev/null 2>&1 || die "Docker is not running. Start Docker Desktop and wait until 'docker run --rm hello-world' works."
fi

# --- paths ------------------------------------------------------------------
stem() { local b; b="$(basename "$1")"; b="${b%.zip}"; echo "$b" | tr -c 'A-Za-z0-9._\n-' '_'; }
[ -n "$OUT" ] || OUT="Diff_$(stem "$OLD")_x_$(stem "$NEW").pdf"
case "$OUT" in *.pdf) ;; *) OUT="$OUT.pdf" ;; esac
OUTDIR="$(cd "$(dirname "$OUT")" && pwd)"
OUT="$OUTDIR/$(basename "$OUT")"
OUTTEX="${OUT%.pdf}.tex"
[ -n "$WORK" ] || WORK="$OUTDIR/.latexdiff-work"
mkdir -p "$WORK"
WORK="$(cd "$WORK" && pwd)"
rm -rf "$WORK/old" "$WORK/new" "$WORK/build"
mkdir -p "$WORK/old" "$WORK/new" "$WORK/build"

# --- 1. extract -------------------------------------------------------------
# Unpack (or copy) into $dest; if the result is a single wrapper directory,
# use its contents instead.
unpack() {
  local src="$1" dest="$2"
  if [ -d "$src" ]; then cp -r "$src/." "$dest/"
  else "$PY" -m zipfile -e "$src" "$dest" || die "cannot unzip $src"; fi
  local entries; entries="$(ls -A "$dest")"
  if [ "$(echo "$entries" | wc -l)" -eq 1 ] && [ -d "$dest/$entries" ]; then
    local inner="$dest/$entries"
    mv "$inner" "$dest.tmp" && rmdir "$dest" && mv "$dest.tmp" "$dest"
  fi
}
unpack "$OLD" "$WORK/old"
unpack "$NEW" "$WORK/new"

# Root = top-level .tex with \documentclass, ignoring stale diff/flatten output.
find_root() {
  local dir="$1" c
  local cands
  cands="$(cd "$dir" && grep -l '^[[:space:]]*\\documentclass' ./*.tex 2>/dev/null \
           | sed 's|^\./||' | grep -viE '^(diff[0-9]*|.*_flat|.*latexdiff.*)\.tex$' || true)"
  [ -n "$cands" ] || return 1
  if [ "$(echo "$cands" | wc -l)" -eq 1 ]; then echo "$cands"; return; fi
  for c in main.tex template.tex paper.tex manuscript.tex; do
    echo "$cands" | grep -qx "$c" && { echo "$c"; return; }
  done
  echo "AMBIGUOUS:$(echo "$cands" | tr '\n' ' ')"
}
if [ -z "$OLDROOT" ]; then OLDROOT="$(find_root "$WORK/old")" || die "no root .tex (with \\documentclass) in $OLD; pass --old-root"; fi
if [ -z "$NEWROOT" ]; then NEWROOT="$(find_root "$WORK/new")" || die "no root .tex (with \\documentclass) in $NEW; pass --new-root"; fi
case "$OLDROOT" in AMBIGUOUS:*) die "several root candidates in OLD: ${OLDROOT#AMBIGUOUS:}-- pass --old-root" ;; esac
case "$NEWROOT" in AMBIGUOUS:*) die "several root candidates in NEW: ${NEWROOT#AMBIGUOUS:}-- pass --new-root" ;; esac
[ -f "$WORK/old/$OLDROOT" ] || die "old root not found: $OLDROOT"
[ -f "$WORK/new/$NEWROOT" ] || die "new root not found: $NEWROOT"
echo "OLD: $OLD  (root $OLDROOT)"
echo "NEW: $NEW  (root $NEWROOT)"

# --- 2. column-spec workaround (bug 3), both trees ----------------------------
"$PY" "$SCRIPTS/fix_colspec.py" "$WORK/old" "$WORK/new"

# --- 3. build dir: old assets overlaid by new, so deleted figures still exist --
cp -r "$WORK/old/." "$WORK/build/"
cp -r "$WORK/new/." "$WORK/build/"
NEWDIR="$(dirname "$NEWROOT")"
BUILD="$WORK/build/$NEWDIR"
JOB=ldiff
rm -f "$BUILD/$JOB".*

# --- 4. latexdiff (flags are load-bearing: bugs 1 and 2) ----------------------
if ! perl -I "$SCRIPTS/perllib" "$SCRIPTS/latexdiff.pl" --flatten \
    --exclude-textcmd="textit" \
    --append-safecmd="textit" \
    --exclude-safecmd="textsuperscript" \
    "$WORK/old/$OLDROOT" "$WORK/new/$NEWROOT" \
    > "$BUILD/$JOB.tex" 2> "$WORK/latexdiff.log"; then
  tail -20 "$WORK/latexdiff.log" >&2
  die "latexdiff failed (full log: $WORK/latexdiff.log)"
fi

# --- 5. heading-brace workaround (bug 4); no-op when not needed ---------------
"$PY" "$SCRIPTS/fix_mblock.py" "$BUILD/$JOB.tex"

# --- 6. pre-compile checks (all should be 0) ----------------------------------
echo "checks (all should be 0):"
echo "  'DIFaddFL{|p}' (bug 3): $(grep -c 'DIFaddFL{|p}' "$BUILD/$JOB.tex" || true)"
echo "  'MBLOCK' (bug 4): $(grep -c 'MBLOCK' "$BUILD/$JOB.tex" || true)"
# Bug 1 leaves "\DIFadd{word}}" with no opening command; "\texttt{\DIFadd{x}}" is fine.
echo "  dropped brace (bug 1): $(perl -ne '$n++ if /(?<!\{)\\DIFadd\{[a-z]*\}\}/; END { print $n+0 }' "$BUILD/$JOB.tex")"
echo "  headings hidden in comments: $(grep -c '%DIFDELCMD <.*\(sub\)*section{' "$BUILD/$JOB.tex" || true)"

# --- 7. compile ---------------------------------------------------------------
if [ "$BIB" = auto ]; then
  if grep -qE '\\usepackage(\[[^]]*\])?\{biblatex\}|\\addbibresource' "$BUILD/$JOB.tex"; then
    if grep -qE 'backend[[:space:]]*=[[:space:]]*bibtex' "$BUILD/$JOB.tex"; then BIB=bibtex; else BIB=biber; fi
  elif grep -qE '\\bibliography\{' "$BUILD/$JOB.tex"; then BIB=bibtex
  else BIB=none; fi
fi
echo "compile: $ENGINE + $BIB ($([ "$USE_DOCKER" = 1 ] && echo "docker $TEXLIVE_IMAGE" || echo local))"

cat > "$BUILD/compile_ldiff.sh" <<EOF
run() { $ENGINE -interaction=nonstopmode -file-line-error $JOB.tex >/dev/null 2>&1 || true; }
run
case "$BIB" in
  biber)  biber $JOB > $JOB.bibtool.log 2>&1 || true ;;
  bibtex) bibtex $JOB > $JOB.bibtool.log 2>&1 || true ;;
esac
run
run
EOF

if [ "$USE_DOCKER" = 1 ]; then
  HOSTDIR="$(cd "$BUILD" && (pwd -W 2>/dev/null || pwd))"
  MSYS_NO_PATHCONV=1 docker run --rm -v "$HOSTDIR:/work" -w /work "$TEXLIVE_IMAGE" sh compile_ldiff.sh
else
  (cd "$BUILD" && sh compile_ldiff.sh)
fi

[ -f "$BUILD/$JOB.pdf" ] || { grep -E '^[^ ]+:[0-9]+: ' "$BUILD/$JOB.log" | head -20 >&2 || true; die "no PDF produced (log: $BUILD/$JOB.log)"; }

# --- 8. report ---------------------------------------------------------------
cp "$BUILD/$JOB.pdf" "$OUT"
cp "$BUILD/$JOB.tex" "$OUTTEX"
echo
echo "$(grep -o 'Output written on .*' "$BUILD/$JOB.log" || echo 'Output written: (not found in log)')"
echo "changes: $(grep -o '\\DIFaddbegin' "$OUTTEX" | wc -l | tr -d ' ') additions / $(grep -o '\\DIFdelbegin' "$OUTTEX" | wc -l | tr -d ' ') deletions"
NERR=$(grep -cE '^[^ ]+:[0-9]+: ' "$BUILD/$JOB.log" || true)
echo "LaTeX errors in log: $NERR"
if [ "$NERR" -gt 0 ]; then grep -E '^[^ ]+:[0-9]+: ' "$BUILD/$JOB.log" | sed 's|^.*/||' | sort | uniq -c | sort -rn | head -15; fi
echo "undefined references/citations: $(grep -cE '(Reference|Citation) .* undefined' "$BUILD/$JOB.log" || true)"
disp() { cygpath -m "$1" 2>/dev/null || echo "$1"; }
echo
echo "Wrote $(disp "$OUT")"
echo "Wrote $(disp "$OUTTEX")"
echo "Build dir (logs, aux): $(disp "$BUILD")"
