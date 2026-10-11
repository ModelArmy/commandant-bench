require "./spec_helper"
require "../src/commandant_bench_cli/review/session"

private alias Review = Commandant::Bench::CLI::Review

private def transcript(*lines : String, start : String? = nil) : String
  input = IO::Memory.new(lines.join("\n") + "\n")
  output = IO::Memory.new
  bench = Commandant::Bench::Workbench.new(RULESETS_PATH)
  Review::Session.new(bench, Review::PlainDisplay.new(input, output)).run(start)
  output.to_s
end

describe Review::Views do
  it "makes commands safe inside table cells" do
    Review::Views.code("find . | xargs rm").should eq("`find . \\| xargs rm`")
    Review::Views.code("echo `date`").should eq("`echo ‵date‵`")
  end
end

describe Review::Session do
  it "welcomes with the number of rulesets" do
    transcript("quit").should contain("5 rulesets under")
  end

  it "lists rulesets filtered by name" do
    output = transcript("list zap", "quit")
    output.should contain("| 1 | linux/zap | 0 |")
    output.should contain("| 2 | posix/zap | 3 |")
    output.should_not contain("posix/ls")
  end

  it "opens a ruleset by its number in the last list" do
    output = transcript("list zap", "open 2", "quit")
    output.should contain("## posix/zap")
    output.should contain("| 2 | zap-recursive-raw | ERROR |")
  end

  it "steps through rules with Enter and back with prev" do
    output = transcript("", "", "prev", "quit", start: "posix/zap")
    output.scan("## posix/zap#zap-recursive-force").size.should eq(2)
    output.should contain("## posix/zap#zap-recursive-raw · ERROR · 2/4")
  end

  it "opens a rule by number and by name" do
    transcript("3", "quit", start: "posix/zap").should contain("## posix/zap#zap-force · WARNING · 3/4")
    transcript("quit", start: "posix/zap#default").should contain("## posix/zap#default · INFO · 4/4")
  end

  it "shows a rule's misses, notes and skipped reasons" do
    output = transcript("quit", start: "posix/zap#zap-recursive-raw")
    output.should contain("| **MISS** | rule | reorder 1 | fires |")
    output.should contain("Skipped:")
    output.should contain("alias, long, abbrev: needs a flag declaration")
  end

  it "filters rows to problems and back" do
    output = transcript("problems", "problems", "quit", start: "posix/zap#zap-recursive-raw")
    cards = output.split("## posix/zap#zap-recursive-raw")
    cards[2].should_not contain("| ok |")
    cards[2].should contain("showing problems only")
    cards[3].should contain("| ok |")
  end

  it "shows a rule's siblings and calibration" do
    output = transcript("siblings", "quit", start: "posix/zap#zap-force")
    output.should contain("## Siblings of posix/zap#zap-force · WARNING")
    output.should contain("| posix/zap#zap-recursive-force | ERROR |")
    output.should contain("Calibration: fewer than 5 close siblings.")
  end

  it "assesses a command on the chosen platform" do
    output = transcript("platform macos", "try zap -rf build/", "quit")
    output.should contain("| Platform | macos |")
    output.should contain("zap-recursive-force")
  end

  it "reports mistakes without ending the session" do
    output = transcript("7", "bogus", "open posix/zap#nope", "quit")
    output.should contain("Unknown command `bogus`")
    output.should contain("No rule posix/zap#nope")
    output.should contain("Open a ruleset first")
  end

  it "ends when input ends" do
    transcript("list").should contain("posix/zap")
  end
end
