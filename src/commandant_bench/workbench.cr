require "json"
require "file_utils"
require "random/secure"

module Commandant::Bench
  # The bench API: reports on rules in a ruleset tree, and ad hoc assessments.
  #
  # ```
  # bench = Commandant::Bench::Workbench.new(Path["../commandant-rules-core/rulesets"])
  # report = bench.report(Commandant::Bench::RuleRef.parse("posix/rm#rm-recursive-force"))
  # report.rows.each { |row| puts "#{row.outcome} #{row.command}" }
  # ```
  #
  # Rows whose subject is the rule are assessed against a tree holding only the
  # ruleset under review, so platform-specific files cannot shadow it. Rows
  # whose subject is the engine are assessed against the full tree.
  class Workbench
    getter rulesets_path : Path

    def initialize(@rulesets_path : Path)
    end

    # All ruleset files in the tree, sorted by folder then tool.
    def rulesets : Array(RulesetRef)
      raise NotFoundError.new("No ruleset tree at #{@rulesets_path}") unless Dir.exists?(@rulesets_path.to_s)

      refs = [] of RulesetRef
      Dir.each_child(@rulesets_path.to_s) do |folder|
        folder_path = @rulesets_path / folder
        next unless Dir.exists?(folder_path.to_s)

        Dir.each_child(folder_path.to_s) do |file|
          refs << RulesetRef.new(folder, File.basename(file, ".json")) if file.ends_with?(".json")
        end
      end
      refs.sort_by! { |ref| {ref.folder, ref.tool} }
    end

    # The rule references in *ruleset*: each rule in file order, then `default`.
    def rules(ruleset : RulesetRef) : Array(RuleRef)
      load(ruleset)[0].rules.map { |rule| RuleRef.new(ruleset, rule.id) } << RuleRef.default(ruleset)
    end

    # Benches one rule.
    def report(rule : RuleRef) : RuleReport
      report(rule.ruleset).find(&.rule.==(rule)) || raise NotFoundError.new("No rule #{rule}")
    end

    # Benches every rule in *ruleset*, including the default rule.
    def report(ruleset : RulesetRef) : Array(RuleReport)
      typed, raw = load(ruleset)
      known_flags = known_flags(typed)

      with_isolated_tree(ruleset) do |isolated|
        rule_runner = Runner.new(isolated)
        engine_runner = Runner.new(@rulesets_path)

        rules(ruleset).map do |ref|
          build_report(ref, typed, raw, known_flags, rule_runner, engine_runner)
        end
      end
    end

    # Assesses one ad hoc command against the full tree.
    def try(command : String, platform : TargetPlatform) : Actual
      Runner.new(@rulesets_path).run(command, platform, Process.parse_arguments_posix(command).first? || "")
    end

    private def build_report(ref, typed, raw, known_flags, rule_runner, engine_runner) : RuleReport
      rule = typed.rules.find(&.id.==(ref.rule_id))
      severity = rule.try(&.severity) || typed.default_rule.severity
      examples = Examples.read(raw, ref.rule_id)
      context = RowContext.new(ref, typed.tool, severity, rule_runner, engine_runner)

      rows = [] of BenchRow
      examples.fires.each_with_index do |example, index|
        rows << context.example_row(example, index, ExpectationKind::Fires)
      end
      examples.does_not_fire.each_with_index do |example, index|
        rows << context.example_row(example, index, ExpectationKind::DoesNotFire)
      end
      examples.fires.each_with_index do |example, index|
        Variants.generate(example, typed.tool, ref.ruleset.folder, known_flags).each do |variant|
          rows << context.variant_row(variant, index)
        end
      end
      VariantKind.values.select(&.needs_flag_declaration?).each do |kind|
        rows << BenchRow.new(
          origin: Origin.new(OriginKind::Variant, variant: kind),
          subject: kind.subject,
          outcome: Outcome::Skipped,
          reason: "needs a flag declaration",
        )
      end
      if examples.fires.empty?
        rows.unshift BenchRow.new(
          origin: Origin.new(OriginKind::Example),
          subject: Subject::Rule,
          outcome: Outcome::Skipped,
          reason: "rule has no examples that should fire",
        )
      end

      RuleReport.new(
        rule: ref,
        description: rule.try(&.description) || "Default rule: applies when no other rule fires.",
        severity: severity,
        examples_from_patterns: examples.from_patterns,
        engine_version: Commandant::Version::VERSION,
        rows: rows,
      )
    end

    private def load(ruleset : RulesetRef) : {Commandant::Ruleset, JSON::Any}
      path = ruleset.path(@rulesets_path)
      raise NotFoundError.new("No ruleset #{ruleset} under #{@rulesets_path}") unless File.exists?(path.to_s)

      text = File.read(path.to_s)
      {Commandant::Ruleset.from_json(text), JSON.parse(text)}
    end

    # Flags the ruleset mentions in any match or abbreviation.
    private def known_flags(ruleset : Commandant::Ruleset) : Set(String)
      flags = Set(String).new
      ruleset.rules.each do |rule|
        rule.patterns.each do |pattern|
          flags.concat(pattern.match.flags_any)
          flags.concat(pattern.match.flags_all)
          flags.concat(pattern.match.flags_none)
        end
      end
      ruleset.option_abbreviations.each { |short, long| flags << short << long }
      flags
    end

    private def with_isolated_tree(ruleset : RulesetRef, &)
      root = Path[Dir.tempdir] / "commandant-bench-#{Random::Secure.hex(8)}"
      Dir.mkdir_p((root / ruleset.folder).to_s)
      File.copy(ruleset.path(@rulesets_path).to_s, ruleset.path(root).to_s)
      yield root
    ensure
      FileUtils.rm_rf(root.to_s) if root
    end
  end

  # Builds rows for one rule: runs commands and judges their outcome.
  private struct RowContext
    def initialize(@rule : RuleRef, @tool : String, @severity : Commandant::Severity,
                   @rule_runner : Runner, @engine_runner : Runner)
    end

    def example_row(command : String, index : Int32, kind : ExpectationKind) : BenchRow
      platform = TargetPlatform.for_folder(@rule.ruleset.folder)
      run(command, platform, Origin.new(OriginKind::Example, index), Subject::Rule, Expectation.new(kind))
    end

    def variant_row(variant : Variant, index : Int32) : BenchRow
      origin = Origin.new(OriginKind::Variant, index, variant.kind)
      subject = variant.kind.subject
      command = variant.command
      unless command
        return BenchRow.new(origin: origin, subject: subject, outcome: Outcome::Skipped, reason: variant.reason)
      end

      expectation = if variant.kind.at_least?
                      Expectation.new(ExpectationKind::AtLeast, @severity)
                    else
                      Expectation.new(ExpectationKind::Fires)
                    end
      run(command, variant.platform, origin, subject, expectation)
    end

    private def run(command, platform, origin, subject, expectation) : BenchRow
      runner = subject.rule? ? @rule_runner : @engine_runner
      actual = runner.run(command, platform, @tool)
      BenchRow.new(
        origin: origin,
        subject: subject,
        outcome: judge(expectation, actual),
        command: command,
        expectation: expectation,
        actual: actual,
      )
    end

    # A row checks whether this rule fired, not only the final severity, so
    # another rule's verdict cannot hide this rule's miss.
    private def judge(expectation : Expectation, actual : Actual) : Outcome
      case expectation.kind
      in .fires?         then fired?(actual) ? Outcome::Ok : Outcome::Miss
      in .does_not_fire? then fired?(actual) ? Outcome::FalseAlarm : Outcome::Ok
      in .at_least?
        minimum = expectation.severity || @severity
        actual.severity.value >= minimum.value ? Outcome::Ok : Outcome::Miss
      end
    end

    private def fired?(actual : Actual) : Bool
      if @rule.default?
        actual.default_kind.default? && actual.binary == @tool
      else
        actual.ruleset_tool == @tool && actual.fired_rules.includes?(@rule.rule_id)
      end
    end
  end
end
