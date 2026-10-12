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
    getter reviews : ReviewStore
    @calibration_index : CalibrationIndex? = nil

    # Creates a bench over the ruleset tree at *rulesets_path*. Sign-offs are
    # kept in *reviews_path*, by default a `reviews` folder beside the tree.
    def initialize(@rulesets_path : Path, reviews_path : Path? = nil)
      @reviews = ReviewStore.new(reviews_path || @rulesets_path.parent / "reviews")
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
        findings = lint(ruleset, typed, raw, rule_runner)
        sign_offs = @reviews.read(ruleset)

        rules(ruleset).map do |ref|
          build_report(ref, typed, raw, known_flags, rule_runner, engine_runner, findings, sign_offs)
        end
      end
    end

    # Lints *ruleset*. Findings about the file as a whole have no rule id.
    def lint(ruleset : RulesetRef) : Array(LintFinding)
      typed, raw = load(ruleset)
      with_isolated_tree(ruleset) { |isolated| lint(ruleset, typed, raw, Runner.new(isolated)) }
    end

    # Lints every ruleset in the tree.
    def lint : Array(LintFinding)
      rulesets.flat_map { |ref| lint(ref) }
    end

    # Compares *rule*'s severity with rules elsewhere in the corpus that share
    # its risk tags.
    def calibration(rule : RuleRef) : Calibration
      typed, _ = load(rule.ruleset)
      calibrate(rule, typed)
    end

    # The review state of *rule*: unreviewed, approved, changes requested, or
    # lapsed because the rule changed after its sign-off.
    def status(rule : RuleRef) : ReviewStatus
      _, raw = load(rule.ruleset)
      ReviewStatus.of(@reviews.read(rule.ruleset)[rule.rule_id]?, RuleHash.of(raw, rule.rule_id))
    end

    # The review state of every rule in *ruleset*, without benching them.
    def statuses(ruleset : RulesetRef) : Array({RuleRef, ReviewStatus})
      _, raw = load(ruleset)
      sign_offs = @reviews.read(ruleset)
      rules(ruleset).map do |rule|
        {rule, ReviewStatus.of(sign_offs[rule.rule_id]?, RuleHash.of(raw, rule.rule_id))}
      end
    end

    # Records a review of the rule in *report*, replacing any earlier one, and
    # returns it. *reviewer* is a handle such as `nogginly`; a leading `@` is
    # dropped.
    def sign_off(report : RuleReport, reviewer : String, answers : Answers, note : String = "",
                 date : Time = Time.utc) : SignOff
      handle = reviewer.lchop('@')
      raise ArgumentError.new("Reviewer must be a handle, got #{reviewer.inspect}") unless handle.matches?(/\A[A-Za-z0-9][A-Za-z0-9-]*\z/)

      sign_off = SignOff.new(report.rule_hash, handle, date.to_s("%F"), report.engine_version, answers, note,
        BenchSummary.of(report))
      @reviews.write(report.rule.ruleset, report.rule.rule_id, sign_off)
      sign_off
    end

    # Assesses one ad hoc command against the full tree.
    def try(command : String, platform : TargetPlatform) : Actual
      Runner.new(@rulesets_path).run(command, platform, Process.parse_arguments_posix(command).first? || "")
    end

    private def lint(ref : RulesetRef, typed, raw, runner : Runner) : Array(LintFinding)
      Lint.check(ref, typed, raw, runner.run(typed.tool, TargetPlatform.for_folder(ref.folder), typed.tool))
    end

    private def calibrate(ref : RuleRef, typed : Commandant::Ruleset) : Calibration
      index = @calibration_index ||= CalibrationIndex.new(rulesets.map { |each_ref| {each_ref, load(each_ref)[0]} })
      rule = typed.rules.find(&.id.==(ref.rule_id))
      tags = (rule.try(&.risk_tags) || typed.default_rule.risk_tags).map(&.to_s).to_set
      index.calibrate(ref, tags, rule.try(&.severity) || typed.default_rule.severity)
    end

    private def build_report(ref, typed, raw, known_flags, rule_runner, engine_runner, findings, sign_offs) : RuleReport
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

      rule_hash = RuleHash.of(raw, ref.rule_id)
      RuleReport.new(
        rule: ref,
        rule_hash: rule_hash,
        description: rule.try(&.description) || "Default rule: applies when no other rule fires.",
        severity: severity,
        reversible: (rule.try(&.reversible) || typed.default_rule.reversible).to_s,
        risk_tags: (rule.try(&.risk_tags) || typed.default_rule.risk_tags).map(&.to_s),
        notes: rule.try(&.notes),
        examples_from_patterns: examples.from_patterns,
        engine_version: Commandant::Version::VERSION,
        rows: rows,
        lint: findings.select(&.rule_id.==(ref.rule_id)),
        calibration: calibrate(ref, typed),
        review: ReviewStatus.of(sign_offs[ref.rule_id]?, rule_hash),
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
