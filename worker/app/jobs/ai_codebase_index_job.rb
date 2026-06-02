# frozen_string_literal: true

# Background job for codebase indexing via the server's internal API.
# Supports full and incremental indexing modes.
class AiCodebaseIndexJob < BaseJob
  include AiJobsConcern

  sidekiq_options queue: "code_intel", retry: 2

  def execute(params)
    validate_required_params(params, "account_id", "base_path")

    account_id = params["account_id"]
    base_path = params["base_path"]
    repository_id = params["repository_id"]
    path = params["path"]
    incremental = params.fetch("incremental", true)

    log_info("Starting codebase indexing",
             account_id: account_id,
             base_path: base_path,
             incremental: incremental)

    # Indexing can run for minutes (AST parse + embeddings) — use the
    # long-running path (3600s) instead of the default 120s timeout. The
    # payload is the request body itself (NOT wrapped in a `body:` key).
    response = api_client.post_with_circuit_breaker(
      "/api/v1/internal/codebase/index",
      {
        account_id: account_id,
        base_path: base_path,
        repository_id: repository_id,
        path: path,
        incremental: incremental
      }.compact,
      circuit_breaker: :code_intel
    )

    # handle_response returns the parsed JSON body (Hash) on 2xx and raises
    # BackendApiClient::ApiError on HTTP error. The body is the server's
    # render_success envelope: { "success" => true, "data" => {...} }.
    if response["success"]
      data = response["data"] || {}
      log_info("Codebase indexing completed",
               account_id: account_id,
               files_processed: data["files_processed"],
               nodes_created: data["nodes_created"])
    else
      log_error("Codebase indexing failed",
                account_id: account_id,
                error: response["error"] || response)
    end
  end
end
