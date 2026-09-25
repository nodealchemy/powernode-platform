# frozen_string_literal: true

require "set"

# RouteCallerCoverageChecker — fc-27 rspec guard support.
#
# Enumerates every non-internal `api/v1` route (any controller NOT under
# `Api::V1::Internal::*`, which is service-token-authed worker traffic with no
# caller of its own by design) and checks it has at least one of:
#   - a FRONTEND literal (core frontend/src, public extensions'
#     frontend/src, and — best-effort, since they're gitignored and may not
#     be present at guard-run time — private extensions' frontend/src), or
#   - an MCP-TOOL / EXTENSION-SERVICE caller (server/app/services/ai/tools,
#     and every extension's server/app/services tree, core + private), or
#   - a WORKER or NODE-AGENT caller: the standalone Sidekiq worker's jobs and
#     services, and any extension's Go agent (tests and whole-line comments
#     excluded).
#
# MATCHING HEURISTIC (two tiers, because this codebase has two real calling
# shapes for the same route):
#   Tier 1 — CONTIGUOUS PATH LITERAL. The route's path (with `/api/v1`
#     optionally stripped, since frontend service clients build on a
#     `/api/v1`-rooted axios baseURL and so normally omit it) appears as one
#     literal string, with each `:dynamic_segment` matching an interpolated
#     placeholder (`${id}`, `#{id}`, a bare `:id`, etc — anything with no
#     slash/quote/whitespace). This catches the vast majority of callers,
#     which build a path as ONE template-literal string
#     (`` `/ai/agents/${agentId}/conversations/active` ``).
#   Tier 2 — CO-OCCURRING SEGMENT TOKENS. Some canonical API-service files
#     (e.g. AgentsApiService#buildPath(resource, id, nestedResource, ...))
#     build a path from SEPARATE quoted segment arguments rather than one
#     literal, so Tier 1 cannot see it. Tier 2 credits a route when ALL of
#     its static (non-`:param`) segments appear as quoted string literals
#     SOMEWHERE in the same file, AND that file shows some sign of being an
#     API-calling file (`buildPath(`, `apiClient.`, `api.get(`/`api.post(`/
#     etc). This is intentionally fuzzier and scoped to reduce false
#     negatives from that one well-established construction pattern, not to
#     replace Tier 1 generally.
#
# PERFORMANCE: precomputes, once per process, one concatenated text blob per
# corpus (Tier 1) and a per-file set of quoted-string tokens + an
# API-call-hint flag (Tier 2) — turning a route check into O(1) regex/set
# lookups instead of re-scanning ~2,000 files per route across ~2,400 routes.
#
# KNOWN LIMITATION: like the sibling shell-script guards
# (check-account-scoping.sh, check-authz-coverage.sh), literal/token matching
# cannot see every real call site (deeper abstraction layers, dynamically
# built paths, cross-repo callers). The guard is BASELINED, not a proof: it is
# green on the pre-existing surface via the checked-in baseline allowlist and
# trips only on a NEW route that is neither baselined, webhook-allowlisted,
# nor caught by the heuristic. See route_caller_coverage_spec.rb.
module RouteCallerCoverageChecker
  Route = Struct.new(:verb, :path, :controller, :action) do
    # repo-relative controller#action key, e.g. "api/v1/ai/agents#show"
    def key
      "#{controller}##{action}"
    end
  end

  REPO_ROOT = File.expand_path("../../..", __dir__) # server/spec/support -> repo root

  # Never name a private extension by name here (core-purity guard): derive
  # whichever ones are actually mounted on THIS checkout from the filesystem,
  # the same way scripts/core-purity-check.sh derives its forbidden-name list
  # from extensions/private/* rather than hard-coding it. A checkout with no
  # private extensions (core mode) simply globs an empty list.
  PRIVATE_EXTENSION_NAMES = Dir.glob(File.join(REPO_ROOT, "extensions", "private", "*"))
    .select { |d| File.directory?(d) }
    .map { |d| File.basename(d) }
    .freeze

  FRONTEND_DIRS = (
    [
      "frontend/src",
      "extensions/system/frontend/src",
      "extensions/marketing/frontend/src",
      "extensions/supply-chain/frontend/src"
    ] + PRIVATE_EXTENSION_NAMES.map { |name| "extensions/private/#{name}/frontend/src" }
  ).freeze

  # Server-side callers: MCP tools and extension services, plus the two
  # other processes that call the API over HTTP — the standalone Sidekiq
  # worker (`server_post("/api/v1/...")`) and any Go node agent shipped by an
  # extension (`fmt.Sprintf("/api/v1/.../%s/...", id)`). Agent directories
  # are globbed, like the private-extension list above, so no extension is
  # named here beyond the public ones.
  AGENT_DIRS = Dir.glob(File.join(REPO_ROOT, "{agent,extensions/*/agent,extensions/private/*/agent}"))
    .select { |d| File.directory?(d) }
    .map { |d| d.delete_prefix("#{REPO_ROOT}/") }
    .sort
    .freeze

  SERVICE_DIRS = (
    [
      "server/app/services/ai/tools",
      "extensions/system/server/app/services",
      "extensions/marketing/server/app/services",
      "extensions/supply-chain/server/app/services",
      # Not worker/app/controllers: those declare the worker's OWN endpoints
      # (`['POST', '/api/v1/jobs']`), which are not calls to this server.
      "worker/app/jobs",
      "worker/app/services"
    ] + PRIVATE_EXTENSION_NAMES.map { |name| "extensions/private/#{name}/server/app/services" } + AGENT_DIRS
  ).freeze

  FRONTEND_EXTS = %w[.ts .tsx].freeze
  SERVICE_EXTS = %w[.rb .go].freeze
  # A test that builds a route path is not a caller of it.
  SERVICE_TEST_FILE = /(_test\.go|_spec\.rb)\z/.freeze
  # A whole-line Ruby `#` or Go `//` comment that mentions a path is prose,
  # not a call (e.g. "POSTs to <parent_url>/api/v1/..."). Only whole lines:
  # a trailing comment can't be told from `#{...}` interpolation cheaply.
  SERVICE_COMMENT_LINE = %r{\A\s*(?:#(?!\{)|//)}.freeze

  API_CALL_HINT = /buildPath\(|apiClient\.|api\.(get|post|put|patch|delete)\(|this\.(get|post|put|patch|delete)\(/.freeze
  QUOTED_TOKEN = /(['"`])([A-Za-z0-9_\-]{1,60})\1/.freeze

  # Module import/re-export lines (`import ... from '@/features/...'`,
  # `export * from '...'`, a wrapped `} from '...'` continuation line, or a
  # bare side-effect `import '...'`) are never a route call — a TS path alias
  # like `@/shared/components/Foo` reads as a segment sequence
  # ("components", "Foo") that must never count as a caller of a route whose
  # path happens to share those words. Stripped before either tier scans.
  IMPORT_LINE = /^\s*import\b|\bfrom\s+['"`]/.freeze

  # A base-path declaration: `const BASE = '/platform/component_statuses';`,
  # `private basePath = '/ai/monitoring';`, `protected baseNamespace: string = '/ai';`.
  # Only path-like values (leading `/`) — the value is spliced back into the
  # `${NAME}` / `${this.NAME}` interpolations that use it, so a service that
  # builds every path on a base variable reads as the literal it really sends.
  BASE_PATH_ASSIGNMENT = %r{\b([A-Za-z_]\w*)\s*(?::\s*string\s*)?=\s*(['"`])(/[^'"`\s]*)\2}.freeze
  BASE_PATH_INTERPOLATION = /\$\{(this\.)?([A-Za-z_]\w*)\}/.freeze

  class << self
    # All non-internal api/v1 routes currently mounted, deduped by
    # controller#action (a controller action reachable via >1 HTTP verb/path
    # combination — e.g. member routes generating both PUT and PATCH — only
    # needs ONE caller to prove the action is live).
    def non_internal_api_v1_routes
      @non_internal_api_v1_routes ||= begin
        seen = {}
        Rails.application.routes.routes.each do |r|
          path = r.path.spec.to_s.sub(/\(\.:format\)\z/, "")
          next unless path.start_with?("/api/v1/")

          controller = r.defaults[:controller]
          action = r.defaults[:action]
          next if controller.nil? || action.nil?
          next if controller.start_with?("api/v1/internal/")

          route = Route.new(r.verb.to_s, path, controller, action)
          seen[route.key] ||= route
        end
        seen.values.sort_by(&:key)
      end
    end

    # Returns true if `route` (or a synthetic Route-shaped object with the
    # same #path) has a frontend literal or MCP-tool/extension-service
    # caller under the two-tier heuristic above.
    def covered?(route)
      segments = path_segments(route.path)

      tier1_regex = contiguous_regex(segments)
      return true if frontend_blob.match?(tier1_regex) || service_blob.match?(tier1_regex)

      static_segments = segments.reject { |seg| seg[:dynamic] }.map { |seg| seg[:text] }
      return false if static_segments.size < 2 # too weak a signal to trust Tier 2

      (frontend_file_index.values + service_file_index.values).any? do |entry|
        entry[:api_hint] && static_segments.all? { |seg| entry[:tokens].include?(seg) }
      end
    end

    # Tier 1 against a single piece of source text: true if `path` appears in
    # `text` as a contiguous literal once base-path variables are resolved
    # (from `text` itself, then from `known_bases`). The corpus scan applies
    # the same resolution per file; this is its unit-testable form.
    def literal_caller_in?(path, text, known_bases: {})
      resolved = resolve_base_paths(strip_import_lines(text), known_bases)
      resolved.match?(contiguous_regex(path_segments(path)))
    end

    # Whether `file` belongs in the server-side caller corpus.
    def caller_source_file?(file)
      SERVICE_EXTS.include?(File.extname(file)) && !SERVICE_TEST_FILE.match?(file)
    end

    def reset_memoized_corpus!
      @frontend_file_index = nil
      @service_file_index = nil
      @frontend_blob = nil
      @service_blob = nil
      @corpus_base_paths = nil
      @non_internal_api_v1_routes = nil
    end

    private

    def frontend_file_index
      @frontend_file_index ||= build_file_index(FRONTEND_DIRS, FRONTEND_EXTS)
    end

    def service_file_index
      @service_file_index ||= build_file_index(SERVICE_DIRS, SERVICE_EXTS, reject: SERVICE_TEST_FILE)
    end

    def frontend_blob
      @frontend_blob ||= frontend_file_index.values.map { |e| e[:text] }.join("\n")
    end

    def service_blob
      @service_blob ||= service_file_index.values.map { |e| e[:text] }.join("\n")
    end

    # file => { text:, tokens: Set[quoted string contents], api_hint: bool }
    def build_file_index(dirs, exts, reject: nil)
      sources = {}
      dirs.each do |rel_dir|
        dir = File.join(REPO_ROOT, rel_dir)
        next unless Dir.exist?(dir)

        Dir.glob(File.join(dir, "**", "*")).each do |file|
          next unless exts.include?(File.extname(file))
          next if file.include?("/node_modules/")
          next if reject&.match?(file)

          text = strip_import_lines(File.read(file))
          text = strip_comment_lines(text) if reject
          sources[file] = text
        rescue StandardError
          next
        end
      end

      sources.transform_values do |source|
        text = resolve_base_paths(source, corpus_base_paths)
        tokens = text.scan(QUOTED_TOKEN).map { |_quote, body| body }.to_set
        { text: text, tokens: tokens, api_hint: API_CALL_HINT.match?(text) }
      end
    end

    def strip_import_lines(text)
      text.lines.reject { |line| IMPORT_LINE.match?(line) }.join
    end

    def strip_comment_lines(text)
      text.lines.reject { |line| SERVICE_COMMENT_LINE.match?(line) }.join
    end

    # Base-path names with exactly ONE value across the whole frontend
    # corpus — the fallback for a variable a service inherits rather than
    # declares (`this.baseNamespace` from BaseApiService). A name declared
    # with different values in different files (`basePath`, `BASE_URL`) is
    # left out: guessing which one applies would credit the wrong route.
    def corpus_base_paths
      @corpus_base_paths ||= begin
        values = Hash.new { |h, k| h[k] = Set.new }
        FRONTEND_DIRS.each do |rel_dir|
          Dir.glob(File.join(REPO_ROOT, rel_dir, "**", "*.{ts,tsx}")).each do |file|
            next if file.include?("/node_modules/")

            base_path_declarations(File.read(file)).each { |name, value| values[name] << value }
          rescue StandardError
            next
          end
        end
        values.select { |_name, set| set.size == 1 }.transform_values(&:first)
      end
    end

    # name => value for this text's own base-path declarations; a name
    # declared twice with different values is ambiguous and dropped.
    def base_path_declarations(text)
      found = Hash.new { |h, k| h[k] = Set.new }
      text.scan(BASE_PATH_ASSIGNMENT) { |name, _quote, value| found[name] << value }
      found.select { |_name, set| set.size == 1 }.transform_values(&:first)
    end

    # Splices each resolvable `${NAME}` / `${this.NAME}` back to its declared
    # path, so `` `${this.basePath}/health/detailed` `` with basePath
    # '/ai/monitoring' reads as `` `/ai/monitoring/health/detailed` `` — the
    # route it really calls. A bare `${NAME}` resolves only from this file's
    # own declarations (it is a local or module constant; a same-named
    # function parameter elsewhere, like `${base}` in a compare path, must not
    # pick up some other file's value). `${this.NAME}` may also fall back to
    # `known_bases`, for a field inherited from a base class. An unresolvable
    # interpolation is left as-is and does NOT anchor a match: a bare leading
    # `}` would credit the un-prefixed route (/health/detailed), which is a
    # different endpoint.
    def resolve_base_paths(text, known_bases)
      local = base_path_declarations(text)
      return text if local.empty? && known_bases.empty?

      text.gsub(BASE_PATH_INTERPOLATION) do
        this_ref, name = Regexp.last_match.captures
        local[name] || (this_ref && known_bases[name]) || Regexp.last_match(0)
      end
    end

    # Splits "/api/v1/ai/agents/:id/conversations/active" into segment
    # hashes, stripping a leading /api/v1 (frontend clients build on a
    # /api/v1-rooted baseURL and normally omit it from literals).
    def path_segments(path)
      stripped = path.sub(%r{\A/api/v1}, "")
      stripped.split("/").reject(&:empty?).map do |seg|
        { text: seg.sub(/\A:/, ""), dynamic: seg.start_with?(":") }
      end
    end

    # Anchored so a route path can't match as a mere substring of something
    # unrelated — a fake route `/components/:id` must NOT be "covered" by
    # `@/shared/components/Foo` just because "components/Foo" appears in it.
    # Requires, immediately before the path: a quote, a backtick, or the
    # literal `/api/v1`. And immediately after: a quote, `?`, `/`, `$` (the
    # start of a trailing `${...}`, e.g. `` `/audit_logs/security_summary${params}` ``),
    # or end-of-line. A base-path VARIABLE spliced into a template literal
    # (`` `${BASE_PATH}/pipelines` ``) is resolved to its declared value by
    # #resolve_base_paths before this runs; an unresolvable one does NOT
    # satisfy the anchor, since a bare `}` boundary reopens the false-positive
    # class this anchor exists to close (a real `.../components/${id}/...`
    # route would cover an unrelated fake `/components/:id`).
    def contiguous_regex(segments)
      parts = segments.map do |seg|
        seg[:dynamic] ? "[^/'\"`\\s]+" : Regexp.escape(seg[:text])
      end
      path_pattern = parts.join("/")
      # $ (not \z): the corpus is many files concatenated by "\n" into one
      # blob, and Ruby's $ matches at each line boundary regardless of the
      # /m flag, so "end of string" here really means "end of this line".
      Regexp.new("(?:['\"`]|/api/v1)/#{path_pattern}(?:['\"`?/$]|$)")
    end
  end
end
