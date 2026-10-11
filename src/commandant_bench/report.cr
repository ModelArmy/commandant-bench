require "json"

module Commandant::Bench
  # The bench's findings for one rule.
  struct RuleReport
    include JSON::Serializable

    getter rule : RuleRef
    getter description : String
    @[JSON::Field(converter: Commandant::Severity)]
    getter severity : Commandant::Severity
    getter reversible : String
    getter risk_tags : Array(String)
    getter notes : String?
    getter? examples_from_patterns : Bool
    getter engine_version : String
    getter rows : Array(BenchRow)

    def initialize(@rule, @description, @severity, @reversible, @risk_tags, @notes,
                   @examples_from_patterns, @engine_version, @rows)
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
