require "json"
require "digest/sha256"
require "file_utils"

module Commandant::Bench
  # A reviewer's answer to one review question.
  enum Answer
    Pass
    Fail
  end

  # Answers to the four review questions (BENCH_DESIGN.md section 1).
  struct Answers
    include JSON::Serializable

    # Q-a: are the description and behaviour right for the tool?
    getter accurate : Answer
    # Q-b: does the rule fire on the right commands, and only those?
    getter catches : Answer
    # Q-c: is the severity consistent with similar rules?
    getter calibrated : Answer
    # Q-d: do the notes admit the rule's gaps?
    getter honest : Answer

    def initialize(@accurate, @catches, @calibrated, @honest)
    end

    def all_pass? : Bool
      {accurate, catches, calibrated, honest}.all?(&.pass?)
    end
  end

  # The bench's counts at the moment of sign-off, for context.
  record BenchSummary, rows : Int32, misses : Int32, false_alarms : Int32, skipped : Int32 do
    include JSON::Serializable

    def self.of(report : RuleReport) : BenchSummary
      new(report.rows.size, report.count(Outcome::Miss), report.count(Outcome::FalseAlarm), report.count(Outcome::Skipped))
    end
  end

  # One recorded review of one rule.
  record SignOff,
    rule_hash : String,
    reviewer : String,
    date : String,
    engine_version : String,
    answers : Answers,
    note : String,
    bench : BenchSummary do
    include JSON::Serializable
  end

  enum ReviewState
    # Never reviewed.
    Unreviewed
    # Reviewed, every answer passed, and the rule is unchanged since.
    Approved
    # Reviewed with at least one failed answer, and the rule is unchanged since.
    ChangesRequested
    # Reviewed, but the rule has changed since, so the review no longer applies.
    Lapsed

    def name : String
      to_s.underscore.tr("_", "-")
    end

    def to_json(json : JSON::Builder) : Nil
      json.string(name)
    end
  end

  # A rule's review state and the sign-off it rests on, if any.
  record ReviewStatus, state : ReviewState, sign_off : SignOff? = nil do
    include JSON::Serializable

    def self.of(sign_off : SignOff?, rule_hash : String) : ReviewStatus
      case
      when sign_off.nil?                   then new(ReviewState::Unreviewed)
      when sign_off.rule_hash != rule_hash then new(ReviewState::Lapsed, sign_off)
      when sign_off.answers.all_pass?      then new(ReviewState::Approved, sign_off)
      else                                      new(ReviewState::ChangesRequested, sign_off)
      end
    end
  end

  # Fingerprints a rule so that a sign-off lapses when the rule changes.
  module RuleHash
    # Ruleset fields that change how every rule in it matches.
    CONTEXT = %w[option_abbreviations flags subcommands unrecognised_severity is_multiplexer]

    # SHA-256 of the canonical JSON of the rule's object together with the
    # ruleset fields in `CONTEXT`, written `sha256:<hex>`.
    def self.of(raw : JSON::Any, rule_id : String) : String
      rule = if rule_id == RuleRef::DEFAULT
               raw["default_rule"]
             else
               raw["rules"].as_a.find { |candidate| candidate["id"].as_s == rule_id }
             end
      raise NotFoundError.new("No rule #{rule_id.inspect}") unless rule

      context = CONTEXT.compact_map { |key| raw[key]?.try { |value| {key, value} } }.to_h
      subject = JSON::Any.new({"rule" => rule, "context" => JSON::Any.new(context)})
      "sha256:#{Digest::SHA256.hexdigest(canonical(subject))}"
    end

    # JSON with object keys sorted and no whitespace, so equal content always
    # hashes equally.
    def self.canonical(value : JSON::Any) : String
      JSON.build { |json| write(value, json) }
    end

    private def self.write(value : JSON::Any, json : JSON::Builder) : Nil
      if hash = value.as_h?
        json.object do
          hash.keys.sort!.each do |key|
            json.field(key) { write(hash[key], json) }
          end
        end
      elsif array = value.as_a?
        json.array { array.each { |item| write(item, json) } }
      else
        value.to_json(json)
      end
    end
  end

  # Reads and writes sign-offs in a tree that mirrors the ruleset tree: the
  # sign-offs for `posix/rm` live in `<root>/posix/rm.json`, keyed by rule id.
  class ReviewStore
    getter root : Path

    def initialize(@root : Path)
    end

    def read(ruleset : RulesetRef) : Hash(String, SignOff)
      path = ruleset.path(@root)
      return {} of String => SignOff unless File.exists?(path.to_s)

      Hash(String, SignOff).from_json(File.read(path.to_s))
    end

    # Records *sign_off* for *rule_id*, replacing any earlier one. Entries are
    # written sorted by rule id so the file diffs cleanly.
    def write(ruleset : RulesetRef, rule_id : String, sign_off : SignOff) : Nil
      entries = read(ruleset)
      entries[rule_id] = sign_off
      sorted = entries.to_a.sort_by!(&.[0]).to_h

      path = ruleset.path(@root)
      Dir.mkdir_p(File.dirname(path.to_s))
      temporary = "#{path}.tmp"
      File.write(temporary, sorted.to_pretty_json + "\n")
      File.rename(temporary, path.to_s)
    end
  end
end
