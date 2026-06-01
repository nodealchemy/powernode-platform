# frozen_string_literal: true

# Background job for long-running codebase analysis (prune_stale,
# find_duplicates) via the server's internal API. These scans iterate the full
# code knowledge graph (file-existence checks, embedding-similarity), so they
# run on the worker rather than blocking the MCP/user request path.
#
# The server-side endpoint writes the result to the account's "default"
# shared-memory pool under `result_key`; callers retrieve it with
# read_shared_memory(pool_id: "default", key: result_key).
class AiCodeAnalysisJob < BaseJob
  include AiJobsConcern

  sidekiq_options queue: "default", retry: 2

  def execute(params)
    validate_required_params(params, "operation", "account_id", "base_path", "result_key")

    operation = params["operation"]

    log_info("Starting codebase analysis",
             operation: operation,
             account_id: params["account_id"],
             result_key: params["result_key"])

    # Long-running scan → 3600s timeout path. Payload is the request body.
    response = api_client.post_with_circuit_breaker(
      "/api/v1/internal/codebase/analyze",
      {
        operation: operation,
        account_id: params["account_id"],
        base_path: params["base_path"],
        repository_id: params["repository_id"],
        result_key: params["result_key"],
        options: params["options"] || {}
      }.compact
    )

    if response.success?
      data = response.parsed_response
      log_info("Codebase analysis completed",
               operation: operation,
               result_key: params["result_key"],
               summary: data.dig("data", "summary"))
    else
      log_error("Codebase analysis failed",
                operation: operation,
                status: response.code,
                error: response.body)
    end
  end
end
