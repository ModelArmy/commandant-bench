# Scope

Outstanding work, tracked in two buckets. **Completed items are deleted, not
ticked** — this file is a worklist, not a changelog. It should grow through the
early phases and dissolve as the design settles.

- **MUST FIX** — blocks progress, or is cheap now and expensive later.
- **WILL FIX** — real, but deliberately not now.

Anything settled belongs in code comments or design documentation; anything
outstanding belongs here, because nobody greps a codebase for open questions.

---

## MUST FIX

- **Use the `flags` declaration in variants** — Needed to review the corpus migration with the bench. Once rulesets declare `flags` (`BENCH_DESIGN.md` section 8.2):
  - Generate the `alias`, `long` and `abbrev` variants, which are skipped today.
  - Use `takes_value` in `reorder` and `split`, replacing the heuristics: `usermod -o -u 0` currently becomes `usermod -u -o 0`.
  - Add the combination bench (section 6) and the `combination` row origin.

---

## WILL FIX

- **Report the unrecognised-flag check** — Add the engine's undeclared tokens and baseline-default flag to `Actual` once `commandant` reports them, and show them on rule cards.

- **Lint default rules' examples** — Require `fires` examples on default rules once the corpus has migrated; today every default would fail.

- **Id convention for punctuation tools** — `id-convention` flags `posix/.#dot-executes-in-current-context`, but `dot-` is the sensible prefix for the `.` builtin. Accept a word form for tools whose names are punctuation.

- **Resolved ruleset is computed by the bench** — `Runner` mirrors the engine's lookup order to name the file a binary resolved to. Use the engine's answer once `AssessmentResponse` reports it.

- **Termify drops backticks in code spans** — Commands containing a backtick are shown with `‵` instead. Report upstream to Termify and remove the substitution once fixed.

- **Run in rules-core CI** — A workflow there that lints and reports on changed rulesets, once the corpus is clean enough to gate on.

- **Publish binaries** — Release builds for macOS, Linux and Windows, once others are invited to use the bench.

- **Web UI** — A second presentation over the same API (`BENCH_DESIGN.md` section 12).
