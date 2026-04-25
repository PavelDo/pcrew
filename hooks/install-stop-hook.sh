#!/usr/bin/env bash
# Idempotently install the session-learning Stop hook into ~/.claude/settings.json.
#
# Why this exists:
#   Claude Code's Stop hook does NOT accept `hookSpecificOutput.additionalContext`
#   (that field is only valid on UserPromptSubmit and PostToolUse). The valid way
#   to re-prompt the assistant at session end is `decision: "block"` + `reason: "..."`.
#   Without a sentinel, `block` re-fires on every Stop attempt and creates a loop;
#   we gate on /tmp/claude-stop-learning-${CLAUDE_SESSION_ID} so it fires once per session.
#
# Behavior:
#   - Backs up the current settings.json (timestamped).
#   - Replaces (or inserts) the Stop hook with the validated schema-compliant version.
#   - Other top-level keys in settings.json are left untouched.
#   - Idempotent — running twice produces the same result.
#
# Usage:
#   bash hooks/install-stop-hook.sh           # install / update
#   bash hooks/install-stop-hook.sh --dry-run # show what would change, write nothing
#   bash hooks/install-stop-hook.sh --revert  # restore from the most recent backup
set -euo pipefail

SETTINGS="${CLAUDE_SETTINGS_PATH:-$HOME/.claude/settings.json}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_FRAG="$SCRIPT_DIR/stop-session-learning.json"

if [ ! -f "$HOOK_FRAG" ]; then
  echo "error: hook fragment not found at $HOOK_FRAG" >&2
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "error: python3 is required" >&2
  exit 1
fi

case "${1:-install}" in
  --dry-run)
    MODE=dry
    ;;
  --revert)
    LATEST_BACKUP=$(ls -t "$SETTINGS".bak-* 2>/dev/null | head -1 || true)
    if [ -z "$LATEST_BACKUP" ]; then
      echo "no backup found at $SETTINGS.bak-*" >&2
      exit 1
    fi
    cp -p "$LATEST_BACKUP" "$SETTINGS"
    echo "reverted $SETTINGS from $LATEST_BACKUP"
    exit 0
    ;;
  install|"")
    MODE=install
    ;;
  *)
    echo "usage: $0 [install|--dry-run|--revert]" >&2
    exit 2
    ;;
esac

if [ ! -f "$SETTINGS" ]; then
  echo "settings file does not exist: $SETTINGS" >&2
  echo "creating an empty one with just the Stop hook." >&2
  mkdir -p "$(dirname "$SETTINGS")"
  echo '{}' > "$SETTINGS"
fi

python3 - "$SETTINGS" "$HOOK_FRAG" "$MODE" <<'PY'
import json, sys, shutil, datetime, pathlib

settings_path = pathlib.Path(sys.argv[1])
frag_path = pathlib.Path(sys.argv[2])
mode = sys.argv[3]

settings = json.loads(settings_path.read_text() or "{}")
frag = json.loads(frag_path.read_text())

# Strip out the human-readable _comment from the fragment (we only ship the Stop block).
new_stop = frag["Stop"]

current = settings.get("hooks", {}).get("Stop")
if current == new_stop:
    print(f"no change: Stop hook already matches fragment in {settings_path}")
    sys.exit(0)

if mode == "dry":
    print("--- dry-run: would write the following Stop hook ---")
    print(json.dumps(new_stop, indent=2))
    print(f"target: {settings_path}")
    sys.exit(0)

backup = settings_path.with_suffix(
    settings_path.suffix + ".bak-" + datetime.datetime.now().strftime("%Y%m%d%H%M%S")
)
shutil.copy2(settings_path, backup)

settings.setdefault("hooks", {})
settings["hooks"]["Stop"] = new_stop
settings_path.write_text(json.dumps(settings, indent=2) + "\n")
print(f"installed Stop hook to {settings_path}")
print(f"backup at {backup}")
PY
