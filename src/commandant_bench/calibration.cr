require "json"

module Commandant::Bench
  # A rule elsewhere in the corpus that shares risk tags with the rule under
  # review. *overlap* is the Jaccard similarity of the two tag sets, 0.0 to 1.0.
  struct SiblingRule
    include JSON::Serializable

    getter rule : RuleRef
    @[JSON::Field(converter: Commandant::Severity)]
    getter severity : Commandant::Severity
    getter reversible : String
    getter risk_tags : Array(String)
    getter overlap : Float64

    def initialize(@rule, @severity, @reversible, @risk_tags, @overlap)
    end
  end

  # How a rule's severity compares with its close siblings.
  #
  # *siblings* are the most similar rules, most similar first. *close* counts
  # siblings whose overlap is at least `CLOSE`; *usual* is the most common
  # severity among them and *usual_count* how many have it. The rule is an
  # *outlier* when it has at least `MIN_CLOSE` close siblings, at least
  # `USUAL_SHARE` of them agree on a severity, and the rule's differs. The
  # thresholds keep outliers to a shortlist rather than a census.
  struct Calibration
    include JSON::Serializable

    CLOSE       = 0.75
    USUAL_SHARE = 0.75
    MIN_CLOSE   =    5
    MAX_SHOWN   =   12

    getter siblings : Array(SiblingRule)
    getter close : Int32
    @[JSON::Field(converter: Commandant::Severity)]
    getter usual : Commandant::Severity?
    getter usual_count : Int32
    getter? outlier : Bool

    def initialize(@siblings, @close, @usual, @usual_count, @outlier)
    end
  end

  # The corpus seen as tagged rules, for calibrating one rule against the rest.
  # Default rules are compared only with default rules, and rules only with rules.
  class CalibrationIndex
    private record Entry, rule : RuleRef, tags : Set(String), severity : Commandant::Severity, reversible : String

    def initialize(rulesets : Enumerable({RulesetRef, Commandant::Ruleset}))
      @entries = [] of Entry
      rulesets.each do |ref, ruleset|
        ruleset.rules.each do |rule|
          @entries << Entry.new(RuleRef.new(ref, rule.id), rule.risk_tags.map(&.to_s).to_set, rule.severity, rule.reversible.to_s)
        end
        default = ruleset.default_rule
        @entries << Entry.new(RuleRef.default(ref), default.risk_tags.map(&.to_s).to_set, default.severity, default.reversible.to_s)
      end
    end

    def calibrate(rule : RuleRef, tags : Set(String), severity : Commandant::Severity) : Calibration
      ranked = @entries.compact_map do |entry|
        next if entry.rule == rule || entry.rule.default? != rule.default?

        overlap = jaccard(tags, entry.tags)
        next if overlap == 0.0

        {entry, overlap}
      end
      ranked.sort_by! { |(entry, overlap)| {-overlap, entry.rule.to_s} }

      close = ranked.select { |(_, overlap)| overlap >= Calibration::CLOSE }.map(&.[0])
      usual, usual_count = close.map(&.severity).tally.max_by?(&.[1]) || {nil, 0}
      outlier = close.size >= Calibration::MIN_CLOSE && !usual.nil? && usual != severity &&
                usual_count >= Calibration::USUAL_SHARE * close.size

      siblings = ranked.first(Calibration::MAX_SHOWN).map do |(entry, overlap)|
        SiblingRule.new(entry.rule, entry.severity, entry.reversible, entry.tags.to_a.sort!, overlap.round(2))
      end
      Calibration.new(siblings, close.size, usual, usual_count, outlier)
    end

    private def jaccard(a : Set(String), b : Set(String)) : Float64
      return 0.0 if a.empty? || b.empty?
      (a & b).size / (a | b).size
    end
  end
end
