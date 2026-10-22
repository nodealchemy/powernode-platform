# frozen_string_literal: true

require "ripper"
require "set"

# WorkerRouteCensus — the inverse of RouteCallerCoverageChecker.
#
# That checker asks "does every server route have a caller?". This one asks
# "does every path the WORKER calls have a server route?". A worker call to a
# path nothing routes is a silent 404: BackendApiClient raises, the job logs a
# warning or swallows it, and whatever the worker was reporting is lost.
#
# CORPUS: every non-test Ruby file under worker/app and each extension's
# worker/app (public and private — the extension list comes from
# RouteCallerCoverageChecker so no private extension is named here).
#
# EXTRACTION (Ripper, not regex — Ruby string interpolation nests quotes):
#   1. Lex each file and rebuild every string literal as a list of parts:
#      static text, or an interpolated expression's source.
#   2. Record `CONST = "<string>"` assignments as path constants, and splice
#      `#{CONST}` / `#{self.class::CONST}` / `#{Mod::CONST}` interpolations
#      back to the constant's own parts (first from the same file, then from a
#      name that is defined with exactly one value across the whole corpus).
#   3. Keep a string only if, after splicing, it contains `/api/v1/`. Anything
#      before `/api/v1` (a base URL such as `#{ENV['BACKEND_API_URL']}`) is
#      dropped; a query string (`?...`) is dropped.
#   4. Each remaining interpolation, and each `format` placeholder
#      (`%{id}`, `%<id>s`, `%s`, `%d`), that fills a WHOLE path segment becomes
#      one dynamic segment. One that shares a segment with static text, or one
#      that ends the path with no `/` before it (it may be a suffix or a query
#      string), cannot be resolved statically — the call is reported as
#      UNRESOLVED and never fails the census.
#   5. The HTTP verb is taken from the call on the same line (or the line
#      above, for a call whose arguments start on the next line):
#      `api_client.post(`, `backend_api_get(`, `server_patch(`, ... A literal
#      assigned to a constant takes the verb of the call that passes that
#      constant. When none is found the verb is unknown and only the path must
#      route.
#
# MATCHING: every route in Rails.application.routes (extension routes are
# drawn into it by their engines) is compiled to a regex from its path spec,
# ignoring `requirements:` (a placeholder never satisfies a `/\d+/`
# constraint, and a constraint mismatch is a different bug from no route).
# A call is DEAD if no route matches its path, or VERB_MISMATCH if routes
# match the path but none accepts its verb (Rails answers both with a 404).
module WorkerRouteCensus
  Call = Struct.new(:file, :line, :verb, :path, :raw, keyword_init: true) do
    # Census key, stable across line shifts: "POST /api/v1/internal/foo/:x"
    def key
      "#{verb || 'ANY'} #{path}"
    end

    # Grouping area: the first path segment after /api/v1 (and after
    # /internal when present), e.g. "internal/devops", "system".
    def area
      segs = path.delete_prefix("/api/v1/").split("/")
      segs.first == "internal" ? "internal/#{segs[1]}" : segs.first.to_s
    end
  end

  Unresolved = Struct.new(:file, :line, :raw, :reason, keyword_init: true)

  REPO_ROOT = RouteCallerCoverageChecker::REPO_ROOT

  WORKER_DIRS = (
    [ "worker/app" ] +
    Dir.glob(File.join(REPO_ROOT, "extensions", "*", "worker", "app")).map { |d| d.delete_prefix("#{REPO_ROOT}/") } +
    RouteCallerCoverageChecker::PRIVATE_EXTENSION_NAMES.map { |name| "extensions/private/#{name}/worker/app" }
  ).select { |d| Dir.exist?(File.join(REPO_ROOT, d)) }.sort.freeze

  # `api_client.post(`, `backend_api.get(`, `backend_api_post(`,
  # `server_get(`, `post_no_retry(`, `post_with_circuit_breaker(`,
  # `@api_post.call(`, and BackendApiClient's own bare `get(`/`patch(`.
  # Captures the verb.
  VERB_CALL = /(?:\.|\b(?:backend_api|server|api)_|@api_|(?<![\w.@:]))(get|post|patch|put|delete)(?:_no_retry|_with_circuit_breaker)?(?:\(|\.call\(|\s+["'A-Z])/.freeze
  # worker/app/controllers and worker/app/middleware declare and guard the
  # worker's OWN endpoints (`['POST', '/api/v1/jobs']`) — not calls to the
  # server. RouteCallerCoverageChecker::SERVICE_DIRS excludes them likewise.
  OWN_SURFACE = %r{/worker/app/(controllers|middleware)/}.freeze
  LOCAL_LOOKAHEAD = 10
  # A client call whose first argument starts with neither a quote nor a
  # constant (`format(CONST, ...)` counts as the constant).
  DYNAMIC_ARG_CALL = /\b(?:@?api_client|backend_api(?:_client)?)\.(?:get|post|patch|put|delete)(?:_no_retry|_with_circuit_breaker)?\(\s*(?<arg>(?!format\(\s*[A-Z])[^"'\sA-Z)][^,)]*)/.freeze
  PLACEHOLDER = "\u0000"
  FORMAT_PLACEHOLDER = /%\{\w+\}|%<\w+>[sd]|%[sd]/.freeze

  class << self
    # [calls, unresolved] across the whole worker corpus, memoized.
    def scan
      @scan ||= begin
        files = WORKER_DIRS.flat_map { |d| Dir.glob(File.join(REPO_ROOT, d, "**", "*.rb")) }
          .reject { |f| f.end_with?("_spec.rb") || OWN_SURFACE.match?(f) }
          .sort
        lexed = files.to_h { |f| [ f, lex_strings(File.read(f)) ] }
        global_consts = unique_constants(lexed)
        results = lexed.map do |file, info|
          extract(info, global_consts.merge(info[:consts]), file.delete_prefix("#{REPO_ROOT}/"))
        end
        [ results.flat_map(&:first), results.flat_map(&:last) ]
      end
    end

    def calls = scan[0]
    def unresolved = scan[1]

    # Server routes under /api as [verbs, segment-variants] pairs, memoized.
    # verbs is [] for a verb-less route (`match ... via: :all`, a mount).
    def route_matchers
      @route_matchers ||= Rails.application.routes.routes.filter_map do |r|
        spec = r.path.spec.to_s
        next unless spec.start_with?("/api/")

        [ r.verb.to_s.split("|"), route_variants(spec) ]
      end
    end

    # :ok, :dead, or :verb_mismatch for one call.
    def classify(call)
      segments = call.path.split("/").reject(&:empty?)
      matching = route_matchers.select { |_verbs, variants| variants.any? { |v| segments_match?(segments, v) } }
      return :dead if matching.empty?
      return :ok if call.verb.nil?

      matching.any? { |verbs, _| verbs.empty? || verbs.include?(call.verb.upcase) } ? :ok : :verb_mismatch
    end

    # Rails-free: resolve one Ruby source snippet's API-path strings, for unit
    # examples. Returns [calls, unresolved] as #scan does for the corpus.
    def scan_source(source, file: "snippet.rb")
      info = lex_strings(source)
      extract(info, info[:consts], file)
    end

    def reset!
      @scan = nil
      @route_matchers = nil
    end

    private

    def extract(info, consts, rel)
      calls = []
      unresolved = []
      info[:strings].each do |str|
        parts = splice(str[:parts], consts)
        next unless parts_text(parts).include?("/api/v1/")

        verb = str[:const_name] ? info[:const_verbs][str[:const_name]] : verb_for(info[:lines], str[:line])
        verb ||= local_variable_verb(info[:lines], str[:line])
        result = resolve(parts)
        if result[:path]
          calls << Call.new(file: rel, line: str[:line], verb: verb, path: result[:path], raw: parts_text(parts))
        else
          unresolved << Unresolved.new(file: rel, line: str[:line], raw: parts_text(parts), reason: result[:reason])
        end
      end
      [ calls, unresolved + dynamic_call_sites(info[:lines], rel) ]
    end

    # `path = "/api/v1/..."` (or a ternary of two literals) followed, within
    # a few lines, by `api_client.post(path, ...)`: the literal takes that verb.
    def local_variable_verb(lines, line_no)
      var = lines[line_no - 1].to_s[/\A\s*([a-z_]\w*)\s*=[^=]/, 1]
      return nil unless var

      lines[line_no, LOCAL_LOOKAHEAD].to_a.each do |l|
        m = l.match(/#{VERB_CALL.source.delete_suffix('(?:\(|\.call\(|\s+["\'A-Z])')}\(\s*#{Regexp.escape(var)}\b/)
        return m[1].upcase if m
      end
      nil
    end

    # An API-client call whose path argument is a variable or expression, not
    # a literal or a path constant: the path it sends is not visible here. Its
    # literal, when it exists, is censused where it is written; the call site
    # is listed so the gap is visible, never failed on.
    def dynamic_call_sites(lines, rel)
      lines.each_with_index.filter_map do |l, i|
        next if l.match?(/\A\s*#/)

        m = l.match(DYNAMIC_ARG_CALL)
        next unless m

        Unresolved.new(file: rel, line: i + 1, raw: l.strip, reason: "path argument `#{m[:arg].strip}` is not a literal or a path constant")
      end
    end

    # Lexes `source` into its string literals and constant assignments.
    # => { strings: [{line:, parts:, const_name:}], consts: {NAME => parts},
    #      const_verbs: {NAME => verb}, lines: [String] }
    def lex_strings(source)
      tokens = Ripper.lex(source)
      strings = []
      stack = [] # frames: { kind: :str, parts:, line: } / { kind: :expr, buf:, depth: }
      significant = [] # recent non-space top-level tokens, for CONST = detection

      tokens.each do |(pos, event, tok, _state)|
        top = stack.last
        if top && top[:kind] == :expr
          case event
          when :on_embexpr_beg then top[:depth] += 1
          when :on_embexpr_end
            if top[:depth].zero?
              stack.pop
              stack.last[:parts] << [ :expr, top[:buf].strip ]
              next
            end
            top[:depth] -= 1
          end
          top[:buf] << tok
          next
        end

        case event
        when :on_tstring_beg
          const_name = nil
          if stack.empty?
            sig = significant.last(2)
            const_name = sig[0][2] if sig.size == 2 && sig[0][1] == :on_const && sig[1][1] == :on_op && sig[1][2] == "="
          end
          stack << { kind: :str, parts: [], line: pos[0], const_name: const_name }
        when :on_tstring_content
          top[:parts] << [ :text, tok ] if top
        when :on_embexpr_beg
          stack << { kind: :expr, buf: +"", depth: 0 } if top
        when :on_tstring_end
          frame = stack.pop
          if frame
            if stack.empty?
              strings << { line: frame[:line], parts: frame[:parts], const_name: frame[:const_name] }
            else
              # A string nested inside an interpolation is expression source.
              stack.last[:buf] << frame[:parts].map { |k, v| k == :text ? v : "\#{#{v}}" }.join if stack.last[:kind] == :expr
            end
          end
        end
        significant << [ pos, event, tok ] if stack.empty? && !%i[on_sp on_nl on_ignored_nl on_comment].include?(event)
        significant.shift if significant.size > 4
      end

      lines = source.lines
      consts = strings.select { |s| s[:const_name] }.to_h { |s| [ s[:const_name], s[:parts] ] }
      # A constant takes the verb of a call that passes it directly as the
      # path (`api_client.get(NAME, ...)`, `post(format(NAME, id: 1))`).
      direct_use = ->(name) { /\(\s*(?:format\(\s*)?(?:self\.class::)?#{Regexp.escape(name)}\b/ }
      const_verbs = consts.keys.to_h do |name|
        direct = direct_use.call(name)
        verb = nil
        lines.each_with_index do |l, i|
          next unless l.match?(direct)

          verb = verb_for(lines, i + 1)
          break if verb
        end
        [ name, verb ]
      end
      # A constant only ever spliced into other strings (`"#{BASE}/runs"`) is
      # a base, not a call: the strings built on it are censused instead.
      base_only = consts.keys.select do |name|
        uses = lines.grep(/\b#{Regexp.escape(name)}\b/).reject { |l| l.match?(/\b#{Regexp.escape(name)}\s*=[^=]/) }
        uses.any? && uses.all? { |l| l.match?(/\#\{(?:self\.class::)?#{Regexp.escape(name)}\}/) && !l.match?(direct_use.call(name)) }
      end
      strings.reject! { |str| base_only.include?(str[:const_name]) }
      { strings: strings, consts: consts, const_verbs: const_verbs, lines: lines }
    end

    # Constant names defined with exactly one value across the corpus.
    def unique_constants(lexed)
      values = Hash.new { |h, k| h[k] = [] }
      lexed.each_value { |info| info[:consts].each { |name, parts| values[name] << parts } }
      values.select { |_name, list| list.uniq.size == 1 }.transform_values(&:first)
    end

    # Replaces a `#{CONST}`-style interpolation with the constant's parts.
    def splice(parts, consts, depth = 0)
      parts.flat_map do |kind, value|
        next [ [ kind, value ] ] unless kind == :expr && depth < 3

        name = value[/\A(?:[A-Z]\w*::|self\.class::)*([A-Z][A-Z0-9_]*)\z/, 1]
        name && consts[name] ? splice(consts[name], consts, depth + 1) : [ [ kind, value ] ]
      end
    end

    def parts_text(parts)
      parts.map { |kind, value| kind == :text ? value : "\#{#{value}}" }.join
    end

    # => { path: "/api/v1/a/:x/b" } or { reason: "..." }
    def resolve(parts)
      buf = +""
      parts.each { |kind, value| buf << (kind == :text ? value.gsub(FORMAT_PLACEHOLDER, PLACEHOLDER) : PLACEHOLDER) }
      start = buf.index("/api/v1/")
      buf = buf[start..]
      buf = buf.split("?", 2).first
      buf = buf.split("#", 2).first
      segments = buf.split("/", -1)
      segments.pop if segments.last == "" # trailing slash
      return { reason: "path ends in an interpolation that may be a suffix or query string" } if buf.end_with?(PLACEHOLDER) && !buf.end_with?("/#{PLACEHOLDER}")

      mixed = segments.find { |s| s.include?(PLACEHOLDER) && s != PLACEHOLDER }
      return { reason: "interpolation shares a path segment with static text (#{mixed.tr(PLACEHOLDER, '*')})" } if mixed

      { path: segments.map { |s| s == PLACEHOLDER ? ":x" : s }.join("/") }
    end

    def verb_for(lines, line_no)
      [ line_no, line_no - 1 ].each do |n|
        next if n < 1 || n > lines.size
        # The line above counts only when the call's arguments open there and
        # continue onto this line (`api_client.post(\n  "/api/v1/..."`).
        next if n < line_no && !lines[n - 1].match?(/\(\s*\z/)

        m = lines[n - 1].match(VERB_CALL)
        return m[1].upcase if m
      end
      nil
    end

    # A call's `:x` (an interpolation the scanner cannot see the value of)
    # matches any one route segment, static or dynamic: `"/users/#{id}/#{type}"`
    # reaches `/users/:user_id/consents` when type is "consents". A static call
    # segment must equal a static route segment or fill a `:param`. A `*glob`
    # takes one or more remaining segments.
    def segments_match?(call_segs, route_segs)
      return call_segs.empty? if route_segs.empty?

      kind, text = route_segs.first
      if kind == :glob
        return call_segs.any? && (1..call_segs.size).any? { |n| segments_match?(call_segs.drop(n), route_segs.drop(1)) }
      end
      return false if call_segs.empty?

      seg = call_segs.first
      ok = seg == ":x" || kind == :param || seg == text
      ok && segments_match?(call_segs.drop(1), route_segs.drop(1))
    end

    # Route path spec -> every segment list it can match: each `(...)`
    # optional group is expanded present/absent, `(.:format)` dropped.
    # `requirements:` are deliberately ignored.
    def route_variants(spec)
      expand_optional(spec.gsub("(.:format)", "")).uniq.map do |path|
        path.split("/").reject(&:empty?).map do |seg|
          if seg.start_with?(":") then [ :param, seg ]
          elsif seg.start_with?("*") then [ :glob, seg ]
          else [ :static, seg.sub(/\(.*\z/, "") ]
          end
        end
      end
    end

    def expand_optional(spec)
      open_at = spec.index("(")
      return [ spec ] unless open_at

      depth = 0
      close_at = (open_at...spec.size).find do |i|
        depth += 1 if spec[i] == "("
        depth -= 1 if spec[i] == ")"
        depth.zero?
      end
      head = spec[0...open_at]
      inner = spec[(open_at + 1)...close_at]
      tail = spec[(close_at + 1)..]
      expand_optional(head + tail) + expand_optional(head + inner + tail)
    end
  end
end
