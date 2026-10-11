require "colorize"
require "termify"

module Commandant::Bench::CLI::Review
  # Where a review session writes Markdown and reads the reviewer's replies.
  abstract class Display
    # Shows a block of Markdown.
    abstract def show(markdown : String) : Nil

    # Writes *prompt* and returns the next line of input without its newline,
    # or nil when input has ended.
    abstract def ask(prompt : String) : String?
  end

  # Renders Markdown for a terminal through Termify.
  class TerminalDisplay < Display
    def initialize(@input : IO = STDIN, @output : IO = STDOUT)
    end

    # Prepares the console (needed on Windows) for the duration of the block.
    def session(&)
      terminal = Termify.terminal
      terminal.setup_console
      yield
    ensure
      terminal.try(&.restore_console)
    end

    def show(markdown : String) : Nil
      Termify.render_markdown(@output) { |io| io << markdown }
      @output.puts
    end

    def ask(prompt : String) : String?
      @output << prompt.colorize.bold
      @output.flush
      @input.gets
    end
  end

  # Writes Markdown as-is, for pipes, files and specs.
  class PlainDisplay < Display
    def initialize(@input : IO, @output : IO)
    end

    def show(markdown : String) : Nil
      @output.puts markdown
    end

    # Echoes each reply after its prompt, so a scripted session reads like a
    # transcript.
    def ask(prompt : String) : String?
      @output << prompt
      line = @input.gets
      @output.puts line if line
      line
    end
  end
end
