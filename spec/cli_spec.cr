require "./spec_helper"
require "../src/commandant_bench_cli/cli"

private def run_cli(args : Array(String) = [] of String) : {Int32, String, String}
  stdout = IO::Memory.new
  stderr = IO::Memory.new
  status = Commandant::Bench::CLI.run(args, stdout, stderr)
  {status, stdout.to_s, stderr.to_s}
end

private def with_rulesets(args : Array(String)) : Array(String)
  args + ["--rulesets", RULESETS_PATH.to_s]
end

describe Commandant::Bench::CLI do
  it "prints help and exits 0 with no arguments" do
    status, output, _ = run_cli
    status.should eq(0)
    output.should contain("Subcommands:")
  end

  it "prints the version banner" do
    status, output, _ = run_cli(["version"])
    status.should eq(0)
    output.should contain(Commandant::Bench::VERSION)
  end

  it "exits 1 for an unknown subcommand" do
    status, _, errors = run_cli(["bogus"])
    status.should eq(1)
    errors.should contain("bogus")
  end

  it "lists rulesets" do
    status, output, _ = run_cli(with_rulesets(["list"]))
    status.should eq(0)
    output.should contain("posix/zap")
  end

  it "reports one rule as text" do
    status, output, _ = run_cli(with_rulesets(["report", "posix/zap#zap-recursive-raw"]))
    status.should eq(0)
    output.should contain("MISS")
    output.should contain("Skipped:")
  end

  it "reports a whole ruleset as JSON" do
    status, output, _ = run_cli(with_rulesets(["report", "posix/zap", "--json"]))
    status.should eq(0)
    JSON.parse(output).as_a.size.should eq(4)
  end

  it "assesses one command" do
    status, output, _ = run_cli(with_rulesets(["try", "zap -rf build/", "--platform", "macos"]))
    status.should eq(0)
    output.should contain("zap-recursive-force")
  end

  it "exits 1 for a missing ruleset" do
    status, _, errors = run_cli(with_rulesets(["report", "posix/nope"]))
    status.should eq(1)
    errors.should contain("posix/nope")
  end

  it "exits 1 for an unknown platform" do
    status, _, errors = run_cli(with_rulesets(["try", "zap x", "--platform", "plan9"]))
    status.should eq(1)
    errors.should contain("plan9")
  end
end
