require "json"

module Commandant::Bench
  # How sure a lint check is. An `Error` is a defect; `Advice` asks the
  # reviewer to look, and may be justified.
  enum LintLevel
    Error
    Advice
  end

  # The mechanical checks from the ruleset review guide, plus checks the bench
  # makes possible.
  enum LintCheck
    ToolMatchesFile
    PlatformMatchesFolder
    IdConvention
    PatternLooksLikeRegex
    EmptyMatch
    DuplicatePattern
    DependsWithoutNote
    MissingMitre
    MissingExample
    ExampleWrongBinary
    FiresOnBareCommand
    UndeclaredFlag

    def name : String
      to_s.underscore.tr("_", "-")
    end

    def to_json(json : JSON::Builder) : Nil
      json.string(name)
    end
  end

  # One lint finding. *rule_id* is nil for findings about the ruleset as a
  # whole, and `default` for the default rule.
  record LintFinding,
    ruleset : RulesetRef,
    rule_id : String?,
    field : String,
    check : LintCheck,
    level : LintLevel,
    message : String do
    include JSON::Serializable

    def location : String
      rule_id ? "#{ruleset}##{rule_id}" : ruleset.to_s
    end
  end

  # Checks one ruleset. Every check reads the ruleset alone, except
  # `FiresOnBareCommand`, which takes the engine's verdict on the bare tool.
  #
  # ```
  # findings = Lint.check(ref, ruleset, raw, bare)
  # ```
  module Lint
    REGEX_SIGNS = /\\[sSdDwWb]|\.\*|\.\+|\(\?|\[\^|\)\?|\)\*|\A\^/
    ID_FORM     = /\A[a-z0-9]+(-[a-z0-9]+)*\z/

    def self.check(ref : RulesetRef, ruleset : Commandant::Ruleset, raw : JSON::Any, bare : Actual) : Array(LintFinding)
      findings = [] of LintFinding
      add = ->(rule_id : String?, field : String, check : LintCheck, level : LintLevel, message : String) do
        findings << LintFinding.new(ref, rule_id, field, check, level, message)
        nil
      end

      check_file(ref, ruleset, add)
      raw_rules = raw["rules"].as_a
      ruleset.rules.each_with_index do |rule, index|
        check_rule(ruleset, rule, raw_rules[index]? || JSON::Any.new(nil), add)
      end
      check_default(ruleset, raw["default_rule"], add)
      check_bare(ruleset, bare, add)
      check_flags(ruleset, raw, add)
      findings
    end

    private alias Add = Proc(String?, String, LintCheck, LintLevel, String, Nil)

    private def self.check_file(ref, ruleset, add : Add) : Nil
      if ruleset.tool != ref.tool
        add.call(nil, "tool", LintCheck::ToolMatchesFile, LintLevel::Error,
          "tool is #{ruleset.tool.inspect} but the file is #{ref.tool}.json")
      end
      if ruleset.platform != ref.folder
        add.call(nil, "platform", LintCheck::PlatformMatchesFolder, LintLevel::Error,
          "platform is #{ruleset.platform.inspect} but the file is in #{ref.folder}/")
      end
    end

    private def self.check_rule(ruleset, rule, raw_rule : JSON::Any, add : Add) : Nil
      id = rule.id
      prefixes = {"#{ruleset.tool}-", "#{ruleset.tool.tr(".", "-")}-"}
      unless prefixes.any? { |prefix| id.starts_with?(prefix) } && id.matches?(ID_FORM)
        add.call(id, "id", LintCheck::IdConvention, LintLevel::Advice,
          "id should be #{ruleset.tool.tr(".", "-")}-{risk-summary}, lowercase and hyphenated")
      end

      rule.patterns.each_with_index(1) do |pattern, number|
        if pattern.pattern.matches?(REGEX_SIGNS)
          add.call(id, "patterns[#{number}].pattern", LintCheck::PatternLooksLikeRegex, LintLevel::Advice,
            "pattern looks like a regex; use Semgrep style (`...` as wildcard) and put a regex in match.raw_pattern")
        end
        if empty_match?(pattern.match)
          add.call(id, "patterns[#{number}].match", LintCheck::EmptyMatch, LintLevel::Error, "match has no criteria")
        end
      end

      matches = rule.patterns.map(&.match.to_json)
      if matches.size != matches.uniq.size
        add.call(id, "patterns", LintCheck::DuplicatePattern, LintLevel::Error, "two or more patterns have identical matches")
      end

      if rule.reversible.depends? && rule.reversible_note.nil?
        add.call(id, "reversible_note", LintCheck::DependsWithoutNote, LintLevel::Error,
          "reversible is depends but there is no reversible_note")
      end
      if raw_rule["mitre_attack"]?.nil?
        add.call(id, "mitre_attack", LintCheck::MissingMitre, LintLevel::Error, "mitre_attack is missing; use [] when none applies")
      end

      examples = Examples.read_rule(raw_rule)
      if examples.fires.empty?
        add.call(id, "examples", LintCheck::MissingExample, LintLevel::Error, "no example the rule should fire on")
      end
      (examples.fires + examples.does_not_fire).each do |example|
        first = Process.parse_arguments_posix(example).first?
        next if first == ruleset.tool || first == "#{ruleset.tool}.exe"

        add.call(id, "examples", LintCheck::ExampleWrongBinary, LintLevel::Error,
          "example #{example.inspect} runs #{first.inspect}, not #{ruleset.tool}")
      end
    end

    private def self.check_default(ruleset, raw_default : JSON::Any, add : Add) : Nil
      if raw_default["mitre_attack"]?.nil?
        add.call(RuleRef::DEFAULT, "mitre_attack", LintCheck::MissingMitre, LintLevel::Error,
          "mitre_attack is missing; use [] when none applies")
      end
      if ruleset.default_rule.reversible.depends?
        add.call(RuleRef::DEFAULT, "reversible", LintCheck::DependsWithoutNote, LintLevel::Advice,
          "the baseline is depends, and the schema gives default_rule no reversible_note to say on what")
      end
    end

    # A rule that fires on the bare tool takes the default rule's place.
    private def self.check_bare(ruleset, bare : Actual, add : Add) : Nil
      return unless bare.ruleset_tool == ruleset.tool

      bare.fired_rules.each do |rule_id|
        add.call(rule_id, "patterns", LintCheck::FiresOnBareCommand, LintLevel::Advice,
          "catch-all: fires on the bare command `#{ruleset.tool}`, so the default rule never applies; " \
          "if its severity matches the default, retire it")
      end
    end

    # Applies once a ruleset declares its flags (see BENCH_DESIGN.md section 8.2).
    private def self.check_flags(ruleset, raw : JSON::Any, add : Add) : Nil
      declared = raw["flags"]?.try(&.as_h?) || return
      known = Set(String).new
      declared.each do |flag, spec|
        known << flag
        spec["aliases"]?.try(&.as_a.each { |name| known << name.as_s })
      end

      ruleset.rules.each do |rule|
        rule.patterns.each do |pattern|
          match = pattern.match
          (match.flags_any + match.flags_all + match.flags_none).uniq.each do |flag|
            next if known.includes?(flag)

            add.call(rule.id, "match", LintCheck::UndeclaredFlag, LintLevel::Error, "flag #{flag} is not declared in flags")
          end
        end
      end
    end

    private def self.empty_match?(match : Commandant::MatchSpec) : Bool
      match.flags_any.empty? && match.flags_all.empty? && match.flags_none.empty? &&
        match.args_any.empty? && match.args_none.empty? && match.raw_pattern.nil?
    end
  end
end
