require "json"

module Commandant::Bench
  # A rule's hand-written example commands.
  #
  # *from_patterns* is true when the rule has no `examples` field and the
  # examples were taken from its patterns' `example` fields instead.
  record Examples, fires : Array(String), does_not_fire : Array(String), from_patterns : Bool do
    include JSON::Serializable

    # Reads the examples for *rule_id* from a ruleset's raw JSON. Rules and the
    # default rule may carry:
    #
    # ```json
    # "examples": { "fires": ["rm -rf build/"], "does_not_fire": ["rm -f notes.txt"] }
    # ```
    def self.read(raw : JSON::Any, rule_id : String) : Examples
      rule = if rule_id == RuleRef::DEFAULT
               raw["default_rule"]
             else
               raw["rules"].as_a.find { |candidate| candidate["id"].as_s == rule_id }
             end
      raise NotFoundError.new("No rule #{rule_id.inspect}") unless rule

      if examples = rule["examples"]?
        new(strings(examples["fires"]?), strings(examples["does_not_fire"]?), false)
      else
        patterns = rule["patterns"]?.try(&.as_a) || [] of JSON::Any
        new(patterns.compact_map(&.["example"]?.try(&.as_s)).uniq!, [] of String, !patterns.empty?)
      end
    end

    private def self.strings(value : JSON::Any?) : Array(String)
      value.try(&.as_a.map(&.as_s)) || [] of String
    end
  end
end
