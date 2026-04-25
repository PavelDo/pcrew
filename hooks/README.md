# Hooks

Schema-valid Claude Code hook configurations that drop into the user's
`~/.claude/settings.json`. Each hook here has been verified against the
current Claude Code hook schema — common mistakes (e.g. using
`hookSpecificOutput.additionalContext` on a `Stop` hook, where the schema
only allows it on `UserPromptSubmit` and `PostToolUse`) are pre-corrected.

## `stop-session-learning.json` — session-end memory check

A `Stop` hook that prompts the assistant to do a one-shot memory-update
pass before the session ends. Captures user preferences, workflow lessons,
and bug patterns into the persistent memory system so future sessions
benefit. Self-gates with a `/tmp/claude-stop-learning-${CLAUDE_SESSION_ID}`
sentinel so it fires exactly once per session — without that, the
`decision: "block"` payload would loop forever.

### Why a `Stop` hook needs this exact shape

The schema for `Stop` accepts these top-level fields:

```
continue, suppressOutput, stopReason, decision, reason, systemMessage
```

It does **not** accept `hookSpecificOutput` for the `Stop` event — that key
is reserved for `PreToolUse`, `UserPromptSubmit`, and `PostToolUse`. To
re-prompt the assistant from a `Stop` hook, you must emit:

```json
{"decision": "block", "reason": "<the prompt for the assistant>"}
```

The fragment in this directory does that, plus the sentinel guard so it
fires exactly once per session.

### Install

```bash
# Idempotent. Backs up the existing settings.json (timestamped) before writing.
bash hooks/install-stop-hook.sh

# Preview what would change without writing:
bash hooks/install-stop-hook.sh --dry-run

# Roll back the most recent install:
bash hooks/install-stop-hook.sh --revert
```

The installer leaves all other top-level keys in `settings.json` untouched.

### Uninstall

```bash
# Either revert to a timestamped backup:
bash hooks/install-stop-hook.sh --revert

# Or hand-edit and remove the "Stop" entry under "hooks".
```

### Customization

The reason string lives in `stop-session-learning.json`. Edit it there
and re-run the installer; the installer overwrites the old `Stop` block
in your settings (and re-backs up first).

If you want the hook to fire on a different signal — e.g. only after long
sessions, only on certain projects — wrap the inner shell `if` in a
project-detection clause before the `touch "$SENTINEL"` line.
