# Development Guide

This document explains how to build `commandant-bench` and how the code is organised. The design of the bench itself, including its API and result types, is in [BENCH_DESIGN.md](./BENCH_DESIGN.md).

## Dependencies

1. Make sure you have `ops` installed, in one of the following ways:
    - as a gem via `gem install ops_team` or
    - as a tool via `brew tap nickthecook/crops && brew install ops`
2. If you are not using macOS, or a Linux that uses `apt`, please [install Crystal](https://crystal-lang.org/install/)
3. On Linux, install the `libxml2` development package (for example `apt install libxml2-dev`). Termify's syntax highlighter links against it; macOS and the Windows Crystal distribution already provide it.
4. Clone [`commandant-rules-core`](https://github.com/ModelArmy/commandant-rules-core) next to this repo, or set `RULESETS_PATH` to its `rulesets/` folder.

## Getting started

Command                        |Description                                         
-------------------------------|----------------------------------------------------
`ops up`                       |Installs shards and builds `ameba`                  
`ops build-debug` or `ops bd`  |Debug build of `commandant-bench` in `bin/debug`    
`ops build-release` or `ops br`|Release build of `commandant-bench` in `bin/release`
`ops test`                     |Runs specs, a debug build and the linter            
`ops lint`                     |Runs `ameba` on the source code                     
`ops clean`                    |Removes debug and release build files               
`ops wipe`                     |In addition to cleaning, removes all compiler caches

## Code layout

The core, in `src/commandant_bench/`:

File                 |Contents                                                     
---------------------|-------------------------------------------------------------
`workbench.cr`       |`Workbench`, the API entry point, and row judging            
`runner.cr`          |Runs one command through a fresh `Commandant::Assessor`      
`variants.cr`        |`VariantKind` and the variant generator                      
`examples.cr`        |Reads a rule's examples from ruleset JSON                    
`lint.cr`            |`Lint` checks and `LintFinding`                              
`calibration.cr`     |`CalibrationIndex`: siblings and outliers by shared risk tags
`sign_off.cr`        |Sign-off types, `RuleHash` and the `ReviewStore`             
`row.cr`, `report.cr`|Result types                                                 
`refs.cr`            |`RulesetRef` and `RuleRef`                                   
`target_platform.cr` |Platforms and shells a command can be assessed on            

The presentation, in `src/commandant_bench_cli/`:

File               |Contents                                          
-------------------|--------------------------------------------------
`cli.cr`           |Argument parsing and subcommand dispatch          
`text_report.cr`   |Plain-text rendering for `report` and `try`       
`review/session.cr`|The interactive `review` loop and its commands    
`review/views.cr`  |Markdown for each review screen, as pure functions
`review/display.cr`|Terminal (Termify) and plain displays             

The repository:

Path                       |Contents                                                                  
---------------------------|--------------------------------------------------------------------------
`src/commandant_bench.cr`  |Library entry point; requires every bench component                       
`src/commandant_bench/`    |Bench core and its API: operations and JSON-serialisable result types     
`src/commandant_bench_cli/`|`Commandant::Bench::CLI`: argument parsing and presentation for the binary
`src/bench_main.cr`        |Executable entry point; calls `CLI.run(ARGV)` and exits                   
`spec/`                    |Specs, using the Crystal standard library `spec`                          
`spec/fixtures/rulesets/`  |A small ruleset tree; `zap` has deliberately brittle and wrong rules      
`spec/fixtures/lint/`      |`bait`, a ruleset where each rule breaks one lint check                   

### Presentation stays outside the core

Everything under `src/commandant_bench/` returns plain data and never writes to a terminal. The CLI, the TUI and any later web UI are clients of the same API. A change that needs the core to know about colours, layout or keypresses belongs in a presentation layer instead.

### Why the executable entry point is a separate file

`CLI.run` has no top-level side effects, so specs can `require` it and call it in-process. `src/bench_main.cr` is the only file that calls `exit`; requiring it from a spec would end the spec run.
