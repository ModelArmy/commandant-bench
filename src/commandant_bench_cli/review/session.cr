require "../../commandant_bench"
require "./display"
require "./views"

module Commandant::Bench::CLI::Review
  # An interactive review: the reviewer types commands, the session answers by
  # showing Markdown. It asks and scrolls; it does not draw windows.
  #
  # ```
  # display = Commandant::Bench::CLI::Review::PlainDisplay.new(STDIN, STDOUT)
  # Commandant::Bench::CLI::Review::Session.new(bench, display).run
  # ```
  class Session
    @listing = [] of RulesetRef
    @ruleset : RulesetRef? = nil
    @reports = [] of RuleReport
    @index : Int32? = nil
    @problems_only = false
    @platform = TargetPlatform::Linux

    def initialize(@bench : Workbench, @display : Display)
    end

    # Shows the welcome, opens *start* if given, then answers commands until
    # the reviewer quits or input ends.
    def run(start : String? = nil) : Nil
      @display.show(Views.welcome(@bench.rulesets_path, @bench.rulesets.size))
      open(start) if start
      while line = @display.ask(prompt)
        break unless handle(line.strip)
      end
    end

    ALIASES = {
      "" => "next", "n" => "next", "p" => "prev", "ls" => "list", "o" => "open", "r" => "rules",
      "t" => "try", "h" => "help", "?" => "help", "q" => "quit", "exit" => "quit",
    }

    # Acts on one command. Returns false when the reviewer quits.
    def handle(line : String) : Bool
      word, _, rest = line.partition(' ')
      command = ALIASES.fetch(word, word)
      return false if command == "quit"

      dispatch(command, rest.strip)
      true
    rescue ex : Bench::Error | ArgumentError
      @display.show(Views.error(ex.message || ex.class.name))
      true
    end

    private def dispatch(command : String, rest : String) : Nil
      case command
      when "next"     then step(+1)
      when "prev"     then step(-1)
      when "list"     then list(rest.presence)
      when "open"     then open(rest)
      when "rules"    then show_ruleset
      when "problems" then toggle_problems
      when "try"      then try(rest)
      when "platform" then set_platform(rest)
      when "help"     then @display.show(Views::HELP)
      else
        number = command.to_i? || raise ArgumentError.new("Unknown command `#{command}`. Type `help`.")
        open_rule(number)
      end
    end

    private def prompt : String
      if (index = @index) && @ruleset
        "#{@reports[index].rule} (#{index + 1}/#{@reports.size})> "
      elsif ruleset = @ruleset
        "#{ruleset}> "
      else
        "bench> "
      end
    end

    private def list(filter : String?) : Nil
      @listing = @bench.rulesets.select { |ref| filter.nil? || ref.to_s.includes?(filter) }
      entries = @listing.map { |ref| {ref, @bench.rules(ref).size - 1} }
      @display.show(Views.ruleset_list(entries, filter))
    end

    # Opens a ruleset by its number in the last list, by name, or a rule by name.
    private def open(target : String) : Nil
      raise ArgumentError.new("open needs a number, FOLDER/TOOL or FOLDER/TOOL#RULE") if target.empty?

      if number = target.to_i?
        ref = @listing[number - 1]? || raise ArgumentError.new("No ruleset #{number} in the last list")
        open_ruleset(ref)
      elsif target.includes?('#')
        rule = RuleRef.parse(target)
        open_ruleset(rule.ruleset, show: false)
        index = @reports.index(&.rule.==(rule)) || raise NotFoundError.new("No rule #{rule}")
        show_rule(index)
      else
        open_ruleset(RulesetRef.parse(target))
      end
    end

    private def open_ruleset(ref : RulesetRef, show = true) : Nil
      @reports = @bench.report(ref)
      @ruleset = ref
      @index = nil
      show_ruleset if show
    end

    private def open_rule(number : Int32) : Nil
      raise ArgumentError.new("Open a ruleset first") unless @ruleset
      raise ArgumentError.new("No rule #{number}; this ruleset has #{@reports.size}") unless 1 <= number <= @reports.size
      show_rule(number - 1)
    end

    private def step(delta : Int32) : Nil
      raise ArgumentError.new("Open a ruleset first") unless @ruleset

      index = @index.try(&.+(delta)) || 0
      if index >= @reports.size
        @display.show("End of #{@ruleset}. Type `rules`, `list` or `open`.")
      elsif index < 0
        @display.show("Already at the first rule.")
      else
        show_rule(index)
      end
    end

    private def show_ruleset : Nil
      ruleset = @ruleset || raise ArgumentError.new("Open a ruleset first")
      @index = nil
      @display.show(Views.ruleset_summary(ruleset, @reports))
    end

    private def show_rule(index : Int32) : Nil
      @index = index
      @display.show(Views.rule_card(@reports[index], index + 1, @reports.size, @problems_only))
    end

    private def toggle_problems : Nil
      @problems_only = !@problems_only
      if index = @index
        show_rule(index)
      else
        @display.show(@problems_only ? "Showing only misses and false alarms." : "Showing all rows.")
      end
    end

    private def try(command : String) : Nil
      raise ArgumentError.new("try needs a command") if command.empty?
      @display.show(Views.actual(command, @bench.try(command, @platform)))
    end

    private def set_platform(name : String) : Nil
      @platform = TargetPlatform.from_name(name) || raise ArgumentError.new("Unknown platform `#{name}`")
      @display.show("`try` now assesses on #{@platform.name}.")
    end
  end
end
