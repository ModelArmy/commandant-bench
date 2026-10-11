require "json"

module Commandant::Bench
  # Names one ruleset file by its platform folder and tool, written `posix/rm`.
  record RulesetRef, folder : String, tool : String do
    # Parses `folder/tool`. Raises `ArgumentError` for any other shape.
    def self.parse(text : String) : RulesetRef
      folder, slash, tool = text.partition('/')
      raise ArgumentError.new("Expected FOLDER/TOOL, got #{text.inspect}") if slash.empty? || folder.empty? || tool.empty?
      new(folder, tool)
    end

    # Path of the ruleset file under *rulesets*.
    def path(rulesets : Path) : Path
      rulesets / folder / "#{tool}.json"
    end

    def to_s(io : IO) : Nil
      io << folder << '/' << tool
    end

    def to_json(json : JSON::Builder) : Nil
      json.string(to_s)
    end
  end

  # Names one rule within a ruleset, written `posix/rm#rm-recursive-force`.
  # The rule id `default` names the ruleset's default rule.
  record RuleRef, ruleset : RulesetRef, rule_id : String do
    DEFAULT = "default"

    # Parses `folder/tool#rule-id`. Raises `ArgumentError` for any other shape.
    def self.parse(text : String) : RuleRef
      ruleset, hash, rule_id = text.partition('#')
      raise ArgumentError.new("Expected FOLDER/TOOL#RULE, got #{text.inspect}") if hash.empty? || rule_id.empty?
      new(RulesetRef.parse(ruleset), rule_id)
    end

    def self.default(ruleset : RulesetRef) : RuleRef
      new(ruleset, DEFAULT)
    end

    def default? : Bool
      rule_id == DEFAULT
    end

    def to_s(io : IO) : Nil
      io << ruleset << '#' << rule_id
    end

    def to_json(json : JSON::Builder) : Nil
      json.string(to_s)
    end
  end
end
