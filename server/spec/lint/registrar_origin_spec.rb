# frozen_string_literal: true

require "spec_helper"
require "find"

# EVERY TOOL DOOR MARKS ITS CALL (MCP identity plan R3).
#
# Ai::Tools::McpPlatformToolRegistrar is the funnel every MCP-shaped caller
# passes: the streamable controller, the agent tool bridge, the skill recipe
# runner, the ActionCable protocol service, and loop-local tools through
# Ai::Tools::LocalToolBinding#dispatch. Each call site names HOW its call
# arrived with `origin:` (Ai::Tools::CallOrigin), and the tool reads that mark
# instead of inferring "a person" from a nil agent. The keyword is optional on
# purpose (a required one would force it into every spec that drives the
# registrar), so THIS spec is what keeps a production call site from omitting
# it: an unmarked call grants no consent, but it also misses the checks keyed
# on the mark (the autonomy gate's agent audience, DataSourceTool's per-action
# permissions).
#
# It also pins that the vocabulary names no human door. A tool call is never a
# person's consent (R1); a value that read as one would invite a check to treat
# it so.
#
# SCOPE: core `app/**` and every public extension's `server/app/**`, found by
# glob. extensions/private/* is not scanned (remote-only).
RSpec.describe "registrar call sites carry origin:" do
  # Methods, not constants: a constant assigned in a describe block lands on
  # Object and collides with every other spec that names one ROOT.
  def server_root = File.expand_path("../..", __dir__)

  def call_pattern
    /(?:McpPlatformToolRegistrar\s*\.\s*(?:execute_tool|run_guarded)|\blocal_tools\s*\.\s*dispatch)\s*\(/
  end

  # The argument text of every call in `source`, up to its matching paren.
  def call_argument_texts(source)
    texts = []
    source.scan(call_pattern) do
      open_at = Regexp.last_match.end(0) - 1
      depth = 0
      close_at = nil
      source[open_at..].each_char.with_index do |char, offset|
        depth += 1 if char == "("
        depth -= 1 if char == ")"
        if depth.zero?
          close_at = open_at + offset
          break
        end
      end
      texts << source[open_at..(close_at || -1)]
    end
    texts
  end

  def unmarked_calls(source)
    call_argument_texts(source).reject { |args| args.match?(/\borigin:/) }
  end

  def scanned_files
    roots = [ File.join(server_root, "app") ] +
            Dir.glob(File.expand_path("../extensions/*/server/app", server_root)).reject { |d| d.include?("/private/") }
    roots.flat_map { |root| Dir.glob(File.join(root, "**", "*.rb")) }.sort
  end

  describe "the matcher (both arms)" do
    it "flags a call that omits origin:" do
      source = "Ai::Tools::McpPlatformToolRegistrar.execute_tool(\"platform.x\", params: {}, account: a)"
      expect(unmarked_calls(source).size).to eq(1)
    end

    it "passes a call that names origin:, including across lines and nested parens" do
      source = <<~RUBY
        ::Ai::Tools::McpPlatformToolRegistrar.run_guarded(
          tool_class, params: h.merge(x: f(1)), account: account,
          origin: ::Ai::Tools::CallOrigin::AGENT_BRIDGE
        )
        local_tools.dispatch(name, args, account: a, user: u, agent: g, origin: o)
      RUBY
      expect(call_argument_texts(source).size).to eq(2)
      expect(unmarked_calls(source)).to be_empty
    end
  end

  it "finds the call sites it guards (a scan that sees none proves nothing)" do
    total = scanned_files.sum { |path| call_argument_texts(File.read(path)).size }
    expect(total).to be >= 6
  end

  it "every production call site marks its origin" do
    offenders = scanned_files.flat_map do |path|
      unmarked_calls(File.read(path)).map { |args| "#{path.delete_prefix("#{server_root}/")}: #{args.lines.first.strip}" }
    end
    expect(offenders).to be_empty, "registrar calls without origin:\n#{offenders.join("\n")}"
  end

  it "the vocabulary names no human door" do
    source = File.read(File.join(server_root, "app/services/ai/tools/call_origin.rb"))
    values = source.scan(/^\s*[A-Z_]+\s*=\s*"([^"]+)"/).flatten
    expect(values).not_to be_empty
    expect(values.grep(/rest|human|session|person|ui\b|browser/i)).to be_empty
  end
end
