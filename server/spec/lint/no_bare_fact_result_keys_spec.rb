# frozen_string_literal: true

require "spec_helper"
require "yaml"

# APO — THE NO-BARE-FACT RULE, mechanically enforced.
# Design: docs/reference/platform-presentation-design-2026-09-05.md §2.
#
# THE INCIDENT. The concierge told the operator there were no node instances in
# error while twelve were. It had read a result key named `errors` that counts
# AI EXECUTION EVENTS and presented it as fleet health. That key was renamed —
# and the design review then found ten more names of the same shape. Renaming
# instances without a rule only waits for the next plausibly-named key, so this
# file is the rule.
#
# WHAT IT CHECKS, both over the real bytes of every core tool class:
#
#   bare_noun       a result key that is a bare general noun (`errors`,
#                   `status`, `health`, `failed`, …) at the TOP LEVEL of a
#                   result builder. A reader — human or model — resolves a bare
#                   noun to the general question they asked, not to the narrow
#                   one the key answers. The fix is a scope noun in the name:
#                   `agent_execution_errors`, not `errors`.
#
#   constant_status a top-level `status`/`health`-shaped key whose value is a
#                   STRING LITERAL. A field that cannot vary is not a
#                   measurement, and returning one as a status is how a health
#                   probe comes to report `ok` regardless of the world.
#
# WHY IT IS BASELINED. A zero-baseline lint fails immediately against the
# offenders already in the tree and gets reverted within a day. The baseline
# names them per FILE, so they are counted and visible in a file somebody can
# work through, and anything NEW fails. The oracle is EQUALITY in both
# directions: a count that RISES is a regression, a count that DROPS is
# progress that must be recorded here in the same change, and an entry naming a
# file with no offences is stale and fails. A ceiling nobody re-tightens is not
# a ratchet.
#
# PER FILE, NOT PER FINDING, deliberately. An entry that merely said "9 bare
# nouns exist somewhere" would be silently satisfied by a fix in an unrelated
# file while the offender it was written for stayed put.
#
# WHAT IT DOES NOT CHECK. Design rules 2 and 3 — that an observable value
# carries `observed_at` and a `basis`, and that a lifecycle state is returned
# beside an observed one rather than instead of it — are NOT enforced here.
# Both require changing return SHAPES rather than names: baselining them would
# enumerate hundreds of keys, which is a ledger nobody works through, and the
# shape changes land in files other lanes are mid-flight in. They stay design
# rules until someone owns that sweep.
RSpec.describe "no bare fact: tool result keys" do
  repo_root = File.expand_path("../../..", __dir__)
  server_root = File.join(repo_root, "server")
  tools_dir = File.join(server_root, "app/services/ai/tools")
  baseline_path = File.join(__dir__, "no_bare_fact_baseline.yml")

  # A key that reads as the general question. `error`/`errors` and `failed` are
  # the incident's own shape; `status`/`health`/`healthy`/`ok` are the ones the
  # design found 247 keys wide and meaning "what the platform decided" on some
  # rows and "what was observed" on none.
  BARE_NOUNS = %w[errors error health status failed healthy ok].freeze

  # Keys whose value must not be a constant.
  CONSTANT_SHAPED = /(\A|_)(status|health)\z/

  # ---- the scanner -------------------------------------------------------
  #
  # Byte-oriented and Rails-free, like the other lints here. Strings and
  # comments are blanked CHARACTER FOR CHARACTER so every offset in the blanked
  # copy still indexes the same byte of the original — that is what lets the
  # constant check read the raw value at a key found in the blanked copy.
  def self.blank_noise(src)
    out = +""
    i = 0
    quote = nil
    while i < src.length
      c = src[i]
      if quote
        out << (c == "\n" ? "\n" : " ")
        quote = nil if c == quote && src[i - 1] != "\\"
        i += 1
        next
      end
      if c == "#"
        while i < src.length && src[i] != "\n"
          out << " "
          i += 1
        end
        next
      end
      if c == '"' || c == "'"
        quote = c
        out << " "
        i += 1
        next
      end
      out << c
      i += 1
    end
    out
  end

  # Keys directly inside the bracket opened at `start`, with their value offset.
  def self.keys_at_top(blanked, start)
    depth = 0
    i = start
    found = []
    while i < blanked.length
      c = blanked[i]
      depth += 1 if "({[".include?(c)
      if ")}]".include?(c)
        depth -= 1
        break if depth <= 0
      end
      if depth == 1 && (m = blanked[i, 64]&.match(/\A([a-z_][a-z0-9_]*):(?!:)/))
        found << [ m[1], i + m[1].length + 1 ]
        i += m[1].length + 1
        next
      end
      i += 1
    end
    found
  end

  # Every result builder in one file: `success_result(...)` calls and bare
  # `{ success: true, ... }` hash literals — core tools use both.
  def self.offences(raw)
    blanked = blank_noise(raw)
    bare = []
    constant = []

    starts = []
    blanked.to_enum(:scan, /success_result\(/).each do
      open_paren = Regexp.last_match.begin(0) + "success_result".length
      j = open_paren + 1
      j += 1 while blanked[j] =~ /\s/
      starts << (blanked[j] == "{" ? j : open_paren)
    end
    blanked.to_enum(:scan, /\{\s*success:\s*true/).each { starts << Regexp.last_match.begin(0) }

    starts.each do |start|
      keys_at_top(blanked, start).each do |key, value_offset|
        bare << key if BARE_NOUNS.include?(key)
        next unless CONSTANT_SHAPED.match?(key)

        value = raw[value_offset..].to_s.lstrip
        constant << key if value.start_with?('"', "'")
      end
    end

    { "bare_noun" => bare.size, "constant_status" => constant.size }
  end

  # Keyed by path RELATIVE to server/, which is how the baseline names files —
  # an absolute key would differ per checkout and make the baseline unshareable.
  def self.scan_tree(dir, server_root)
    prefix = "#{server_root.chomp('/')}/"
    Dir.glob(File.join(dir, "**", "*.rb")).sort.each_with_object({}) do |path, out|
      counts = offences(File.read(path))
      next if counts.values.all?(&:zero?)

      out[path.delete_prefix(prefix)] = counts
    end
  end

  # ---- the scanner must actually match --------------------------------
  #
  # Every caution this project has earned about guards says the same thing: a
  # pattern that matches nothing passes forever while asserting nothing. These
  # run against fixture bytes, so they hold even if the tree is later cleaned
  # to zero.
  describe "the scanner itself" do
    it "flags a bare noun at the top level of a result builder" do
      src = <<~RUBY
        def call(_params)
          success_result(errors: rows.map(&:to_h), window_hours: 24)
        end
      RUBY

      expect(self.class.offences(src)["bare_noun"]).to eq(1)
    end

    it "does NOT flag the same noun once it carries its scope" do
      src = <<~RUBY
        success_result(agent_execution_errors: rows.map(&:to_h), window_hours: 24)
      RUBY

      expect(self.class.offences(src)["bare_noun"]).to eq(0)
    end

    it "does NOT flag a bare noun NESTED inside another key" do
      # The rule as designed is about the TOP level of a result: an enclosing
      # key can supply the scope a bare noun lacks.
      src = <<~RUBY
        success_result(mission: { status: m.status }, count: 1)
      RUBY

      expect(self.class.offences(src)["bare_noun"]).to eq(0)
    end

    it "flags a constant status and not a computed one" do
      constant = "success_result(status: \"ok\", checked: 3)\n"
      computed = "success_result(status: probe.state, checked: 3)\n"

      expect(self.class.offences(constant)["constant_status"]).to eq(1)
      expect(self.class.offences(computed)["constant_status"]).to eq(0)
    end

    it "reads a bare { success: true } builder as a result too" do
      src = <<~RUBY
        def feed
          { success: true, errors: rows, summary: { error_count: rows.size } }
        end
      RUBY

      expect(self.class.offences(src)["bare_noun"]).to eq(1)
    end

    it "ignores a noun that appears only in a comment or a string" do
      src = <<~RUBY
        # success_result(errors: something)
        success_result(note: "errors: none", count: 0)
      RUBY

      expect(self.class.offences(src)["bare_noun"]).to eq(0)
    end
  end

  # ---- the ratchet --------------------------------------------------------
  describe "the tree against the baseline" do
    let(:baseline) { YAML.safe_load_file(baseline_path) }
    let(:found) { self.class.scan_tree(tools_dir, server_root) }

    it "finds the tool tree at all" do
      # Without this a wrong path would make every absence assertion vacuous.
      expect(Dir.glob(File.join(tools_dir, "*.rb")).size).to be > 20
    end

    it "still matches something, so the ratchet is measuring a live scanner" do
      expect(found).not_to be_empty,
        "the scanner found no offences anywhere. If the tree is genuinely clean, empty the " \
        "baseline and delete this example; until then this means the scanner stopped matching."
    end

    it "has no NEW offending file" do
      new_files = found.keys - baseline.keys

      expect(new_files).to be_empty,
        "these files return a bare general noun, or a constant status, from a result builder. " \
        "Give the key its scope noun (agent_execution_errors, not errors) rather than adding a " \
        "baseline entry: #{new_files.join(', ')}"
    end

    it "has no file whose count ROSE" do
      risen = found.filter_map do |path, counts|
        was = baseline[path] or next
        rules = counts.select { |rule, n| n > was.fetch(rule, 0) }
        next if rules.empty?

        "#{path} #{rules.map { |r, n| "#{r} #{was.fetch(r, 0)}->#{n}" }.join(', ')}"
      end

      expect(risen).to be_empty, "new bare-fact keys in already-baselined files: #{risen.join('; ')}"
    end

    it "has no file whose count DROPPED without the baseline being lowered" do
      # Progress is recorded in the same change. A ceiling left above what the
      # tree contains is a ratchet that has stopped ratcheting.
      dropped = found.filter_map do |path, counts|
        was = baseline[path] or next
        rules = counts.select { |rule, n| n < was.fetch(rule, 0) }
        next if rules.empty?

        "#{path} #{rules.map { |r, n| "#{r} #{was.fetch(r, 0)}->#{n}" }.join(', ')}"
      end

      expect(dropped).to be_empty,
        "fixed, but the baseline still claims the old count — lower it in this change: #{dropped.join('; ')}"
    end

    it "has no STALE baseline entry" do
      # Per FILE, so a fix in an unrelated file cannot satisfy an entry that was
      # never about it.
      stale = baseline.keys - found.keys

      expect(stale).to be_empty,
        "these baseline entries name files with no remaining offences — delete them: #{stale.join(', ')}"
    end

    it "names only files that exist" do
      missing = baseline.keys.reject { |rel| File.file?(File.join(server_root, rel)) }

      expect(missing).to be_empty, "baseline names files that are not in the tree: #{missing.join(', ')}"
    end
  end
end
