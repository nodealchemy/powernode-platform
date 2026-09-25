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
#     and every extension's server/app/services tree, core + private).
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

  SERVICE_DIRS = (
    [
      "server/app/services/ai/tools",
      "extensions/system/server/app/services",
      "extensions/marketing/server/app/services",
      "extensions/supply-chain/server/app/services"
    ] + PRIVATE_EXTENSION_NAMES.map { |name| "extensions/private/#{name}/server/app/services" }
  ).freeze

  FRONTEND_EXTS = %w[.ts .tsx].freeze
  SERVICE_EXTS = %w[.rb].freeze

  API_CALL_HINT = /buildPath\(|apiClient\.|api\.(get|post|put|patch|delete)\(|this\.(get|post|put|patch|delete)\(/.freeze
  QUOTED_TOKEN = /(['"`])([A-Za-z0-9_\-]{1,60})\1/.freeze

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

    def reset_memoized_corpus!
      @frontend_file_index = nil
      @service_file_index = nil
      @frontend_blob = nil
      @service_blob = nil
      @non_internal_api_v1_routes = nil
    end

    private

    def frontend_file_index
      @frontend_file_index ||= build_file_index(FRONTEND_DIRS, FRONTEND_EXTS)
    end

    def service_file_index
      @service_file_index ||= build_file_index(SERVICE_DIRS, SERVICE_EXTS)
    end

    def frontend_blob
      @frontend_blob ||= frontend_file_index.values.map { |e| e[:text] }.join("\n")
    end

    def service_blob
      @service_blob ||= service_file_index.values.map { |e| e[:text] }.join("\n")
    end

    # file => { text:, tokens: Set[quoted string contents], api_hint: bool }
    def build_file_index(dirs, exts)
      index = {}
      dirs.each do |rel_dir|
        dir = File.join(REPO_ROOT, rel_dir)
        next unless Dir.exist?(dir)

        Dir.glob(File.join(dir, "**", "*")).each do |file|
          next unless exts.include?(File.extname(file))
          next if file.include?("/node_modules/")

          text = File.read(file)
          tokens = text.scan(QUOTED_TOKEN).map { |_quote, body| body }.to_set
          index[file] = { text: text, tokens: tokens, api_hint: API_CALL_HINT.match?(text) }
        rescue StandardError
          next
        end
      end
      index
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

    def contiguous_regex(segments)
      parts = segments.map do |seg|
        seg[:dynamic] ? "[^/'\"`\\s]+" : Regexp.escape(seg[:text])
      end
      Regexp.new(parts.join("/"))
    end
  end
end
