require "./spec_helper"

private LINT_PATH = FIXTURES_PATH / "lint"

private def findings : Array(Commandant::Bench::LintFinding)
  Commandant::Bench::Workbench.new(LINT_PATH).lint(Commandant::Bench::RulesetRef.parse("posix/bait"))
end

private def checks_for(rule_id : String?) : Array(String)
  findings.select(&.rule_id.==(rule_id)).map(&.check.name).sort!
end

describe Commandant::Bench::Lint do
  it "finds nothing wrong with a clean rule" do
    checks_for("bait-clean").should be_empty
  end

  it "checks the file against its name and folder" do
    checks_for(nil).should eq(%w[platform-matches-folder])
  end

  it "flags id, regex and duplicate problems" do
    checks_for("Bait_Bad_Id").should eq(%w[id-convention])
    checks_for("bait-regex").should eq(%w[pattern-looks-like-regex])
    checks_for("bait-duplicate").should eq(%w[duplicate-pattern])
  end

  it "flags a depends without a note" do
    checks_for("bait-depends").should eq(%w[depends-without-note])
  end

  it "flags missing mitre_attack on rules and the default rule" do
    path = LINT_PATH / "posix" / "bait.json"
    raw = JSON.parse(File.read(path))
    raw["rules"][0].as_h.delete("mitre_attack")
    raw["default_rule"].as_h.delete("mitre_attack")
    typed = Commandant::Ruleset.from_json(raw.to_json)
    bare = Commandant::Bench::Actual.new(Commandant::Bench::TargetPlatform::Linux, "bait", true, nil,
      Array(String).new, Commandant::Severity::Info, Commandant::Bench::DefaultKind::Default, "posix/bait")

    missing = Commandant::Bench::Lint.check(Commandant::Bench::RulesetRef.parse("posix/bait"), typed, raw, bare)
      .select(&.check.missing_mitre?).map(&.rule_id)
    missing.should eq(["bait-clean", "default"])
  end

  it "flags an example that runs another binary" do
    checks_for("bait-wrong-binary").should eq(%w[example-wrong-binary])
  end

  it "flags flags missing from the declaration" do
    checks_for("bait-undeclared").should eq(%w[undeclared-flag])
  end

  it "flags a catch-all rule that fires on the bare command" do
    checks_for("bait-catch-all").should eq(%w[fires-on-bare-command])
  end

  it "advises on a default rule that is depends" do
    finding = findings.find!(&.rule_id.==("default"))
    finding.check.depends_without_note?.should be_true
    finding.level.advice?.should be_true
  end

  it "grades defects as errors and judgement calls as advice" do
    levels = findings.to_h { |finding| {finding.check, finding.level} }
    levels[Commandant::Bench::LintCheck::DuplicatePattern].error?.should be_true
    levels[Commandant::Bench::LintCheck::IdConvention].advice?.should be_true
  end
end
