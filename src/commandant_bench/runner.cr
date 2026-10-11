module Commandant::Bench
  # Runs single commands through the `commandant` engine.
  #
  # Each call builds a fresh `Commandant::Assessor`, because the engine's
  # persistence tracking carries state between assessments and would make a
  # row's result depend on the rows before it.
  class Runner
    SANDBOX_ROOT = Path["/bench/project"]
    WRAPPERS     = %w[ls sudo sh]

    # Creates a runner over the ruleset tree at *rulesets*.
    def initialize(@rulesets : Path)
    end

    # Assesses *command* on *platform*. *tool* is added to the allowed tools,
    # together with the wrappers that variants use, so that constraint checks
    # do not depend on the variant.
    def run(command : String, platform : TargetPlatform, tool : String) : Actual
      assessor = Commandant::Assessor.new(
        ruleset_path: @rulesets,
        sandbox_root: SANDBOX_ROOT,
        allowed_tools: [tool, "#{tool}.exe", "/usr/bin/#{tool}"] + WRAPPERS,
        platform: platform.engine_platform,
      )
      response = assessor.assess(command)
      binary = response.command.binary

      Actual.new(
        platform: platform,
        binary: binary,
        tool_known: response.tool_known?,
        ruleset_tool: response.matched_rules.first?.try(&.ruleset_tool),
        fired_rules: response.matched_rules.map(&.rule_id),
        severity: response.severity,
        default_kind: response.tool_known? && response.matched_rules.empty? ? DefaultKind::Default : DefaultKind::None,
        resolved_ruleset: resolve(binary, platform),
      )
    end

    # Mirrors the engine's lookup order (platform folder, then `posix`) to name
    # the file *binary* resolved to.
    private def resolve(binary : String, platform : TargetPlatform) : String?
      return if binary.empty?

      folder = platform.engine_platform.ruleset_folder
      [folder, "posix"].uniq.each do |candidate|
        return "#{candidate}/#{binary}" if File.exists?((@rulesets / candidate / "#{binary}.json").to_s)
      end
      nil
    end
  end
end
