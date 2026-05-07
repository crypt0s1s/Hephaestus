#!/bin/sh

set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
HOOK_INPUT="$(mktemp "${TMPDIR:-/tmp}/hephaestus-codex-stop-hook.XXXXXX")"
LINT_OUTPUT="$(mktemp "${TMPDIR:-/tmp}/hephaestus-lint-output.XXXXXX")"

cleanup() {
    rm -f "$HOOK_INPUT" "$LINT_OUTPUT"
}
trap cleanup EXIT

cat > "$HOOK_INPUT"

if /usr/bin/python3 - "$HOOK_INPUT" <<'PY'
import json
import sys

try:
    with open(sys.argv[1], "r", encoding="utf-8") as handle:
        payload = json.load(handle)
except Exception:
    payload = {}

sys.exit(0 if payload.get("stop_hook_active") else 1)
PY
then
    printf '{"continue":true,"suppressOutput":true}\n'
    exit 0
fi

if "$ROOT_DIR/scripts/lint.sh" --strict > "$LINT_OUTPUT" 2>&1; then
    printf '{"continue":true,"suppressOutput":true}\n'
    exit 0
fi

/usr/bin/python3 - "$LINT_OUTPUT" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8", errors="replace") as handle:
    output = handle.read().strip()

reason = "Project linting failed. Fix the lint issues, then stop again."
if output:
    reason += "\n\nLint output:\n" + output[-6000:]

print(json.dumps({
    "decision": "block",
    "reason": reason,
}))
PY
