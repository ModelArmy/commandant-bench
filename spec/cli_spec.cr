require "./spec_helper"
require "../src/commandant_bench_cli/cli"

private def run_cli(args : Array(String) = [] of String) : {Int32, String, String}
  stdout = IO::Memory.new
  stderr = IO::Memory.new
  status = Commandant::Bench::CLI.run(args, stdout, stderr)
  {status, stdout.to_s, stderr.to_s}
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
end
