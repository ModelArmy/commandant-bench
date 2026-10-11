require "./spec_helper"

private alias Kind = Commandant::Bench::VariantKind

private def variant(example : String, kind : Kind, folder = "posix", known = Set{"-r", "-f"}) : Commandant::Bench::Variant
  Commandant::Bench::Variants.generate(example, "rm", folder, known).find!(&.kind.==(kind))
end

describe Commandant::Bench::Variants do
  it "reverses a leading block of flags" do
    variant("rm -r -f build", Kind::Reorder).command.should eq("rm -f -r build")
  end

  it "skips reordering a single flag" do
    variant("rm -rf build", Kind::Reorder).reason.should eq("fewer than two leading flags")
  end

  it "splits combined short flags the ruleset knows" do
    variant("rm -rf build", Kind::Split).command.should eq("rm -r -f build")
  end

  it "does not split a token the ruleset knows as a word flag" do
    variant("rm -exec build", Kind::Split, known: Set{"-exec"}).reason.should eq("no combined short flags")
  end

  it "does not split when the letters are not known flags" do
    (variant("rm -rf build", Kind::Split, known: Set(String).new).reason || "").should contain("word flag")
  end

  it "combines adjacent single-letter flags" do
    variant("rm -r -f build", Kind::Combine).command.should eq("rm -rf build")
  end

  it "quotes the first argument" do
    variant("rm -rf build", Kind::Quote).command.should eq("rm -rf 'build'")
  end

  it "builds prefix and wrapper variants" do
    variant("rm -rf build", Kind::EnvPrefix).command.should eq("BENCH_VAR=1 rm -rf build")
    variant("rm -rf build", Kind::AbsPath).command.should eq("/usr/bin/rm -rf build")
    variant("rm -rf build", Kind::Compound).command.should eq("ls && rm -rf build")
    variant("rm -rf build", Kind::Sudo).command.should eq("sudo rm -rf build")
    variant("rm -rf build", Kind::ShellWrap).command.should eq("sh -c 'rm -rf build'")
  end

  it "runs Windows variants on the matching shell" do
    exe = variant("rm -rf build", Kind::ExeSuffix)
    exe.command.should eq("rm.exe -rf build")
    exe.platform.should eq(Commandant::Bench::TargetPlatform::WindowsPowershell)
    variant("rm -rf build", Kind::CmdExe).platform.should eq(Commandant::Bench::TargetPlatform::WindowsCmd)
  end

  it "skips Windows variants for rulesets that do not apply on Windows" do
    variant("rm -rf build", Kind::ExeSuffix, folder: "linux").reason.should eq("ruleset does not apply on Windows")
  end

  it "skips POSIX-only variants for Windows rulesets" do
    variant("rm -rf build", Kind::EnvPrefix, folder: "windows").reason.should eq("POSIX-only variant")
  end

  it "skips token rewrites when the example has shell operators" do
    variant("rm -r -f build | cat", Kind::Reorder).reason.should eq("example contains shell operators")
    variant("rm -r -f build | cat", Kind::EnvPrefix).command.should eq("BENCH_VAR=1 rm -r -f build | cat")
  end

  it "skips every kind when the example does not start with the tool" do
    variants = Commandant::Bench::Variants.generate("sudo rm -rf build", "rm", "posix", Set{"-r"})
    variants.all?(&.command.nil?).should be_true
  end

  it "never generates kinds that need a flag declaration" do
    variants = Commandant::Bench::Variants.generate("rm -rf build", "rm", "posix", Set{"-r"})
    variants.none?(&.kind.needs_flag_declaration?).should be_true
  end
end
