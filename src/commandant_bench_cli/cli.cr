require "option_parser"
require "json"
require "../commandant_bench"
require "./text_report"
require "./review/session"

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
    property? plain = false
    property reviews : Path? = nil
    property reviewer : String? = nil
  end

  def self.run(argv : Array(String), io : IO = STDOUT, err : IO = STDERR, input : IO = STDIN) : Int32
    return help(io) if argv.empty?

    subcommand, args = argv.first, argv[1..]
    case subcommand
    when "list"                       then list(args, io)
    when "report"                     then report(args, io)
    when "try"                        then try(args, io)
    when "review"                     then review(args, io, input)
    when "lint"                       then lint(args, io)
    when "status"                     then status(args, io)
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
    bench = workbench(options)
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

    bench = workbench(options)
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
    actual = workbench(options).try(command, options.platform || TargetPlatform::Linux)
    if options.json?
      actual.to_json(io)
      io.puts
    else
      TextReport.render(command, actual, io)
    end
    0
  end

  private def self.workbench(options : Options) : Workbench
    Workbench.new(options.rulesets, options.reviews)
  end

  private def self.status(args, io) : Int32
    options, positional = parse(args, "status [FOLDER/TOOL]")
    raise ArgumentError.new("status takes at most one FOLDER/TOOL") if positional.size > 1

    bench = workbench(options)
    refs = positional.first?.try { |ref| [RulesetRef.parse(ref)] } || bench.rulesets
    statuses = refs.flat_map { |ref| bench.statuses(ref) }
    if options.json?
      statuses.map { |(rule, status)| {rule: rule, status: status} }.to_json(io)
      io.puts
    else
      TextReport.render(statuses, io)
    end
    0
  end

  # Exits 1 when any finding is an error, so CI can gate on it.
  private def self.lint(args, io) : Int32
    options, positional = parse(args, "lint [FOLDER/TOOL]")
    raise ArgumentError.new("lint takes at most one FOLDER/TOOL") if positional.size > 1

    bench = workbench(options)
    findings = positional.first?.try { |ref| bench.lint(RulesetRef.parse(ref)) } || bench.lint
    if options.json?
      findings.to_json(io)
      io.puts
    else
      TextReport.render(findings, io)
    end
    findings.any?(&.level.error?) ? 1 : 0
  end

  private def self.review(args, io, input) : Int32
    options, positional = parse(args, "review [REF]")
    raise ArgumentError.new("review takes at most one REF") if positional.size > 1

    bench = workbench(options)
    bench.rulesets # fail early on a missing tree
    start = positional.first?
    if !options.plain? && io.responds_to?(:tty?) && io.tty?
      display = Review::TerminalDisplay.new(input, io)
      display.session { Review::Session.new(bench, display, reviewer(options)).run(start) }
    else
      Review::Session.new(bench, Review::PlainDisplay.new(input, io), reviewer(options)).run(start)
    end
    0
  end

  # The handle to record with sign-offs: `--reviewer`, else `git config github.user`.
  private def self.reviewer(options : Options) : String?
    (options.reviewer || github_user).try(&.lchop('@'))
  end

  private def self.github_user : String?
    handle = Process.run("git", ["config", "--get", "github.user"], output: :pipe, error: :close) do |process|
      process.output.gets_to_end.strip
    end
    handle.presence if $?.success?
  rescue File::NotFoundError | IO::Error
    nil
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
      parser.on("--plain", "Write Markdown as text instead of rendering it (review only)") { options.plain = true }
      parser.on("--reviews PATH", "Sign-off tree (default: reviews/ beside the ruleset tree)") do |path|
        options.reviews = Path[path]
      end
      parser.on("--reviewer HANDLE", "Handle recorded with sign-offs (default: git config github.user)") do |handle|
        options.reviewer = handle
      end
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
        review [REF]             Review rules interactively, optionally starting at REF
        lint [FOLDER/TOOL]       Lint one ruleset or the whole tree; exits 1 on errors
        status [FOLDER/TOOL]     Review state of each rule: unreviewed, approved, changes requested, lapsed
        help                     Show this help
        version                  Print version

      Options:
        -r, --rulesets PATH      Ruleset tree (default: $RULESETS_PATH or ./rulesets)
        --json                   Print results as JSON
        -p, --platform NAME      Platform for try: linux, macos, windows-cmd, windows-powershell
        --plain                  Review with plain Markdown output, e.g. when piping
        --reviews PATH           Sign-off tree (default: reviews/ beside the ruleset tree)
        --reviewer HANDLE        Handle recorded with sign-offs (default: git config github.user)

      Examples:
        commandant-bench report posix/rm#rm-recursive-force
        commandant-bench report posix/rm --json
        commandant-bench try 'FOO=1 rm -rf build/'
        commandant-bench review posix/rm
      HELP
    0
  end
end
