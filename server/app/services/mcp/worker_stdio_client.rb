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
  # account_id is INFORMATIONAL ONLY, not an authorization check: the
  # worker never looks up an McpServer row (no ID crosses this boundary,
  # only the already-resolved raw command/args/env), so it has nothing to
  # verify account_id against. Tenancy is enforced BEFORE this seam, by
  # each call site's own account-scoped lookup of the `server`/`account`
  # it was constructed with (e.g. `current_user.account.mcp_servers.find`
  # in the prompts/resources controllers) — exactly as it was before this
  # class existed, since spawning locally never checked tenancy either.
  # account_id is passed through purely for worker-side observability
  # (logging, future per-account rate limiting), matching the same
  # non-authoritative role it already plays in WorkerEmbeddingClient.
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
    # Headroom on top of the worker's own deadline+grace (below) for the
    # worker's own HTTP request/response overhead (JSON parse, Rack
    # dispatch, network latency) — NOT part of the deadline math itself,
    # just margin so ordinary overhead never trips the outer HTTP timeout.
    READ_TIMEOUT_MARGIN_SECONDS = 5
    OPEN_TIMEOUT_SECONDS = 10

    class << self
      def execute(account_id:, server:, mcp_request:)
        transport.post('/api/v1/mcp/execute_stdio', {
          account_id: account_id,
          server: server,
          mcp_request: mcp_request
        }).deep_symbolize_keys
      end

      private

      # Not memoized: WorkerTransport re-resolves
      # Rails.application.config.worker_url on every .new, and
      # #read_timeout below re-reads MCP_STDIO_TIMEOUT_SECONDS on every
      # call (via Mcp::SecurityService.stdio_timeout_seconds, itself never
      # memoized) — a memoized transport would freeze a stale timeout if
      # the ENV var changes without a restart.
      def transport
        WorkerTransport.new(open_timeout: OPEN_TIMEOUT_SECONDS, read_timeout: read_timeout)
      end

      # MUST exceed the worker's own spawn_stdio deadline
      # (Mcp::SecurityService.stdio_timeout_seconds) plus its TERM->KILL
      # grace (Mcp::SecurityService::STDIO_TERM_GRACE_SECONDS) — otherwise
      # the SERVER gives up on the HTTP call before the WORKER gives up on
      # the child, and the operator sees a generic
      # WorkerTransport::TimeoutError ("worker timeout") instead of the
      # worker's own precise StdioTimeoutError message. The GRACE constant
      # is parity-spec-verified identical between the two apps, but the
      # DEADLINE (stdio_timeout_seconds) reads MCP_STDIO_TIMEOUT_SECONDS
      # from THIS process's own ENV — a parity spec run in one process
      # cannot see the other's live ENV. This sum is only exact when the
      # operator has actually set the SAME MCP_STDIO_TIMEOUT_SECONDS value
      # on both the server and the worker (see server/.env.example and
      # worker/.env.example) — a mismatch here is a deployment error, not
      # something this code can detect or correct for on its own.
      def read_timeout
        Mcp::SecurityService.stdio_timeout_seconds +
          Mcp::SecurityService::STDIO_TERM_GRACE_SECONDS +
          READ_TIMEOUT_MARGIN_SECONDS
      end
    end
  end
end
