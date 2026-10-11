require "./spec_helper"

private def bench : Commandant::Bench::Workbench
  Commandant::Bench::Workbench.new(RULESETS_PATH)
end

private def report(ref : String) : Commandant::Bench::RuleReport
  bench.report(Commandant::Bench::RuleRef.parse(ref))
end

private def row(report, origin : String) : Commandant::Bench::BenchRow
  report.rows.find! { |candidate| candidate.origin.to_s == origin }
end

private alias Outcome = Commandant::Bench::Outcome

describe Commandant::Bench::Workbench do
  it "lists ruleset files sorted by folder then tool" do
    bench.rulesets.map(&.to_s).should eq(%w[linux/zap posix/ls posix/sh posix/sudo posix/zap])
  end

  it "lists rules in file order, then the default rule" do
    refs = bench.rules(Commandant::Bench::RulesetRef.parse("posix/zap")).map(&.rule_id)
    refs.should eq(%w[zap-recursive-force zap-recursive-raw zap-force default])
  end

  it "raises NotFoundError for a missing ruleset or rule" do
    expect_raises(Commandant::Bench::NotFoundError) { report("posix/nope#x") }
    expect_raises(Commandant::Bench::NotFoundError) { report("posix/zap#nope") }
  end

  describe "examples" do
    it "takes examples from patterns when the rule has none of its own" do
      result = report("posix/zap#zap-recursive-force")
      result.examples_from_patterns?.should be_true
      row(result, "example 1").outcome.should eq(Outcome::Ok)
    end

    it "reads the examples field, including commands that should not fire" do
      result = report("posix/zap#zap-force")
      result.examples_from_patterns?.should be_false
      outcomes = result.rows.select(&.expectation.try(&.kind.does_not_fire?)).map(&.outcome)
      outcomes.should eq([Outcome::Ok, Outcome::FalseAlarm])
    end

    it "benches the default rule from its own examples" do
      result = report("posix/zap#default")
      result.rows.select(&.origin.kind.example?).map(&.outcome).should eq([Outcome::Ok, Outcome::Ok])
    end

    it "reports a rule without examples as skipped rather than clean" do
      result = bench.report(Commandant::Bench::RuleRef.default(Commandant::Bench::RulesetRef.parse("posix/ls")))
      result.rows.first.reason.should eq("rule has no examples that should fire")
    end
  end

  describe "variants" do
    it "finds the misses of a brittle raw pattern" do
      result = report("posix/zap#zap-recursive-raw")
      row(result, "example 1").outcome.should eq(Outcome::Ok)
      row(result, "reorder 1").outcome.should eq(Outcome::Miss)
      row(result, "combine 1").outcome.should eq(Outcome::Miss)
    end

    it "lists kinds that need a flag declaration as skipped" do
      result = report("posix/zap#zap-recursive-force")
      %w[alias long abbrev].each { |kind| row(result, kind).outcome.should eq(Outcome::Skipped) }
    end

    it "judges wrapper variants by severity" do
      sudo = row(report("posix/zap#zap-recursive-force"), "sudo 1")
      sudo.expectation.try(&.kind.at_least?).should be_true
      sudo.outcome.should eq(Outcome::Ok)
    end
  end

  describe "isolation" do
    it "benches rule rows against the file under review, even when a platform file would shadow it" do
      result = report("posix/zap#zap-recursive-force")
      split = row(result, "split 1")
      split.subject.rule?.should be_true
      split.outcome.should eq(Outcome::Ok)
    end

    it "benches engine rows against the full tree and names the file that resolved" do
      quote = row(report("posix/zap#zap-recursive-force"), "quote 1")
      quote.subject.engine?.should be_true
      quote.actual.try(&.resolved_ruleset).should eq("linux/zap")
      quote.outcome.should eq(Outcome::Miss)
    end
  end

  it "assesses an ad hoc command" do
    actual = bench.try("zap -rf build/", Commandant::Bench::TargetPlatform::Macos)
    actual.fired_rules.should contain("zap-recursive-force")
    actual.resolved_ruleset.should eq("posix/zap")
  end

  it "serialises reports with severities as written in rulesets" do
    report("posix/zap#zap-force").to_json.should contain(%("severity":"WARNING"))
  end
end
