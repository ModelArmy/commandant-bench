require "../commandant_bench"

# Command-line entry point for the `commandant-bench` binary.
#
# `CLI.run` parses *argv*, dispatches to a subcommand and returns the process
# exit status. It has no top-level side effects, so specs call it in-process.
module Commandant::Bench::CLI
  BANNER = "commandant-bench #{Commandant::Bench::VERSION} — review bench for commandant rulesets"

  def self.run(argv : Array(String), io : IO = STDOUT, err : IO = STDERR) : Int32
    return help(io) if argv.empty?

    case subcommand = argv.first
    when "help", "--help", "-h"       then help(io)
    when "version", "--version", "-v" then version(io)
    else
      err.puts "Unknown subcommand: #{subcommand.inspect}"
      err.puts "Run 'commandant-bench help' for usage."
      1
    end
  end

  private def self.version(io : IO) : Int32
    io.puts BANNER
    0
  end

  private def self.help(io : IO) : Int32
    io.puts <<-HELP
      #{BANNER}

      Subcommands:
        help     Show this help
        version  Print version
      HELP
    0
  end
end
