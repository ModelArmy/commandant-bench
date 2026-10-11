require "json"

module Commandant::Bench
  # What a row expects of the rule under review.
  enum ExpectationKind
    Fires
    DoesNotFire
    AtLeast
  end

  # A row's expectation. *severity* is set only for `AtLeast`: the verdict's
  # severity must be at least this.
  struct Expectation
    include JSON::Serializable

    getter kind : ExpectationKind
    @[JSON::Field(converter: Commandant::Severity)]
    getter severity : Commandant::Severity?

    def initialize(@kind : ExpectationKind, @severity : Commandant::Severity? = nil)
    end

    def to_s(io : IO) : Nil
      case kind
      in .fires?         then io << "fires"
      in .does_not_fire? then io << "no fire"
      in .at_least?      then io << ">= " << severity
      end
    end
  end

  enum OriginKind
    Example
    Variant
  end

  # Where a row's command came from: a hand-written example (by index), or a
  # variant of one. A variant without an example index applies to the whole rule.
  record Origin, kind : OriginKind, example_index : Int32? = nil, variant : VariantKind? = nil do
    include JSON::Serializable

    def to_s(io : IO) : Nil
      io << (variant.try(&.name) || "example")
      if index = example_index
        io << ' ' << index + 1
      end
    end
  end

  # Whether the verdict came from the ruleset's default rule.
  enum DefaultKind
    None
    Default
  end

  # What the engine actually decided for a row's command.
  #
  # *fired_rules* lists the rules that fired on the primary command only; the
  # engine does not report rules fired within compound commands.
  # *resolved_ruleset* is the ruleset file the primary binary resolved to.
  struct Actual
    include JSON::Serializable

    getter platform : TargetPlatform
    getter binary : String
    getter? tool_known : Bool
    getter ruleset_tool : String?
    getter fired_rules : Array(String)
    @[JSON::Field(converter: Commandant::Severity)]
    getter severity : Commandant::Severity
    getter default_kind : DefaultKind
    getter resolved_ruleset : String?

    def initialize(@platform, @binary, @tool_known, @ruleset_tool, @fired_rules, @severity, @default_kind, @resolved_ruleset)
    end
  end

  enum Outcome
    Ok
    Miss
    FalseAlarm
    Skipped
  end

  # One command run through the engine, with what was expected and what happened.
  # A `Skipped` row has no command or actual; *reason* says why.
  record BenchRow,
    origin : Origin,
    subject : Subject,
    outcome : Outcome,
    command : String? = nil,
    expectation : Expectation? = nil,
    actual : Actual? = nil,
    reason : String? = nil do
    include JSON::Serializable
  end
end
