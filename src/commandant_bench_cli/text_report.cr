require "../commandant_bench"

# Renders bench results as plain text for the terminal.
module Commandant::Bench::CLI::TextReport
  LABELS = {
    Outcome::Ok         => "ok",
    Outcome::Miss       => "MISS",
    Outcome::FalseAlarm => "FALSE ALARM",
    Outcome::Skipped    => "skipped",
  }

  # Writes *report* as a header, a table of run rows, the skipped rows with
  # their reasons, and a one-line summary.
  def self.render(report : RuleReport, io : IO) : Nil
    io.puts "#{report.rule}  #{report.severity}"
    io.puts "  #{report.description}"
    io.puts "  (examples taken from pattern `example` fields)" if report.examples_from_patterns?
    io.puts

    run, skipped = report.rows.partition { |row| !row.outcome.skipped? }
    render_table(run, io) unless run.empty?

    unless skipped.empty?
      io.puts
      io.puts "  Skipped:"
      skipped.each { |row| io.puts "    #{row.origin.to_s.ljust(14)} #{row.reason}" }
    end

    io.puts
    io.puts "  #{report.rows.size} rows: #{report.count(Outcome::Ok)} ok, #{report.count(Outcome::Miss)} miss, " \
            "#{report.count(Outcome::FalseAlarm)} false alarm, #{report.count(Outcome::Skipped)} skipped"
  end

  # Writes one ad hoc assessment.
  def self.render(command : String, actual : Actual, io : IO) : Nil
    io.puts command
    io.puts "  platform:  #{actual.platform.name}"
    io.puts "  ruleset:   #{actual.resolved_ruleset || "none (unknown tool #{actual.binary.inspect})"}"
    io.puts "  severity:  #{actual.severity}"
    io.puts "  fired:     #{describe_fired(actual)}"
  end

  private def self.render_table(rows : Array(BenchRow), io : IO) : Nil
    command_width = rows.max_of { |row| row.command.try(&.size) || 0 }
    io.puts "  #{"OUTCOME".ljust(11)} #{"SUBJECT".ljust(7)} #{"ORIGIN".ljust(14)} #{"EXPECT".ljust(10)} " \
            "#{"COMMAND".ljust(command_width)}  ACTUAL"
    rows.each do |row|
      io.puts "  #{LABELS[row.outcome].ljust(11)} #{row.subject.to_s.downcase.ljust(7)} " \
              "#{row.origin.to_s.ljust(14)} #{row.expectation.to_s.ljust(10)} " \
              "#{(row.command || "").ljust(command_width)}  #{row.actual.try { |actual| describe(actual) }}"
    end
  end

  private def self.describe(actual : Actual) : String
    "#{actual.severity} #{describe_fired(actual)}"
  end

  private def self.describe_fired(actual : Actual) : String
    if !actual.tool_known?
      "unknown tool #{actual.binary.inspect}"
    elsif actual.default_kind.default?
      "default (#{actual.binary})"
    else
      actual.fired_rules.join(", ")
    end
  end
end
