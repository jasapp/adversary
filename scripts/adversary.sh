#!/usr/bin/env bash
# adversary.sh: run a hostile, read-only review of stdin using a model from
# another provider, via a nested Claude Code session.
#
# Usage: ... | adversary.sh [--mode critic|rebuttal] [--model ID] [--dry-run] [--allow-secrets]
#
#   --dry-run        print exactly what would be sent, then exit. Nothing leaves the machine.
#   --allow-secrets  skip the credential check on the material.
#
# Environment (all optional when MOONSHOT_API_KEY is set, or ~/.config/moonshot/env exists):
#   ADVERSARY_BASE_URL      Anthropic-compatible endpoint. Default: Moonshot.
#   ADVERSARY_AUTH_TOKEN    Bearer token. Default: $MOONSHOT_API_KEY.
#   ADVERSARY_MODEL         Main model. Default: kimi-k3.1-pro.
#   ADVERSARY_FAST_MODEL    Model for the "haiku" slot. Default: kimi-k3.1-pro-highspeed.
#   ADVERSARY_CONTEXT       Context window to assume. Default: 1000000.
#   ADVERSARY_MAX_TURNS     Tool-use turns allowed. Default: 40.
#
# Known limit: the nested session is read-only by tool allow-list, not by a
# sandbox. A model that really wanted to could write a file with
# `git diff --output=PATH`. This guards against accidents, not a hostile repo.

set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mode=critic
model="${ADVERSARY_MODEL:-kimi-k3.1-pro}"
allow_secrets=0
dry_run=0

while [ $# -gt 0 ]; do
  case "$1" in
    --mode) mode="$2"; shift 2 ;;
    --model) model="$2"; shift 2 ;;
    --allow-secrets) allow_secrets=1; shift ;;
    --dry-run) dry_run=1; shift ;;
    -h|--help) sed -n '2,/^set -/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "adversary: unknown option $1" >&2; exit 2 ;;
  esac
done

case "$mode" in critic|rebuttal) ;; *) echo "adversary: mode must be critic or rebuttal" >&2; exit 2 ;; esac

base_url="${ADVERSARY_BASE_URL:-https://api.moonshot.ai/anthropic}"
keyfile="$HOME/.config/moonshot/env"
# If the key is not in the environment (Claude Code launched from a desktop
# launcher, say), fall back to the conventional file.
if [ -z "${ADVERSARY_AUTH_TOKEN:-}" ] && [ -z "${MOONSHOT_API_KEY:-}" ] && [ -r "$keyfile" ]; then
  # shellcheck disable=SC1091
  . "$keyfile"
fi
token="${ADVERSARY_AUTH_TOKEN:-${MOONSHOT_API_KEY:-}}"
if [ -z "$token" ] && [ "$dry_run" -eq 0 ]; then
  echo "adversary: no token. Set MOONSHOT_API_KEY, or ADVERSARY_AUTH_TOKEN and ADVERSARY_BASE_URL." >&2
  exit 1
fi
command -v claude >/dev/null || { echo "adversary: claude CLI not on PATH" >&2; exit 1; }

material="$(cat)"
if [ -z "$material" ]; then
  echo "adversary: nothing on stdin" >&2
  exit 1
fi

# Refuse to ship anything that looks like a credential to a third party.
# grep -c reads all of stdin, so pipefail cannot hide a match behind a broken pipe.
# The diagnostic prints line numbers only, never the matched text.
if [ "$allow_secrets" -eq 0 ]; then
  secret_re='(sk-[A-Za-z0-9_-]{16,}|AKIA[0-9A-Z]{16}|ghp_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|xox[baprs]-[A-Za-z0-9-]{10,}|AIza[0-9A-Za-z_-]{30,}|-----BEGIN [A-Z ]*PRIVATE KEY-----|(password|passwd|pwd|secret|api[_-]?key|access[_-]?key|auth[_-]?token|token|private[_-]?key|client[_-]?secret|bearer)[A-Za-z0-9_]*[[:space:]]*[:=][[:space:]]*["'"'"']?[A-Za-z0-9/+_.-]{12,})'
  hits="$(printf '%s' "$material" | grep -ciE "$secret_re" || true)"
  if [ "${hits:-0}" -gt 0 ]; then
    lines="$(printf '%s' "$material" | grep -niE "$secret_re" | cut -d: -f1 | head -5 | paste -sd, -)"
    echo "adversary: material looks like it contains a secret (line $lines). Remove it, or pass --allow-secrets." >&2
    exit 3
  fi
