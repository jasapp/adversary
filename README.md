# adversary

A Claude Code skill that gets a hostile second opinion from a model built by a
different lab, then makes Claude verify every claim before you see it.

The default critic is Kimi K3.1 Pro through Moonshot's API. The point is not
that Kimi is better. It was trained differently, so it has different blind
spots. A second model that disagrees with Claude is worth more than a second
copy of Claude.

## How it works

`/adversary` takes a diff, a file, or the plan Claude just proposed, writes a
short brief about what the change is meant to do, and pipes both to
`scripts/adversary.sh`. That script starts a nested, read-only Claude Code
session pointed at the other provider. The critic can read your repo and run
`git diff`, `git log`, `git show`, and `git blame`. It cannot edit, run tests,
or touch the network.

The critic returns numbered findings with file and line citations. Claude then
opens each one and marks it confirmed, plausible, or rejected. Anything
rejected goes back for one rebuttal round. You get the survivors, ordered by
severity, plus one line per rejected finding so you can see what was filtered.

## Install

Needs the `claude` CLI and a Moonshot API key from
[platform.kimi.ai](https://platform.kimi.ai). Pay-as-you-go. A review of a
typical diff costs a few cents.

```sh
git clone https://github.com/jasapp/adversary ~/src/adversary
ln -s ~/src/adversary ~/.claude/skills/adversary
```

Put the key somewhere your shell loads. Not in the repo.

```sh
mkdir -p ~/.config/moonshot && chmod 700 ~/.config/moonshot
echo "export MOONSHOT_API_KEY='sk-...'" > ~/.config/moonshot/env
chmod 600 ~/.config/moonshot/env
echo '[ -f ~/.config/moonshot/env ] && . ~/.config/moonshot/env' >> ~/.bashrc
```

Open a new shell, start Claude Code, type `/adversary`.

## Use

```
/adversary              review the working tree diff, or the branch if clean
/adversary plan         attack the plan Claude just proposed
/adversary src/foo.py   attack one file
/adversary HEAD~3..     attack a commit range
```

## Other providers

Any endpoint that speaks the Anthropic Messages API works. Set these instead of
`MOONSHOT_API_KEY`:

```sh
export ADVERSARY_BASE_URL=https://ollama.com       # Ollama cloud, for example
export ADVERSARY_AUTH_TOKEN="$OLLAMA_API_KEY"
export ADVERSARY_MODEL=kimi-k3:cloud
export ADVERSARY_FAST_MODEL=kimi-k3:cloud
```

## Privacy

Whatever you review leaves your machine and goes to the provider. The script
refuses material that looks like it contains a credential. It is a regex, not a
guarantee. Do not point it at diffs holding customer data.

## Files

- `SKILL.md`: what Claude does when you type `/adversary`.
- `scripts/adversary.sh`: runs the nested session. Usable on its own: `git diff | scripts/adversary.sh`.
- `prompts/critic.md`: the round-one stance.
- `prompts/rebuttal.md`: the round-two stance.

## License

MIT.
