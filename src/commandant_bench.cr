require "commandant"

# Review bench for `commandant` rulesets.
#
# The bench runs a rule's examples, generated variants and flag combinations
# through the real `commandant` engine and returns plain, JSON-serialisable
# results. Presentation layers (TUI, web, CI) consume these results and hold
# no review logic of their own. See `BENCH_DESIGN.md`.
module Commandant::Bench
  VERSION    = {{ `shards version #{__DIR__}`.chomp.stringify }}
  PRERELEASE = VERSION.match(/^\d+\.\d+\.\d+$/).nil?
end
