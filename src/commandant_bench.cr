require "commandant"
require "./commandant_bench/error"
require "./commandant_bench/refs"
require "./commandant_bench/target_platform"
require "./commandant_bench/variants"
require "./commandant_bench/row"
require "./commandant_bench/examples"
require "./commandant_bench/runner"
require "./commandant_bench/lint"
require "./commandant_bench/calibration"
require "./commandant_bench/sign_off"
require "./commandant_bench/report"
require "./commandant_bench/workbench"

# Review bench for `commandant` rulesets.
#
# The bench runs a rule's examples and generated variants through the real
# `commandant` engine and returns plain, JSON-serialisable results. Presentation
# layers (CLI, TUI, web, CI) consume these results and hold no review logic of
# their own. Start with `Commandant::Bench::Workbench`; see `BENCH_DESIGN.md`.
module Commandant::Bench
  VERSION    = {{ `shards version #{__DIR__}`.chomp.stringify }}
  PRERELEASE = VERSION.match(/^\d+\.\d+\.\d+$/).nil?
end
