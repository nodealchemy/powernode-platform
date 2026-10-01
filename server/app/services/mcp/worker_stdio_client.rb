# frozen_string_literal: true

module Mcp
  # Synchronous server -> worker bridge for stdio MCP execution
  # (IMP-abda86fb39be, MCP isolation Phase 0 T1). The server no longer
  # spawns stdio MCP children itself (see Mcp::SecurityService's class
  # comment) — each call site validates locally first, for early, no-
  # network-hop refusal of an obviously bad config (Mcp::SecurityService
  # .validate_stdio_server!), then hands the request here. This POSTs the
  # already-resolved command/args/env plus the JSON-RPC request to the
  # worker's synchronous /api/v1/mcp/execute_stdio endpoint (a Rack
  # dispatcher in worker/app/controllers/jobs_controller.rb), reached via
  # the SAME shared WorkerTransport every other server -> worker
  # synchronous call already uses (WorkerLlmClient, WorkerEmbeddingClient,
  # WorkerApiClient). The worker independently re-validates via its OWN
  # validate_stdio_server! before it ever spawns anything — this class's
  # caller having already validated is a fast local refusal, never the
  # only gate; the worker's copy is the one that actually matters, since
  # it is the one standing between this request and Process.spawn.
  #
  # account_id is NOT an authorization check: the
  # worker never looks up an McpServer row (no ID crosses this boundary,
  # only the already-resolved raw command/args/env), so it has nothing to
  # verify account_id against. Tenancy is enforced BEFORE this seam, by
  # each call site's own account-scoped lookup of the `server`/`account`
  # it was constructed with (e.g. `current_user.account.mcp_servers.find`
  # in the prompts/resources controllers) — exactly as it was before this
  # class existed, since spawning locally never checked tenancy either.
  # It IS load-bearing for isolation (IMP-bd260c0b4c00): the worker keys
  # the stdio sandbox identity (User=/CacheDirectory=) on it, so one
  # account's child cannot read another's process environment or poison
  # its package cache. The call sites also put the MCP server's OWNING
  # account in `server['account_id']` (the identity key, as on the async
  # path); the worker refuses a request whose account_id disagrees.
  #
  # RETURN CONTRACT: mirrors exactly what Mcp::PromptService/
  # Mcp::ResourceService#send_stdio_request used to return when it spawned
  # locally — a symbolized Hash with either a `:result` key (the parsed
  # JSON-RPC response) or an `:error` key (`{ message: "..." }`), for
  # EVERY domain-level outcome (security violation, timeout, process
  # failure, no valid response). Each call site's existing post-processing
  # of that shape is unchanged. WorkerTransport-level failures (worker
  # unreachable, worker 5xx, malformed worker response) are NOT translated
  # here — they propagate as WorkerTransport::HttpError/TimeoutError/
  # ConnectionError (all StandardError subclasses), which each call site's
  # own existing outer `rescue StandardError` already catches. This is a
  # genuinely NEW failure mode (execution used to be in-process, so a
  # "worker unreachable" case couldn't previously occur) — there is no
  # pre-existing shape to preserve for it beyond that generic catch-all.
  class WorkerStdioClient
    # IMP-f010c9fc7051 — the stdio deadline for THIS synchronous path is
    # DB-driven config, read per call (so a change needs no restart), with
    # DEFAULT_TIMEOUT_SECONDS as the fallback, the same unseeded-key pattern
    # as Mcp::ToolCatalog's description limit. Every caller here is a Puma
    # request thread (the prompts/resources controllers, a synchronous tool
    # call), held for deadline + TERM grace + READ_TIMEOUT_MARGIN_SECONDS
    # in the worst case. The default is therefore 15s, a 22s worst-case
    # hold on a 16-thread pool, against the 37s the old shared 30s default
    # cost. The worker's async jobs keep their own longer default. A
    # cold package fetch (each request spawns the child fresh) is the
    # realistic slow case; that is what the setting lets an operator raise.
    TIMEOUT_SETTING = "mcp.stdio.timeout_seconds"
    DEFAULT_TIMEOUT_SECONDS = 15

    # Headroom on top of the worker's own deadline+grace (below) for the
    # worker's own HTTP request/response overhead (JSON parse, Rack
    # dispatch, network latency) — NOT part of the deadline math itself,
    # just margin so ordinary overhead never trips the outer HTTP timeout.
    READ_TIMEOUT_MARGIN_SECONDS = 5
    OPEN_TIMEOUT_SECONDS = 10

    class << self
      # `timeout:` is the deadline the worker enforces on the child, sent in
      # the request body; the worker refuses one it does not accept (see
      # Mcp::SecurityService::MAX_STDIO_TIMEOUT_SECONDS). Required, so every
      # call site states it — normally .timeout_seconds below.
      def execute(account_id:, server:, mcp_request:, timeout:)
        transport(timeout).post("/api/v1/mcp/execute_stdio", {
          account_id: account_id,
          server: server,
          mcp_request: mcp_request,
          timeout_seconds: timeout
        }).deep_symbolize_keys
      end

      # The operator-configured deadline. Anything but a positive decimal
      # integer (a fraction, a boolean, "010" read as octal) is ignored for
      # the default rather than honoured; a value above the worker's
      # ceiling is clamped to it, since the worker would refuse it outright.
      def timeout_seconds
        value = Integer(::SiteSetting.get(TIMEOUT_SETTING).to_s, 10, exception: false)
        return DEFAULT_TIMEOUT_SECONDS unless value&.positive?

        [ value, Mcp::SecurityService::MAX_STDIO_TIMEOUT_SECONDS ].min
      end

      private

      # Not memoized: WorkerTransport re-resolves
      # Rails.application.config.worker_url on every .new, and its
      # read_timeout follows each call's own deadline.
      def transport(timeout)
        WorkerTransport.new(open_timeout: OPEN_TIMEOUT_SECONDS, read_timeout: read_timeout(timeout))
      end

      # MUST exceed the deadline the worker is told to enforce plus its
      # TERM->KILL grace (Mcp::SecurityService::STDIO_TERM_GRACE_SECONDS,
      # parity-spec-verified identical to the worker's) — otherwise the
      # SERVER gives up on the HTTP call before the WORKER gives up on the
      # child, and the operator sees a generic WorkerTransport::TimeoutError
      # ("worker timeout") instead of the worker's own precise
      # StdioTimeoutError message. Both ends now use the same per-call
      # number, so they cannot disagree the way two separately set ENV
      # values could.
      def read_timeout(timeout)
        timeout +
          Mcp::SecurityService::STDIO_TERM_GRACE_SECONDS +
          READ_TIMEOUT_MARGIN_SECONDS
      end
    end
  end
end
