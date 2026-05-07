#!/bin/sh

set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SWIFTLINT_BIN="${SWIFTLINT_BIN:-swiftlint}"

usage() {
    cat <<'USAGE'
Usage: scripts/lint.sh [--all] [--strict] [--fix] [--quiet]

Runs the project Swift linter using the repo-level .swiftlint.yml.
By default, only changed Swift files are linted. Use --all for a full-project lint.

Options:
  --all     Lint every Swift file included by .swiftlint.yml.
  --strict  Treat warnings as failures.
  --fix     Apply SwiftLint autocorrections where available.
  --quiet   Reduce linter output.

Environment:
  SWIFTLINT_BIN  Path to a SwiftLint executable. Defaults to "swiftlint".
USAGE
}

STRICT=0
FIX=0
QUIET=0
ALL=0

while [ "$#" -gt 0 ]; do
    case "$1" in
        --all)
            ALL=1
            ;;
        --strict)
            STRICT=1
            ;;
        --fix)
            FIX=1
            ;;
        --quiet)
            QUIET=1
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            echo "Unknown lint option: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
    shift
done

if ! command -v "$SWIFTLINT_BIN" >/dev/null 2>&1; then
    cat >&2 <<'ERROR'
SwiftLint is required to run project linting, but it was not found on PATH.

Install SwiftLint, or set SWIFTLINT_BIN to the executable path, then retry:
  SWIFTLINT_BIN=/path/to/swiftlint scripts/lint.sh
ERROR
    exit 127
fi

CHANGED_FILES="$(mktemp "${TMPDIR:-/tmp}/hephaestus-swiftlint-files.XXXXXX")"
cleanup() {
    rm -f "$CHANGED_FILES"
}
trap cleanup EXIT

if [ "$ALL" -eq 0 ]; then
    cd "$ROOT_DIR"
    {
        git diff --name-only --diff-filter=ACMR
        git diff --cached --name-only --diff-filter=ACMR
        git ls-files --others --exclude-standard
    } | sort -u | grep '\.swift$' > "$CHANGED_FILES" || true

    if [ ! -s "$CHANGED_FILES" ]; then
        if [ "$QUIET" -eq 0 ]; then
            echo "No changed Swift files to lint."
        fi
        exit 0
    fi
fi

set -- lint --config "$ROOT_DIR/.swiftlint.yml" --force-exclude

if [ -f "$ROOT_DIR/.swiftlint-baseline.json" ]; then
    set -- "$@" --baseline "$ROOT_DIR/.swiftlint-baseline.json"
fi

if [ "$STRICT" -eq 1 ]; then
    set -- "$@" --strict
fi

if [ "$QUIET" -eq 1 ]; then
    set -- "$@" --quiet
fi

if [ "$FIX" -eq 1 ]; then
    set -- --fix --config "$ROOT_DIR/.swiftlint.yml" --force-exclude
    if [ "$QUIET" -eq 1 ]; then
        set -- "$@" --quiet
    fi
fi

cd "$ROOT_DIR"
if [ "$ALL" -eq 0 ]; then
    while IFS= read -r file; do
        [ -f "$file" ] || continue
        set -- "$@" "$file"
    done < "$CHANGED_FILES"
fi

exec "$SWIFTLINT_BIN" "$@"
