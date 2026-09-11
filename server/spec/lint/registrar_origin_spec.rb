# frozen_string_literal: true

require "spec_helper"
require "find"
require "yaml"

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

  # A TOOL CONSTRUCTED DIRECTLY carries no origin unless its constructor names
  # one (reviewer guidance 3). Every direct construction of a BaseTool
  # subclass under app/ passes `call_origin:`, except the allowlisted files
  # below, each with the reason it is not a machine's unmarked door.
  #
  # NOT SCANNED, deliberately: Ai::Introspection::McpToolRegistrar. It serves
  # the read-only introspection verbs and builds no BaseTool, so there is no
  # tool for a mark to reach. That is a decision, not a blind spot.
  def repo_root = File.expand_path("..", server_root)

  # `...Tool.new(` names under Ai::Tools, and the seams that build one from a
  # variable. Ai::Tools::LocalToolBinding and SemanticToolDiscoveryService are
  # not tools, and do not end in "Tool".
  def construction_pattern
    /(?:\bAi::Tools::[A-Z]\w*Tool|\btool_class|\btool_klass)\s*\.\s*new\s*\(/
  end

  # Core files, each with its reason. An extension lists its own in
  # server/config/direct_tool_constructions.yml (a path relative to its server/
  # directory, mapped to the reason), found by glob, so core names no extension.
  def construction_allowlist
    allowlist = {
      "server/app/services/ai/tools/mcp_platform_tool_registrar.rb" =>
        "the funnel: build_and_execute sets the caller's origin: on the tool it just built",
      "server/app/services/ai/growth/cross_post_service.rb" =>
        "built only by REST controllers (growth analytics cross_post, content drafts publish): a person's request"
    }
    Dir.glob(File.join(repo_root, "extensions/*/server/config/direct_tool_constructions.yml")).sort.each do |file|
      next if file.include?("/private/")

      ext_server = File.dirname(File.dirname(file)).delete_prefix("#{repo_root}/")
      (YAML.safe_load_file(file) || {}).each { |relative, reason| allowlist["#{ext_server}/#{relative}"] = reason.to_s }
    end
    allowlist
  end

  # The argument text of every construction in `source` that is code, not a comment.
  def construction_argument_texts(source)
    texts = []
    source.scan(construction_pattern) do
      match = Regexp.last_match
      line_start = source.rindex("\n", match.begin(0)) || -1
      next if source[(line_start + 1)...match.begin(0)].lstrip.start_with?("#")

      open_at = match.end(0) - 1
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

  def unmarked_constructions(source)
    construction_argument_texts(source).reject { |args| args.match?(/\bcall_origin:/) }
  end

  describe "the construction matcher (both arms)" do
    it "flags a direct construction that names no call_origin:, and skips a comment" do
      source = <<~RUBY
        # ::Ai::Tools::SomeTool.new(account: @account)
        tool = ::Ai::Tools::MemoryTool.new(account: @account, agent: agent, internal: true)
        built = tool_class.new(account: a, user: u)
        discovery = Ai::Tools::SemanticToolDiscoveryService.new(account: a)
      RUBY
      expect(unmarked_constructions(source).size).to eq(2)
    end

    it "passes one that names call_origin:, across lines" do
      source = <<~RUBY
        tool = ::Ai::Tools::ProvisioningTool.new(
          account: account, agent: agent, user: @user,
          call_origin: ::Ai::Tools::CallOrigin::CONCIERGE
        )
      RUBY
      expect(construction_argument_texts(source).size).to eq(1)
      expect(unmarked_constructions(source)).to be_empty
    end
  end

  it "every direct tool construction under app/ names its origin, or is allowlisted with a reason" do
    offenders = scanned_files.flat_map do |path|
      key = path.delete_prefix("#{repo_root}/")
      next [] if construction_allowlist.key?(key)

      unmarked_constructions(File.read(path)).map { |args| "#{key}: #{args.lines.first.strip}" }
    end
    expect(offenders).to be_empty, "direct tool constructions without call_origin:\n#{offenders.join("\n")}"
  end

  it "keeps the allowlist honest: every entry still constructs a tool without a mark" do
    stale = construction_allowlist.keys.reject do |key|
      path = File.join(repo_root, key)
      File.exist?(path) && unmarked_constructions(File.read(path)).any?
    end
    expect(stale).to be_empty, "allowlist entries with nothing left to excuse: #{stale.join(', ')}"

    unjustified = construction_allowlist.select { |_key, reason| reason.to_s.strip.empty? }.keys
    expect(unjustified).to be_empty, "allowlist entries without a reason: #{unjustified.join(', ')}"
  end

  it "the vocabulary names no human door" do
    source = File.read(File.join(server_root, "app/services/ai/tools/call_origin.rb"))
    values = source.scan(/^\s*[A-Z_]+\s*=\s*"([^"]+)"/).flatten
    expect(values).not_to be_empty
    expect(values.grep(/rest|human|session|person|ui\b|browser/i)).to be_empty
  end
end