fi

prompt="$(cat "$here/prompts/$mode.md")"
fast="${ADVERSARY_FAST_MODEL:-kimi-k3.1-pro-highspeed}"

if [ "$dry_run" -eq 1 ]; then
  printf '%s\n\n---\n\n%s\n' "$prompt" "$material"
  exit 0
fi

# Redact the token if it ever appears in the nested session's output.
esc_token="$(printf '%s' "$token" | sed 's/[][\/.*^$|&]/\\&/g')"
redact() { sed -u "s/$esc_token/[REDACTED]/g"; }

# Nested Claude Code, locked down as far as the CLI allows:
#   --tools            only these tools exist in the session at all
#   --setting-sources  no user/project settings, so no inherited allow rules or hooks
#   --disallowedTools  deny reading the key file even though Read is allowed
#   -p                 non-interactive: anything not allow-listed is denied, not prompted
# Env: CLAUDECODE unset so nesting is allowed; ANTHROPIC_API_KEY and the
# Bedrock/Vertex switches unset so nothing can override the endpoint; git's
# external helpers and pager neutralised so allowed git commands stay read-only.
printf '%s\n\n---\n\n%s\n' "$prompt" "$material" | env \
  -u CLAUDECODE -u ANTHROPIC_API_KEY -u CLAUDE_CODE_SUBAGENT_MODEL \
  -u CLAUDE_CODE_USE_BEDROCK -u CLAUDE_CODE_USE_VERTEX -u CLAUDE_CODE_USE_FOUNDRY \
  -u GIT_EXTERNAL_DIFF -u GIT_PAGER -u GIT_DIR -u GIT_WORK_TREE \
  GIT_CONFIG_COUNT=3 \
  GIT_CONFIG_KEY_0=diff.external GIT_CONFIG_VALUE_0= \
  GIT_CONFIG_KEY_1=core.pager    GIT_CONFIG_VALUE_1=cat \
  GIT_CONFIG_KEY_2=pager.diff    GIT_CONFIG_VALUE_2=false \
  ANTHROPIC_BASE_URL="$base_url" \
  ANTHROPIC_AUTH_TOKEN="$token" \
  ANTHROPIC_MODEL="$model" \
  ANTHROPIC_DEFAULT_OPUS_MODEL="$model" \
  ANTHROPIC_DEFAULT_SONNET_MODEL="$model" \
  ANTHROPIC_DEFAULT_FABLE_MODEL="$model" \
  ANTHROPIC_DEFAULT_HAIKU_MODEL="$fast" \
  CLAUDE_CODE_AUTO_COMPACT_WINDOW="${ADVERSARY_CONTEXT:-1000000}" \
  claude -p \
    --model "$model" \
    --max-turns "${ADVERSARY_MAX_TURNS:-40}" \
    --output-format text \
    --setting-sources "" \
    --tools "Read" "Glob" "Grep" "Bash" \
    --allowedTools "Read" "Glob" "Grep" "Bash(git diff:*)" "Bash(git log:*)" "Bash(git show:*)" "Bash(git blame:*)" \
    --disallowedTools "Read(~/.config/moonshot/**)" "Read(//$HOME/.config/moonshot/**)" "Edit" "Write" "NotebookEdit" "WebFetch" "WebSearch" "Agent" "Task" \
  2> >(grep -vE 'connectors are disabled|context window of 200k|unrecognized_model' | redact >&2) \
  | redact
