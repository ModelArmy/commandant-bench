require "./spec_helper"

describe Commandant::Bench::RulesetRef do
  it "parses folder/tool" do
    ref = Commandant::Bench::RulesetRef.parse("posix/rm")
    ref.folder.should eq("posix")
    ref.tool.should eq("rm")
    ref.to_s.should eq("posix/rm")
  end

  it "rejects text without a folder" do
    expect_raises(ArgumentError) { Commandant::Bench::RulesetRef.parse("rm") }
  end
end

describe Commandant::Bench::RuleRef do
  it "parses folder/tool#rule" do
    ref = Commandant::Bench::RuleRef.parse("posix/rm#rm-force")
    ref.ruleset.should eq(Commandant::Bench::RulesetRef.new("posix", "rm"))
    ref.rule_id.should eq("rm-force")
    ref.default?.should be_false
  end

  it "recognises the default rule" do
    Commandant::Bench::RuleRef.parse("posix/rm#default").default?.should be_true
  end

  it "rejects text without a rule id" do
    expect_raises(ArgumentError) { Commandant::Bench::RuleRef.parse("posix/rm") }
  end
end
