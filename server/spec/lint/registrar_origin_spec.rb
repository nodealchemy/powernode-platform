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

  # A construction's receiver is a `...Tool` constant — bare, or fully
  # qualified through any number of `::`-namespaces, so Ai::Tools::MemoryTool,
  # a bare MemoryTool written from inside Ai::Tools, and a namespaced BaseTool
  # OUTSIDE Ai::Tools (the real Ai::Ralph::RepositoryGitTool) are all judged
  # the same way — or a variable, whose class the text cannot name. It is
  # built with `.new` (dot or safe-nav `&.`), or `public_send`/`send` of
  # `:new`, `"new"`, or `'new'`, with or without parentheses.
  # Ai::Tools::LocalToolBinding and SemanticToolDiscoveryService are not
  # tools, and do not end in "Tool".
  #
  # KNOWN UNJUDGED SHAPES (deliberate, not a promise of full coverage): a
  # chained receiver (self.class.new, obj.x.new, MAP[k].new,
  # "X".constantize.new); a variable receiver whose call is entirely
  # `**opts`-splatted, with no literal `account:` in its own text; the
  # metaprogramming forms `Class.new`, `&:new`, `method(:new)`,
  # `instance_variable_get(...).new`, and the rare `X::new` call syntax; a
  # class variable (`@@k`) or global (`$k`) receiver; a dynamic-symbol send
  # (`send(:"new", ...)`, which is neither the `:new\b` literal nor a
  # quoted-string arm); and a real BaseTool subclass whose name does not end
  # in "Tool" (e.g. AgentAsToolAdapter) — this matcher judges by naming
  # convention, not by ancestry.
  # (IMP-bda82956101d widened this from Ai::Tools-qualified constants and
  # tool_class/tool_klass called with parentheses; a same-IMP follow-up
  # widened it further to any namespace, safe navigation, and a string-keyed
  # send/public_send.)
  def construction_pattern
    /
      (?<receiver>
        (?:::)?(?:[A-Z]\w*::)*[A-Z]\w*Tool\b
      | (?<![\w:.@$])@?[a-z_]\w*
      )
      \s*(?:&\.|\.)\s*
      (?:new\b(?![?!=])|(?:public_send|__send__|send)\s*\(?\s*(?::new\b|["']new["']))
    /x
  end

  # Core exemptions, each with its reason. A key is a file, which excuses every
  # construction in it, or `file#receiver`, which excuses only the constructions
  # through that variable. Use the second for a variable that holds a class that
  # is not a tool, so a real tool built elsewhere in the file is still judged.
  # A `#receiver` key excuses that receiver NAME wherever it appears in the
  # file, not only the reviewed call site — a different construction that
  # reuses the same variable name for a genuinely different class is excused
  # too, so pick a name-scoped exemption only when that is true throughout
  # the file.
  # An extension lists its own in server/config/direct_tool_constructions.yml
  # (keys relative to its server/ directory, mapped to the reason), found by
  # glob, so core names no extension.
  def construction_allowlist
    allowlist = {
      "server/app/services/ai/tools/mcp_platform_tool_registrar.rb" =>
        "the funnel: build_and_execute sets the caller's origin: on the tool it just built",
      "server/app/services/ai/growth/cross_post_service.rb" =>
        "built only by REST controllers (growth analytics cross_post, content drafts publish): a person's request",
      "server/app/services/ai/tools/base_tool.rb#executor_class" =>
        "build_skill_executor builds a skill executor, not a BaseTool",
      "server/app/services/ai/provisioning/skill_composition_runner.rb#executor_class" =>
        "build_executor builds a System::Ai::Skills executor, not a BaseTool",
      "server/app/services/ai/concierge_router.rb#klass" =>
        "invoke_skill calls klass.descriptor[:inputs] before .new; no BaseTool defines .descriptor, " \
        "so a tool name raises there and is rescued before construction is ever reached",
      "server/app/services/ai/autonomy/observation_pipeline_service.rb#sensor_class" =>
        "an observation sensor, not a BaseTool",
      "server/app/services/ai/coordination/pressure_field_service.rb#klass" =>
        "calculators[field_type] is an Ai::Coordination::Metrics::*Calculator, not a BaseTool",
      "server/app/services/ai/delivery/progressive_executor.rb#klass" =>
        "a delivery strategy from STRATEGY_CLASSES, not a BaseTool",
      "server/app/services/ai/deploy/orchestrator.rb#method_class" =>
        "a deploy method, not a BaseTool",
      "server/app/services/ai/team_strategies/strategy_factory.rb#strategy_class" =>
        "a team strategy from STRATEGY_MAP, not a BaseTool"
    }
    Dir.glob(File.join(repo_root, "extensions/*/server/config/direct_tool_constructions.yml")).sort.each do |file|
      next if file.include?("/private/")

      ext_server = File.dirname(File.dirname(file)).delete_prefix("#{repo_root}/")
      (YAML.safe_load_file(file) || {}).each { |relative, reason| allowlist["#{ext_server}/#{relative}"] = reason.to_s }
    end
    allowlist
  end

  # Every construction in `source` that is code, not a comment, as
  # { receiver:, args: }. A variable is judged only when it passes account:,
  # which every BaseTool requires.
  def constructions(source)
    found = []
    source.scan(construction_pattern) do
      match = Regexp.last_match
      line_start = source.rindex("\n", match.begin(0)) || -1
      next if source[(line_start + 1)...match.begin(0)].lstrip.start_with?("#")

      receiver = match[:receiver]
      args = construction_arguments(source, match)
      next unless receiver.end_with?("Tool") || args.match?(/\baccount:/)

      # `call` is match[0] with any overlap it shares with `args` trimmed off
      # (public_send/send WITH parens re-scans from their own opening paren,
      # which match[0] already reached), so `call + args` reads back as the
      # source text, never duplicating the "(:new" it was found through.
      paren = match[0].index("(")
      call = paren ? match[0][0...paren] : match[0]

      found << { receiver: receiver.delete_prefix("@"), args: args, call: call }
    end
    found
  end

  # A no-paren call's line, up to an unquoted "#" or ";" — a trailing comment
  # or a chained statement never belongs to this call's own arguments, and
  # must not be scanned for a call_origin: that isn't really there. Quote
  # tracking is naive (single-line strings only, no here-docs): inside a
  # string, a "\\" escapes whatever char follows it (so it never mistakes an
  # escaped backslash for an escaped quote), and a quote only OPENS when it
  # is both not preceded by "?" (a ?x char literal) and has a later partner
  # of the same char on this line — a "'" with no such partner (a contraction
  # inside a comment or a regex, `it's`) is left as an ordinary char rather
  # than risk opening a string that never closes and swallows the rest of
  # the line. Not handled: a regex/%-literal whose delimiter IS a real quote
  # char with a coincidental same-char partner later on the line, and
  # send(:"new", ...) (a dynamic-symbol send — see construction_pattern).
  def truncate_at_unquoted(line)
    i = 0
    while i < line.length
      char = line[i]
      if (char == '"' || char == "'") && (i.zero? || line[i - 1] != "?") && line.index(char, i + 1)
        quote = char
        i += 1
        while i < line.length
          if line[i] == "\\"
            i += 2
            next
          end
          break if line[i] == quote

          i += 1
        end
      elsif char == "#" || char == ";"
        return line[0...i]
      end
      i += 1
    end
    line
  end

  # A parenthesized call's argument text runs to its matching paren (for
  # public_send(:new, ...), that call's own paren). One without parentheses
  # runs to the end of its line (truncated at an unquoted "#" or ";"), and on
  # through lines whose TRUNCATED text ends in a comma or a backslash — a
  # trailing comment after a comma (`foo a: 1, # note`) still continues onto
  # the next line in real Ruby, so continuation is decided on the truncated
  # text, not the raw line. Only a ";" ends the call outright, since it is a
  # real statement separator; a "#" truncation alone does not force a stop.
  def construction_arguments(source, match)
    paren = match[0].index("(")
    open_at = paren ? match.begin(0) + paren : (match.end(0) if source[match.end(0)] == "(")
    unless open_at
      text = +""
      source[match.end(0)..].each_line do |line|
        truncated = truncate_at_unquoted(line)
        text << truncated
        stopped_at_semicolon = truncated != line && line[truncated.length] == ";"
        break if stopped_at_semicolon || !truncated.rstrip.end_with?(",", "\\")
      end
      return text
    end

    depth = 0
    source[open_at..].each_char.with_index do |char, offset|
      depth += 1 if char == "("
      depth -= 1 if char == ")"
      return source[open_at..(open_at + offset)] if depth.zero?
    end
    source[open_at..]
  end

  def construction_argument_texts(source)
    constructions(source).map { |c| c[:args] }
  end

  # `call_origin: nil` names no origin.
  def marked?(args)
    args.match?(/\bcall_origin:(?!\s*nil\b)/)
  end

  def unmarked(source)
    constructions(source).reject { |c| marked?(c[:args]) }
  end

  def unmarked_constructions(source)
    unmarked(source).map { |c| c[:args] }
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

    # IMP-bda82956101d: each of these ships a tool with no origin.
    it "flags the shapes a narrower matcher missed" do
      source = <<~RUBY
        module Ai
          module Tools
            class Nested
              def bare = MemoryTool.new(account: account)
              def no_parens = Ai::Tools::MemoryTool.new account: account,
                                                        agent: agent
              def other_variable(klass) = klass.new(account: account, user: user)
              def ivar = @builder.new(account: account)
              def sent = Ai::Tools::MemoryTool.public_send(:new, account: account)
              def sent_bare = MemoryTool.send :new, account: account
              def nil_origin = Ai::Tools::MemoryTool.new(account: account, call_origin: nil)
            end
          end
        end
      RUBY
      expect(unmarked_constructions(source).size).to eq(7)
    end

    it "passes the same shapes when they name a call_origin:" do
      source = <<~RUBY
        MemoryTool.new(account: account, call_origin: origin)
        Ai::Tools::MemoryTool.new account: account,
                                  call_origin: origin
        klass.new(account: account, call_origin:)
        Ai::Tools::MemoryTool.public_send(:new, account: account, call_origin: origin)
      RUBY
      expect(construction_argument_texts(source).size).to eq(4)
      expect(unmarked_constructions(source)).to be_empty
    end

    it "flags safe navigation and a string-keyed send/public_send" do
      source = <<~RUBY
        a = klass&.new(account: account)
        b = Ai::Tools::MemoryTool.send("new", account: account)
        c = Ai::Tools::MemoryTool.send('new', account: account)
        d = Ai::Tools::MemoryTool.public_send("new", account: account)
      RUBY
      expect(unmarked_constructions(source).size).to eq(4)
    end

    it "does not judge a variable's construction that takes no account:" do
      source = <<~RUBY
        row = klass.new(name: "x")
        record.new_record?
        service = System::FleetService.new(account: account)
      RUBY
      expect(construction_argument_texts(source)).to be_empty
    end

    it "judges a bare or namespaced Tool constant in ANY namespace, not only inside Ai::Tools" do
      source = "other = Foo::BarTool.new(account: account)\n"
      expect(unmarked_constructions(source).size).to eq(1)
    end

    it "stops a paren-less call's arguments at an unquoted # or ;, so a trailing comment or a chained statement is never read as its call_origin:" do
      source = <<~RUBY
        t = Ai::Tools::MemoryTool.new account: a # call_origin: TODO
        Ai::Tools::MemoryTool.new account: a; log(call_origin: o)
      RUBY
      expect(unmarked_constructions(source).size).to eq(2)
    end

    it "does not let an escaped backslash, a ?-char literal, or a regex literal's apostrophe hide a trailing comment" do
      source = <<~'RUBY'
        x.new account: a, sep: "\\" # call_origin: TODO
        x.new account: a, sep: ?' # call_origin: TODO
        x.new account: a, re: /it's/ # call_origin: TODO
      RUBY
      expect(unmarked_constructions(source).size).to eq(3)
    end

    it "still treats a real quoted string as opaque, so a # or ; inside it is not read as ending the call" do
      source = <<~'RUBY'
        x.new account: a, s: "a # b", call_origin: o
      RUBY
      expect(unmarked_constructions(source)).to be_empty
    end

    it "continues a paren-less call across a trailing comment after a comma, onto the next line's account:" do
      source = <<~RUBY
        x = klass.new name: 1, # note
                      account: a
      RUBY
      expect(unmarked_constructions(source).size).to eq(1)
    end

    it "a #receiver allowlist entry excuses only that receiver, not every construction in the file" do
      source = <<~RUBY
        skipped = sensor_class.new(account: account)
        tool = ::Ai::Tools::MemoryTool.new(account: account)
      RUBY
      allowlist = { "some/file.rb#sensor_class" => "not a tool" }
      expect(offenders_for("some/file.rb", source, allowlist).size).to eq(1)
    end

    it "an offender message shows the matched call text, not a hardcoded .new" do
      source = "sensor_class.public_send(:new, account: account)\n"
      message = offenders_for("some/file.rb", source, {}).first
      expect(message).to eq("some/file.rb: sensor_class.public_send(:new, account: account)")
    end
  end

  # A file's own offenders: unmarked constructions whose receiver is not
  # excused. A file key excuses everything in it; a `#receiver` key excuses
  # only that receiver's constructions, so a DIFFERENT receiver's unmarked
  # construction in the same file must still be flagged.
  def offenders_for(key, source, allowlist)
    return [] if allowlist.key?(key)

    unmarked(source)
      .reject { |c| allowlist.key?("#{key}##{c[:receiver]}") }
      .map { |c| "#{key}: #{(c[:call] + c[:args]).lines.first.strip}" }
  end

  it "every direct tool construction under app/ names its origin, or is allowlisted with a reason" do
    allowlist = construction_allowlist
    offenders = scanned_files.flat_map do |path|
      offenders_for(path.delete_prefix("#{repo_root}/"), File.read(path), allowlist)
    end
    expect(offenders).to be_empty, "direct tool constructions without call_origin:\n#{offenders.join("\n")}"
  end

  it "keeps the allowlist honest: every entry still constructs a tool without a mark" do
    stale = construction_allowlist.keys.reject do |key|
      file, receiver = key.split("#", 2)
      path = File.join(repo_root, file)
      File.exist?(path) && unmarked(File.read(path)).any? { |c| receiver.nil? || c[:receiver] == receiver }
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
