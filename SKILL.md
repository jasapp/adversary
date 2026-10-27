---
name: adversary
description: Get a hostile second opinion from a different model (Kimi K3.1 Pro via Moonshot by default) on a diff, plan, or file, then verify every claim before reporting. Use when the user says /adversary, "red team this", "poke holes", "second opinion", "what would another model say", or wants a change attacked before it ships.
---

# Adversary

Send work to a model from a different lab and have it attack the work. Then
verify each attack against the real code before repeating any of it. The other
model is the prosecutor. You are the judge. Nothing it says reaches the user
unverified.

## Prerequisites

- `scripts/adversary.sh` next to this file.
- `MOONSHOT_API_KEY` in the environment, or `ADVERSARY_AUTH_TOKEN` plus
  `ADVERSARY_BASE_URL` for another Anthropic-compatible endpoint. See README.
- The `claude` CLI on PATH. The script runs a nested, read-only Claude Code
  session pointed at the other provider.

If the key is missing, say so and stop. Do not ask the user to paste it in chat.
Tell them to put it in `~/.config/moonshot/env` or export it in their shell.

## Procedure

1. **Pick the target.** In order of precedence:
   - An explicit argument: a file path, a commit or range, or the word `plan`.
   - `plan` means the most recent plan or design in this conversation. Write it
     out in full as the material; the other model cannot see this chat.
   - No argument: the working tree diff (`git diff HEAD`, including staged). If
     that is empty, the branch diff against the merge-base with the default
     branch. If that is empty too, ask what to review.
2. **Write the brief.** The critic needs to know what the change is supposed to
   do, or it will only find style nits. Two to five lines: the goal, any
   constraints the user stated, what "correct" means here. Pull this from the
   conversation, commit messages, or the issue. Put it under a `## Intent`
   heading above the material.
3. **Run round one.** From the repo root so the critic can read surrounding code:
   ```
   printf '%s\n' "$BRIEF" "$MATERIAL" | <skill-dir>/scripts/adversary.sh
   ```
   The script refuses material that looks like it contains a secret. If it
   refuses, remove the secret from the material and run again. Do not pass
   `--allow-secrets` unless the user says to.
4. **Verify every finding yourself.** For each one, open the code at the cited
   location and decide:
   - **Confirmed**: you reproduced the failure or traced the logic to it.
   - **Plausible**: you could not rule it out but could not confirm it either.
   - **Rejected**: it is wrong, and you can say exactly why in one sentence.
   Do not skip this step to save time. The point of the skill is a second model
   with different blind spots, and that only works if someone checks its work.
5. **Run round two when anything was rejected.** Send the original findings and
   your verdicts back with `--mode rebuttal`. The critic may concede or push
   back with new evidence. Re-verify anything it pushes back on. Two rounds is
   the limit. If you still disagree after that, report the disagreement as
   plausible, with both positions in one line each.
6. **Report.** Surviving findings first, ordered by severity, as a short table:
   severity, location, one-line claim, your verdict. Then one line per rejected
   finding saying why, so the user can see what was filtered. Then anything the
   critic said it could not verify. No praise, no restatement of what the code
   does. If nothing survived, say that in one sentence.

## Scope rules

- The nested session is read-only. It can read files and run `git diff`, `git
  log`, `git show`, and `git blame`. It cannot edit, run tests, or hit the
  network. If a finding needs a test run to settle, you run the test.
- The material leaves the machine and goes to the provider. Say so the first
  time in a session. Skip the skill for diffs holding customer data or
  credentials, even redacted ones, unless the user explicitly accepts that.
- One target per run. Big diffs get split by concern, not by file count.
- Round one on a typical diff costs a few cents. Do not loop beyond two rounds.
