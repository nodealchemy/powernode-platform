# frozen_string_literal: true

require "base64"
require_relative "../../services/devops/git_operations_service"
require_relative "../../services/devops/increment_merge_service"

module Git
  # Runs one APPROVED dev_merge_increment (dispatched by the server's
  # Ai::Tools::DevMergeTool on the approved replay; nothing else enqueues it)
  # and reports the outcome to /api/v1/internal/ai/dev_merges/:id/report,
  # where the audit row is written. The git work is
  # Devops::IncrementMergeService; this job resolves each remote's URL and
  # credential over the internal API and posts the report.
  #
  # retry: 0. A merge is not retried blind: a second run after a partial push
  # would re-push on a state nobody approved. A failure is REPORTED, and a
  # person decides whether to park it again.
  class DevMergeIncrementJob < BaseJob
    include AiSuspensionCheckConcern

    sidekiq_options queue: "services", retry: 0

    # The payload carries private-extension names for the message check. They
    # are not secret, but they do not belong in a log line either.
    def self.redact_args(args)
      super(args).map do |arg|
        next arg unless arg.is_a?(Hash) && arg.key?("forbidden_names")

        arg.merge("forbidden_names" => "[#{Array(arg['forbidden_names']).size} names]")
      end
    end

    def execute(payload)
      operation_id = payload["deferred_operation_id"]
      report = bail_if_ai_suspended!(payload["account_id"]) ? suspended_report : merge(payload)

      log_info "dev merge #{operation_id}: #{report['status']}",
               stage: report["stage"], remotes: report["remotes"].size
      api_client.post("/api/v1/internal/ai/dev_merges/#{operation_id}/report", report)
      report
    end

    private

    def merge(payload)
      Devops::IncrementMergeService.new(
        payload: payload,
        remote_resolver: method(:resolve_remote),
        git_ops_factory: ->(config) { Devops::GitOperationsService.new(provider_config: config, logger: logger) },
        logger: logger
      ).call
    end

    def suspended_report
      { "status" => "failed", "stage" => "kill_switch",
        "error" => "AI is suspended for this account (kill switch); nothing was merged",
        "remotes" => [], "pointer_remotes" => [] }
    end

    # URL, credential and provider config for one repository, read from the
    # server's internal API. The token never enters a URL or argv: it travels
    # as an Authorization header through Devops::GitCli.
    def resolve_remote(repository_id)
      repository = api_client.get("/api/v1/internal/git/repositories/#{repository_id}")["data"]
      raise ArgumentError, "repository not found" unless repository.is_a?(Hash)

      credential_id = repository.dig("credential", "id")
      raise ArgumentError, "repository has no credential" if credential_id.to_s.empty?

      credential = api_client.get("/api/v1/internal/git/credentials/#{credential_id}/decrypted")["data"]
      secrets = credential["credentials"] || {}
      token = secrets["access_token"] || secrets["token"]
      raise ArgumentError, "credential has no token" if token.to_s.empty?

      username = secrets["username"].to_s.empty? ? "git" : secrets["username"].to_s
      basic = Base64.strict_encode64("#{username}:#{token}")
      provider_type = repository.dig("credential", "provider_type") || credential.dig("provider", "provider_type")
      api_url = repository.dig("credential", "provider", "api_base_url") || credential.dig("provider", "api_base_url")

      {
        url: repository["clone_url"],
        full_name: repository["full_name"],
        auth_header: "Authorization: Basic #{basic}",
        secrets: [ token, basic ],
        api_config: { "provider_type" => provider_type, "api_url" => provider_api_url(provider_type, api_url),
                      "access_token" => token }
      }
    end

    # The server stores a Gitea provider's api_base_url WITH its "/api/vN"
    # suffix (its own client requests "/user" relative to it; see
    # Devops::GitProvider#default_web_base_url), while this worker's
    # GiteaProvider appends "/api/v1" itself. Strip it so the two agree.
    def provider_api_url(provider_type, api_url)
      return api_url unless provider_type.to_s == "gitea" && api_url.is_a?(String)

      api_url.sub(%r{/api/v\d+/?\z}, "")
    end
  end
end
