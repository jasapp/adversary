#!/usr/bin/env bash
# adversary.sh: run a hostile, read-only review of stdin using a model from
# another provider, via a nested Claude Code session.
#
# Usage: ... | adversary.sh [--mode critic|rebuttal] [--model ID] [--allow-secrets]
#
# Environment (all optional when MOONSHOT_API_KEY is set):
#   ADVERSARY_BASE_URL      Anthropic-compatible endpoint. Default: Moonshot.
#   ADVERSARY_AUTH_TOKEN    Bearer token. Default: $MOONSHOT_API_KEY.
#   ADVERSARY_MODEL         Main model. Default: kimi-k3.1-pro.
#   ADVERSARY_FAST_MODEL    Model for the "haiku" slot. Default: kimi-k3.1-pro-highspeed.
#   ADVERSARY_CONTEXT       Context window to assume. Default: 1000000.
#   ADVERSARY_MAX_TURNS     Tool-use turns allowed. Default: 40.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mode=critic
model="${ADVERSARY_MODEL:-kimi-k3.1-pro}"
allow_secrets=0

while [ $# -gt 0 ]; do
  case "$1" in
    --mode) mode="$2"; shift 2 ;;
    --model) model="$2"; shift 2 ;;
    --allow-secrets) allow_secrets=1; shift ;;
    -h|--help) sed -n '2,15p' "$0"; exit 0 ;;
    *) echo "adversary: unknown option $1" >&2; exit 2 ;;
  esac
done

case "$mode" in critic|rebuttal) ;; *) echo "adversary: mode must be critic or rebuttal" >&2; exit 2 ;; esac

base_url="${ADVERSARY_BASE_URL:-https://api.moonshot.ai/anthropic}"
token="${ADVERSARY_AUTH_TOKEN:-${MOONSHOT_API_KEY:-}}"
if [ -z "$token" ]; then
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
if [ "$allow_secrets" -eq 0 ]; then
  secret_re='(sk-[A-Za-z0-9_-]{16,}|AKIA[0-9A-Z]{16}|ghp_[A-Za-z0-9]{20,}|xox[baprs]-[A-Za-z0-9-]{10,}|-----BEGIN [A-Z ]*PRIVATE KEY-----|(password|passwd|secret|api[_-]?key|token)\s*[:=]\s*["'"'"']?[A-Za-z0-9/+_-]{12,})'
  if printf '%s' "$material" | grep -qiE "$secret_re"; then
    echo "adversary: material looks like it contains a secret. Remove it, or pass --allow-secrets." >&2
    printf '%s' "$material" | grep -niE "$secret_re" | cut -c1-80 | sed 's/^/  line /' >&2
    exit 3
  fi
fi

prompt="$(cat "$here/prompts/$mode.md")"
fast="${ADVERSARY_FAST_MODEL:-kimi-k3.1-pro-highspeed}"

# Nested Claude Code: different provider, read-only tools, no interactive prompts.
# CLAUDECODE is unset so the nested session does not refuse to start.
# ANTHROPIC_API_KEY is unset so it cannot silently win over the auth token.
printf '%s\n\n---\n\n%s\n' "$prompt" "$material" | env \
  -u CLAUDECODE -u ANTHROPIC_API_KEY -u CLAUDE_CODE_SUBAGENT_MODEL \
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
    --allowedTools "Read" "Glob" "Grep" "Bash(git diff:*)" "Bash(git log:*)" "Bash(git show:*)" "Bash(git blame:*)" \
  2> >(grep -vE 'connectors are disabled|context window of 200k|unrecognized_model' >&2)
