# commandant-bench

Review bench for [`commandant`](https://github.com/ModelArmy/commandant.cr) rulesets. It runs each rule against its examples, generated variants and flag combinations through the real engine, so a reviewer judges what a rule *does* rather than reading its JSON.

> **WARNING**: This shard is a work in progress and in development until this warning is removed.

> See [DISCLOSURE](./DISCLOSURE.md) for information how AI is used by this project.

## What it is for

A ruleset reviewer has four questions per rule: is it true, does it catch the right commands, is its severity consistent with similar rules, and do its notes admit its gaps. The bench answers the mechanical parts of those questions so the reviewer spends attention only on judgement.

For example, a reviewer looking at `rm-recursive-force` sees a table like this (illustrative) instead of a regex:

```
                                    expected  actual
  rm -rf build/                     match     ERROR    ok
  rm -Rf build/            [case]   match     INFO     MISS
  rm -f notes.txt                   no match  INFO     ok
```

## Usage

Build the binary (see [DEVELOPMENT.md](./DEVELOPMENT.md)), then point it at a ruleset tree with `--rulesets` or `RULESETS_PATH`:

```sh
export RULESETS_PATH=../commandant-rules-core/rulesets
commandant-bench list                                  # ruleset files and rule counts
commandant-bench report posix/rm#rm-recursive-force    # bench one rule
commandant-bench report posix/rm                       # bench every rule, including #default
commandant-bench report posix/rm --json                # the same, as JSON
commandant-bench try 'FOO=1 rm -rf build/'             # assess one command
commandant-bench review posix/rm                       # review interactively
commandant-bench lint                                  # lint the tree; exits 1 on errors
commandant-bench status posix/rm                       # review state of each rule
```

`review` is an interactive session that asks and scrolls: open a ruleset, press Enter to step through its rules, `problems` to see only misses and false alarms, `try` to check a hunch, `siblings` to compare a rule's severity with rules sharing its risk tags. `signoff` asks the four review questions and records the answers in `reviews/`, beside the ruleset tree; editing the rule later marks the review as lapsed. Set your handle once with `git config --global github.user HANDLE`. Type `help` inside it for all commands. On a terminal it renders Markdown with [Termify](https://github.com/nogginly/termify.cr); when piped, or with `--plain`, it writes the Markdown as text.

From Crystal, use `Commandant::Bench::Workbench`; see [BENCH_DESIGN.md](./BENCH_DESIGN.md) for the API.

## License

[MPL-2.0](./LICENSE)
