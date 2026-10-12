require "json"

module Commandant::Bench
  # The bench's findings for one rule.
  struct RuleReport
    include JSON::Serializable

    getter rule : RuleRef
    getter rule_hash : String
    getter description : String
    @[JSON::Field(converter: Commandant::Severity)]
    getter severity : Commandant::Severity
    getter reversible : String
    getter risk_tags : Array(String)
    getter notes : String?
    getter? examples_from_patterns : Bool
    getter engine_version : String
    getter rows : Array(BenchRow)
    getter lint : Array(LintFinding)
    getter calibration : Calibration
    getter review : ReviewStatus

    def initialize(@rule, @rule_hash, @description, @severity, @reversible, @risk_tags, @notes,
                   @examples_from_patterns, @engine_version, @rows, @lint, @calibration, @review)
    end

    # A copy of this report with *review* in place of its review status.
    def with_review(review : ReviewStatus) : RuleReport
      RuleReport.new(@rule, @rule_hash, @description, @severity, @reversible, @risk_tags, @notes,
        @examples_from_patterns, @engine_version, @rows, @lint, @calibration, review)
    end

    def count(outcome : Outcome) : Int32
      rows.count(&.outcome.==(outcome))
    end

    # True when no row is a miss or a false alarm. Skipped rows do not count.
    def clean? : Bool
      count(Outcome::Miss) == 0 && count(Outcome::FalseAlarm) == 0
    end
  end
end
