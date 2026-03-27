# frozen_string_literal: true

# Background job for codebase indexing via the server's internal API.
# Supports full and incremental indexing modes.
class AiCodebaseIndexJob < BaseJob
  include AiJobsConcern

  sidekiq_options queue: "default", retry: 2

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

    response = api_client.post(
      "/api/v1/internal/codebase/index",
      body: {
        account_id: account_id,
        base_path: base_path,
        repository_id: repository_id,
        path: path,
        incremental: incremental
      }.compact
    )

    if response.success?
      data = response.parsed_response
      log_info("Codebase indexing completed",
               account_id: account_id,
               files_processed: data.dig("data", "files_processed"),
               nodes_created: data.dig("data", "nodes_created"))
    else
      log_error("Codebase indexing failed",
                account_id: account_id,
                status: response.code,
                error: response.body)
    end
  end
end
