require "json"

module Commandant::Bench
  # A platform and shell the bench can assess a command on.
  enum TargetPlatform
    Linux
    Macos
    WindowsCmd
    WindowsPowershell

    # The platform whose rulesets a file in *folder* is written for.
    # `posix` rulesets are assessed on Linux.
    def self.for_folder(folder : String) : TargetPlatform
      case folder
      when "macos"   then Macos
      when "windows" then WindowsCmd
      else                Linux
      end
    end

    # Parses a CLI name such as `linux` or `windows-cmd`; nil if unrecognised.
    def self.from_name(name : String) : TargetPlatform?
      parse?(name.tr("-", "_"))
    end

    def name : String
      to_s.underscore.tr("_", "-")
    end

    def to_json(json : JSON::Builder) : Nil
      json.string(name)
    end

    def engine_platform : Commandant::Platform::Base
      case self
      in Linux             then Commandant::Platform::Linux.new
      in Macos             then Commandant::Platform::MacOS.new
      in WindowsCmd        then Commandant::Platform::Windows::Cmd.new
      in WindowsPowershell then Commandant::Platform::Windows::PowerShell.new
      end
    end
  end
end
