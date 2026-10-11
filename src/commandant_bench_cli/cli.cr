require "option_parser"
require "json"
require "../commandant_bench"
require "./text_report"

# Command-line entry point for the `commandant-bench` binary.
#
# `CLI.run` parses *argv*, dispatches to a subcommand and returns the process
# exit status. It has no top-level side effects, so specs call it in-process.
module Commandant::Bench::CLI
  BANNER = "commandant-bench #{Commandant::Bench::VERSION} — review bench for commandant rulesets"

  # Options shared by subcommands that read a ruleset tree.
  private class Options
    property rulesets : Path = Path[ENV["RULESETS_PATH"]? || "./rulesets"]
    property? json = false
    property platform : TargetPlatform? = nil
  end

  def self.run(argv : Array(String), io : IO = STDOUT, err : IO = STDERR) : Int32
    return help(io) if argv.empty?

    subcommand, args = argv.first, argv[1..]
    case subcommand
    when "list"                       then list(args, io)
    when "report"                     then report(args, io)
    when "try"                        then try(args, io)
    when "help", "--help", "-h"       then help(io)
    when "version", "--version", "-v" then version(io)
    else
      err.puts "Unknown subcommand: #{subcommand.inspect}"
      err.puts "Run 'commandant-bench help' for usage."
      1
    end
  rescue ex : OptionParser::Exception | ArgumentError | Bench::Error
    err.puts "commandant-bench: #{ex.message}"
    1
  end

  private def self.list(args, io) : Int32
    options, _ = parse(args, "list")
    bench = Workbench.new(options.rulesets)
    refs = bench.rulesets
    if options.json?
      refs.to_json(io)
      io.puts
    else
      refs.each { |ref| io.puts "#{ref.to_s.ljust(32)} #{bench.rules(ref).size - 1} rules" }
    end
    0
  end

  private def self.report(args, io) : Int32
    options, positional = parse(args, "report REF")
    raise ArgumentError.new("report needs one REF: FOLDER/TOOL or FOLDER/TOOL#RULE") unless positional.size == 1

    bench = Workbench.new(options.rulesets)
    ref = positional.first
    reports = ref.includes?('#') ? [bench.report(RuleRef.parse(ref))] : bench.report(RulesetRef.parse(ref))

    if options.json?
      reports.to_json(io)
      io.puts
    else
      reports.each_with_index do |report, index|
        io.puts unless index == 0
        TextReport.render(report, io)
      end
    end
    0
  end

  private def self.try(args, io) : Int32
    options, positional = parse(args, "try COMMAND")
    raise ArgumentError.new("try needs one COMMAND, quoted") unless positional.size == 1

    command = positional.first
    actual = Workbench.new(options.rulesets).try(command, options.platform || TargetPlatform::Linux)
    if options.json?
      actual.to_json(io)
      io.puts
    else
      TextReport.render(command, actual, io)
    end
    0
  end

  private def self.parse(args : Array(String), usage : String) : {Options, Array(String)}
    options = Options.new
    positional = [] of String
    OptionParser.parse(args.dup) do |parser|
      parser.banner = "Usage: commandant-bench #{usage} [options]"
      parser.on("-r PATH", "--rulesets PATH", "Ruleset tree (default: $RULESETS_PATH or ./rulesets)") do |path|
        options.rulesets = Path[path]
      end
      parser.on("--json", "Print results as JSON") { options.json = true }
      parser.on("-p NAME", "--platform NAME", "linux, macos, windows-cmd or windows-powershell (try only)") do |name|
        options.platform = TargetPlatform.from_name(name) || raise ArgumentError.new("Unknown platform #{name.inspect}")
      end
      parser.unknown_args { |before, after| positional.concat(before).concat(after) }
    end
    {options, positional}
  end

  private def self.version(io : IO) : Int32
    io.puts BANNER
    0
  end

  private def self.help(io : IO) : Int32
    io.puts <<-HELP
      #{BANNER}

      Subcommands:
        list                     List ruleset files in the tree
        report FOLDER/TOOL       Bench every rule in a ruleset
        report FOLDER/TOOL#RULE  Bench one rule (use #default for the default rule)
        try COMMAND              Assess one command against the full tree
        help                     Show this help
        version                  Print version

      Options:
        -r, --rulesets PATH      Ruleset tree (default: $RULESETS_PATH or ./rulesets)
        --json                   Print results as JSON
        -p, --platform NAME      Platform for try: linux, macos, windows-cmd, windows-powershell

      Examples:
        commandant-bench report posix/rm#rm-recursive-force
        commandant-bench report posix/rm --json
        commandant-bench try 'FOO=1 rm -rf build/'
      HELP
    0
  end
end
