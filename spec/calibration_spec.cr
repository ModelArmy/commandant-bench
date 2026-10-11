require "./spec_helper"

private alias Severity = Commandant::Severity

private def ruleset(tool : String, rules : Array({String, Array(String), String})) : {Commandant::Bench::RulesetRef, Commandant::Ruleset}
  json = {
    tool: tool, tool_summary: tool, platform: "posix",
    rules: rules.map do |(id, tags, severity)|
      {id: id, description: id, risk_tags: tags, reversible: "no", severity: severity, mitre_attack: [] of String,
       patterns: [{pattern: tool, pattern_type: "flag", example: tool, match: {flags_any: ["-x"]}}]}
    end,
    default_rule: {risk_tags: [] of String, reversible: "yes", severity: "INFO", mitre_attack: [] of String},
  }.to_json
  {Commandant::Bench::RulesetRef.new("posix", tool), Commandant::Ruleset.from_json(json)}
end

private def index : Commandant::Bench::CalibrationIndex
  tags = %w[deletes-files irreversible]
  Commandant::Bench::CalibrationIndex.new([
    ruleset("a", [{"a-wipe", tags, "ERROR"}, {"a-soft", tags, "INFO"}]),
    ruleset("b", [{"b-wipe", tags, "ERROR"}, {"b-other", %w[network-egress], "WARNING"}]),
    ruleset("c", [{"c-wipe", tags, "ERROR"}, {"c-near", tags + %w[writes-files], "ERROR"}]),
    ruleset("d", [{"d-wipe", tags, "ERROR"}, {"d-wipe2", tags, "ERROR"}]),
  ])
end

private def calibrate(ref : String, severity : String) : Commandant::Bench::Calibration
  index.calibrate(Commandant::Bench::RuleRef.parse(ref), %w[deletes-files irreversible].to_set, Severity.parse(severity))
end

describe Commandant::Bench::CalibrationIndex do
  it "flags a rule whose severity departs from close siblings that agree" do
    result = calibrate("posix/a#a-soft", "INFO")
    result.close.should eq(5)
    result.usual.should eq(Severity::Error)
    result.outlier?.should be_true
  end

  it "does not flag a rule that agrees with its siblings" do
    calibrate("posix/a#a-wipe", "ERROR").outlier?.should be_false
  end

  it "lists the most similar siblings first and excludes unrelated rules" do
    siblings = calibrate("posix/a#a-soft", "INFO").siblings
    siblings.first.overlap.should eq(1.0)
    siblings.last.rule.to_s.should eq("posix/c#c-near")
    siblings.map(&.rule.to_s).should_not contain("posix/b#b-other")
  end

  it "compares default rules only with default rules" do
    calibrate("posix/a#default", "INFO").siblings.should be_empty
  end
end
