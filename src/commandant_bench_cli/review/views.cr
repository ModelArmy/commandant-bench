require "../../commandant_bench"

# Builds the Markdown for each screen of a review session. Every method is a
# pure function of bench results, so views are testable without a terminal.
module Commandant::Bench::CLI::Review::Views
  OUTCOME_LABELS = {
    Outcome::Ok         => "ok",
    Outcome::Miss       => "**MISS**",
    Outcome::FalseAlarm => "**FALSE ALARM**",
    Outcome::Skipped    => "skipped",
  }

  # Stands in for a backtick inside a command, which a code span cannot show.
  BACKTICK_STANDIN = '‵'

  HELP = <<-MD
    | Command | Does |
    |---|---|
    | `list [TEXT]` | List rulesets, or only those whose name contains TEXT |
    | `open N` or `open REF` | Open ruleset N from the last list, or a ruleset or rule by name |
    | `N` | Open rule N of the open ruleset |
    | *Enter* or `next` | Next rule |
    | `prev` | Previous rule |
    | `rules` | Back to the open ruleset's rules |
    | `problems` | Show only misses and false alarms, or everything again |
    | `siblings` | Rules elsewhere that share the open rule's risk tags |
    | `try COMMAND` | Assess one command against the full tree |
    | `platform NAME` | Platform for `try`: linux, macos, windows-cmd, windows-powershell |
    | `help` | Show this help |
    | `quit` | Leave |
    MD

  def self.welcome(rulesets_path : Path, count : Int32) : String
    <<-MD
      # commandant-bench review

      #{count} rulesets under `#{rulesets_path}`. Type `list` to see them, or `help` for commands.
      MD
  end

  def self.ruleset_list(entries : Array({RulesetRef, Int32}), filter : String?) : String
    return "No rulesets match `#{filter}`." if entries.empty?

    String.build do |io|
      io << "| # | Ruleset | Rules |\n|--:|---|--:|\n"
      entries.each_with_index(1) do |(ref, rules), number|
        io << "| " << number << " | " << ref << " | " << rules << " |\n"
      end
    end
  end

  def self.ruleset_summary(ruleset : RulesetRef, reports : Array(RuleReport), findings : Array(LintFinding)) : String
    String.build do |io|
      io << "## " << ruleset << "\n\n"
      io << "| # | Rule | Severity | ok | miss | false alarm | skipped | lint | calibration |\n"
      io << "|--:|---|---|--:|--:|--:|--:|--:|---|\n"
      reports.each_with_index(1) do |report, number|
        io << "| " << number << " | " << report.rule.rule_id << " | " << report.severity
        {Outcome::Ok, Outcome::Miss, Outcome::FalseAlarm, Outcome::Skipped}.each do |outcome|
          count = report.count(outcome)
          problem = count > 0 && (outcome.miss? || outcome.false_alarm?)
          io << " | " << (problem ? "**#{count}**" : count)
        end
        io << " | " << report.lint.size << " | " << (report.calibration.outlier? ? "**outlier**" : "") << " |\n"
      end
      io << "\n"
      lint_list(findings.select(&.rule_id.nil?), io)
      io << "Type a rule number, or press Enter to start at the first rule."
    end
  end

  def self.rule_card(report : RuleReport, position : Int32, total : Int32, problems_only : Bool) : String
    String.build do |io|
      io << "## " << report.rule << " · " << report.severity << " · " << position << "/" << total << "\n\n"
      io << report.description << "\n\n"
      io << "Reversible: " << report.reversible
      io << " · Risk tags: " << (report.risk_tags.empty? ? "none" : report.risk_tags.join(", ")) << "\n\n"
      if notes = report.notes
        io << "> **Notes:** " << notes << "\n\n"
      end
      io << calibration(report) << "\n\n"
      lint_list(report.lint, io)
      io << "*Examples taken from pattern `example` fields.*\n\n" if report.examples_from_patterns?

      run = report.rows.reject(&.outcome.skipped?)
      shown = problems_only ? run.select { |row| row.outcome.miss? || row.outcome.false_alarm? } : run
      if shown.empty?
        io << (problems_only ? "No misses or false alarms." : "No rows were run.") << "\n\n"
      else
        rows_table(shown, io)
      end

      skipped(report.rows.select(&.outcome.skipped?), io)
      io << summary(report)
      io << " · showing problems only" if problems_only
    end
  end

  def self.siblings(report : RuleReport) : String
    siblings = report.calibration.siblings
    return "#{report.rule} has no siblings: no other rule shares its risk tags." if siblings.empty?

    String.build do |io|
      io << "## Siblings of " << report.rule << " · " << report.severity << "\n\n"
      io << calibration(report) << "\n\n"
      io << "| Rule | Severity | Reversible | Overlap | Risk tags |\n|---|---|---|--:|---|\n"
      siblings.each do |sibling|
        io << "| " << sibling.rule << " | " << sibling.severity << " | " << sibling.reversible
        io << " | " << sibling.overlap << " | " << sibling.risk_tags.join(", ") << " |\n"
      end
    end
  end

  def self.calibration(report : RuleReport) : String
    calibration = report.calibration
    usual = calibration.usual
    return "Calibration: fewer than #{Calibration::MIN_CLOSE} close siblings." if usual.nil? || calibration.close < Calibration::MIN_CLOSE

    text = "Calibration: #{calibration.usual_count} of #{calibration.close} close siblings are #{usual}"
    calibration.outlier? ? "#{text}; this rule is #{report.severity}: **outlier**" : text
  end

  def self.lint_list(findings : Array(LintFinding), io : IO) : Nil
    return if findings.empty?

    io << "Lint:\n\n"
    findings.each do |finding|
      io << "- " << (finding.level.error? ? "**error**" : "advice") << " " << finding.check.name
      io << " (" << finding.field << "): " << finding.message << "\n"
    end
    io << "\n"
  end

  def self.actual(command : String, actual : Actual) : String
    ruleset = actual.resolved_ruleset || "none (unknown tool #{code(actual.binary)})"
    <<-MD
      | Command | #{code(command)} |
      |---|---|
      | Platform | #{actual.platform.name} |
      | Ruleset | #{ruleset} |
      | Severity | #{actual.severity} |
      | Fired | #{fired(actual)} |
      MD
  end

  def self.error(message : String) : String
    "**Error:** #{message}"
  end

  # Wraps *text* in a code span, safe inside a table cell.
  def self.code(text : String) : String
    "`#{text.tr("`", BACKTICK_STANDIN.to_s).gsub("|", "\\|")}`"
  end

  private def self.rows_table(rows : Array(BenchRow), io : IO) : Nil
    io << "| Outcome | Subject | Origin | Expect | Command | Actual |\n|---|---|---|---|---|---|\n"
    rows.each do |row|
      io << "| " << OUTCOME_LABELS[row.outcome] << " | " << row.subject.to_s.downcase << " | " << row.origin
      io << " | " << row.expectation << " | " << code(row.command || "")
      io << " | " << row.actual.try { |actual| "#{actual.severity} #{fired(actual)}" } << " |\n"
    end
    io << "\n"
  end

  private def self.skipped(rows : Array(BenchRow), io : IO) : Nil
    return if rows.empty?

    io << "Skipped:\n\n"
    rows.group_by(&.reason).each do |reason, group|
      io << "- " << group.map(&.origin.to_s).join(", ") << ": " << reason << "\n"
    end
    io << "\n"
  end

  private def self.summary(report : RuleReport) : String
    "#{report.rows.size} rows: #{report.count(Outcome::Ok)} ok, #{report.count(Outcome::Miss)} miss, " \
    "#{report.count(Outcome::FalseAlarm)} false alarm, #{report.count(Outcome::Skipped)} skipped"
  end

  private def self.fired(actual : Actual) : String
    if !actual.tool_known?
      "unknown tool #{code(actual.binary)}"
    elsif actual.default_kind.default?
      "default (#{actual.binary})"
    else
      actual.fired_rules.join(", ")
    end
  end
end
