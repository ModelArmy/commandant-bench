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

The library API and the `commandant-bench` binary are under construction; see [BENCH_DESIGN.md](./BENCH_DESIGN.md) for the planned API and [DEVELOPMENT.md](./DEVELOPMENT.md) to build it.

## License

[MPL-2.0](./LICENSE)
