require "./spec_helper"
require "file_utils"

private alias Bench = Commandant::Bench

# Yields a writable copy of the fixture ruleset tree and an empty reviews path.
def with_scratch_tree(&)
  root = Path[Dir.tempdir] / "bench-spec-#{Random::Secure.hex(6)}"
  Dir.mkdir_p(root.to_s)
  FileUtils.cp_r(RULESETS_PATH.to_s, (root / "rulesets").to_s)
  yield root / "rulesets", root / "reviews"
ensure
  FileUtils.rm_rf(root.to_s) if root
end

def answers(*values : Bench::Answer) : Bench::Answers
  Bench::Answers.new(values[0], values[1], values[2], values[3])
end

private PASS = Bench::Answer::Pass
private FAIL = Bench::Answer::Fail

private def edit_rule(rulesets : Path, rule_id : String, &)
  path = rulesets / "posix" / "zap.json"
  raw = JSON.parse(File.read(path))
  rule = raw["rules"].as_a.find! { |candidate| candidate["id"].as_s == rule_id }
  yield rule.as_h
  File.write(path, raw.to_pretty_json)
end

describe Bench::RuleHash do
  raw = JSON.parse(File.read(RULESETS_PATH / "posix" / "zap.json"))

  it "ignores key order" do
    Bench::RuleHash.canonical(JSON.parse(%({"b": 1, "a": {"d": 2, "c": 3}})))
      .should eq(Bench::RuleHash.canonical(JSON.parse(%({"a": {"c": 3, "d": 2}, "b": 1}))))
  end

  it "differs between rules and is stable for one rule" do
    Bench::RuleHash.of(raw, "zap-force").should eq(Bench::RuleHash.of(raw, "zap-force"))
    Bench::RuleHash.of(raw, "zap-force").should_not eq(Bench::RuleHash.of(raw, "zap-recursive-raw"))
  end

  it "changes when ruleset fields that affect matching change" do
    before = Bench::RuleHash.of(raw, "zap-force")
    changed = JSON.parse(raw.to_json)
    changed.as_h["option_abbreviations"] = JSON::Any.new({"--frc" => JSON::Any.new("--force")})
    Bench::RuleHash.of(changed, "zap-force").should_not eq(before)
  end
end

describe Bench::ReviewStatus do
  sign_off = Bench::SignOff.new("sha256:a", "nogginly", "2026-10-11", "0.5.3", answers(PASS, PASS, PASS, PASS), "",
    Bench::BenchSummary.new(1, 0, 0, 0))

  it "derives the state from the sign-off and the current hash" do
    Bench::ReviewStatus.of(nil, "sha256:a").state.unreviewed?.should be_true
    Bench::ReviewStatus.of(sign_off, "sha256:a").state.approved?.should be_true
    Bench::ReviewStatus.of(sign_off, "sha256:b").state.lapsed?.should be_true
  end

  it "requests changes when any answer fails" do
    failing = sign_off.copy_with(answers: answers(PASS, FAIL, PASS, PASS))
    Bench::ReviewStatus.of(failing, "sha256:a").state.changes_requested?.should be_true
  end
end

describe "Workbench sign-off" do
  it "records a sign-off and reports the rule approved" do
    with_scratch_tree do |rulesets, reviews|
      bench = Bench::Workbench.new(rulesets, reviews)
      report = bench.report(Bench::RuleRef.parse("posix/zap#zap-force"))
      report.review.state.unreviewed?.should be_true

      bench.sign_off(report, "@nogginly", answers(PASS, PASS, PASS, PASS), "looks right", Time.utc(2026, 10, 11))
      status = bench.status(report.rule)
      status.state.approved?.should be_true
      status.sign_off.try(&.reviewer).should eq("nogginly")
      status.sign_off.try(&.date).should eq("2026-10-11")
      File.exists?(reviews / "posix" / "zap.json").should be_true
    end
  end

  it "lapses the sign-off when the rule changes, and only that rule's" do
    with_scratch_tree do |rulesets, reviews|
      bench = Bench::Workbench.new(rulesets, reviews)
      %w[zap-force zap-recursive-raw].each do |rule_id|
        report = bench.report(Bench::RuleRef.parse("posix/zap##{rule_id}"))
        bench.sign_off(report, "nogginly", answers(PASS, PASS, PASS, PASS))
      end

      edit_rule(rulesets, "zap-force") { |rule| rule["severity"] = JSON::Any.new("ERROR") }

      states = bench.statuses(Bench::RulesetRef.parse("posix/zap")).to_h { |(rule, status)| {rule.rule_id, status.state} }
      states["zap-force"].lapsed?.should be_true
      states["zap-recursive-raw"].approved?.should be_true
      states["default"].unreviewed?.should be_true
    end
  end

  it "writes sign-offs sorted by rule id" do
    with_scratch_tree do |rulesets, reviews|
      bench = Bench::Workbench.new(rulesets, reviews)
      %w[zap-recursive-raw zap-force].each do |rule_id|
        bench.sign_off(bench.report(Bench::RuleRef.parse("posix/zap##{rule_id}")), "nogginly", answers(PASS, PASS, PASS, PASS))
      end
      JSON.parse(File.read(reviews / "posix" / "zap.json")).as_h.keys.should eq(%w[zap-force zap-recursive-raw])
    end
  end

  it "rejects a reviewer that is not a handle" do
    with_scratch_tree do |rulesets, reviews|
      bench = Bench::Workbench.new(rulesets, reviews)
      report = bench.report(Bench::RuleRef.parse("posix/zap#zap-force"))
      expect_raises(ArgumentError) { bench.sign_off(report, "Full Name", answers(PASS, PASS, PASS, PASS)) }
    end
  end

  it "keeps reviews beside the ruleset tree by default" do
    Bench::Workbench.new(Path["/data/rules/rulesets"]).reviews.root.to_posix.to_s.should eq("/data/rules/reviews")
  end
end
