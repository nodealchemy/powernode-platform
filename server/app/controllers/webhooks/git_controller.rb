# frozen_string_literal: true

# External webhook controller for Git provider events (GitHub, GitLab, Gitea).
module Webhooks
  class GitController < ApplicationController
    skip_before_action :authenticate_request
    skip_before_action :verify_authenticity_token, raise: false

    # POST /webhooks/git/:provider_type
    def handle
      provider_type = params[:provider_type]

      unless %w[github gitlab gitea].include?(provider_type)
        return render_error("Unknown provider", status: :bad_request)
      end

      # Find the repository by webhook payload
      repository = find_repository(provider_type)

      unless repository
        Rails.logger.warn "Git webhook: Repository not found for #{provider_type}"
        return render_error("Repository not found", status: :not_found)
      end

      # Verify webhook signature
      unless verify_signature(repository, provider_type)
        Rails.logger.warn "Git webhook: Invalid signature for #{repository.full_name}"
        return render_error("Invalid signature", status: :unauthorized)
      end

      # Create webhook event record
      event = create_webhook_event(repository, provider_type)

      # Queue processing job via worker API
      begin
        WorkerApiClient.new.queue_git_webhook_processing(event.id)
      rescue WorkerApiClient::ApiError => e
        Rails.logger.error "Failed to queue webhook processing: #{e.message}"
        # Update event status but continue - event was saved
        event.update(status: "queued_failed", error_message: e.message)
      end

      render_success({ received: true, event_id: event.id })
    rescue StandardError => e
      Rails.logger.error "Git webhook error: #{e.message}"
      Rails.logger.error e.backtrace.first(10).join("\n")
      render_error("Processing error", status: :internal_server_error)
    end

    private

    def find_repository(provider_type)
      full_name = extract_repository_name(provider_type)
      return nil unless full_name

      ::Devops::GitRepository.joins(credential: :provider)
                   .where(git_providers: { provider_type: provider_type })
                   .find_by(full_name: full_name)
    end

    def extract_repository_name(provider_type)
      case provider_type
      when "github"
        params.dig("repository", "full_name")
      when "gitlab"
        params.dig("project", "path_with_namespace")
      when "gitea"
        params.dig("repository", "full_name")
      end
    end

    def verify_signature(repository, provider_type)
      secret = repository.webhook_secret
      return false unless secret.present?

      case provider_type
      when "github"
        verify_github_signature(secret)
      when "gitlab"
        verify_gitlab_signature(secret)
      when "gitea"
        verify_gitea_signature(secret)
      else
        false
      end
    end

    def verify_github_signature(secret)
      signature = request.headers["X-Hub-Signature-256"]
      return false unless signature

      body = request.raw_post
      expected = "sha256=#{OpenSSL::HMAC.hexdigest('sha256', secret, body)}"
      Rack::Utils.secure_compare(expected, signature)
    end

    def verify_gitlab_signature(secret)
      token = request.headers["X-Gitlab-Token"]
      return false unless token

      Rack::Utils.secure_compare(secret, token)
    end

    def verify_gitea_signature(secret)
      # Gitea can use either GitHub-style HMAC or X-Gitea-Signature
      signature = request.headers["X-Gitea-Signature"] || request.headers["X-Hub-Signature-256"]
      return false unless signature

      body = request.raw_post

      if signature.start_with?("sha256=")
        expected = "sha256=#{OpenSSL::HMAC.hexdigest('sha256', secret, body)}"
        Rack::Utils.secure_compare(expected, signature)
      else
        expected = OpenSSL::HMAC.hexdigest("sha256", secret, body)
        Rack::Utils.secure_compare(expected, signature)
      end
    end

    def create_webhook_event(repository, provider_type)
      event_type = extract_event_type(provider_type)
      action = extract_action(provider_type)

      repository.git_webhook_events.create!(
        git_provider: repository.git_provider,
        account: repository.account,
        event_type: event_type,
        action: action,
        delivery_id: extract_delivery_id(provider_type),
        payload: webhook_payload,
        headers: extract_headers,
        sender_username: extract_sender_username(provider_type),
        sender_id: extract_sender_id(provider_type),
        ref: extract_ref(provider_type),
        sha: extract_sha(provider_type),
        status: "pending"
      )
    end

    def extract_event_type(provider_type)
      case provider_type
      when "github"
        request.headers["X-GitHub-Event"]
      when "gitlab"
        request.headers["X-Gitlab-Event"]&.downcase&.gsub(" hook", "")&.gsub(" ", "_")
      when "gitea"
        request.headers["X-Gitea-Event"] || request.headers["X-GitHub-Event"]
      end || "unknown"
    end

    def extract_action(provider_type)
      payload = webhook_payload
      case provider_type
      when "github", "gitea"
        payload["action"]
      when "gitlab"
        payload.dig("object_attributes", "action") || payload.dig("object_attributes", "state")
      end
    end

    def extract_delivery_id(provider_type)
      case provider_type
      when "github"
        request.headers["X-GitHub-Delivery"]
      when "gitlab"
        request.headers["X-Gitlab-Event-UUID"]
      when "gitea"
        request.headers["X-Gitea-Delivery"] || request.headers["X-GitHub-Delivery"]
      end
    end

    def extract_sender_username(provider_type)
      case provider_type
      when "github", "gitea"
        params.dig("sender", "login")
      when "gitlab"
        params.dig("user", "username")
      end
    end

    def extract_sender_id(provider_type)
      case provider_type
      when "github", "gitea"
        params.dig("sender", "id")&.to_s
      when "gitlab"
        params.dig("user", "id")&.to_s
      end
    end

    def extract_ref(provider_type)
      params["ref"] || params.dig("object_attributes", "ref")
    end

    def extract_sha(provider_type)
      case provider_type
      when "github", "gitea"
        params["after"] || params.dig("head_commit", "id") || params.dig("pull_request", "head", "sha")
      when "gitlab"
        params["after"] || params.dig("object_attributes", "last_commit", "id")
      end
    end

    def extract_headers
      relevant_headers = %w[
        X-GitHub-Event X-GitHub-Delivery X-GitHub-Hook-ID
        X-Gitlab-Event X-Gitlab-Event-UUID X-Gitlab-Token
        X-Gitea-Event X-Gitea-Delivery
        Content-Type User-Agent
      ]

      relevant_headers.each_with_object({}) do |header, result|
        value = request.headers[header]
        result[header] = value if value.present?
      end
    end

    def webhook_payload
      # Get JSON payload, handling both JSON body and form-encoded
      if request.content_type&.include?("application/json")
        JSON.parse(request.raw_post)
      else
        params.except(:controller, :action, :provider_type).to_unsafe_h
      end
    rescue JSON::ParserError
      params.except(:controller, :action, :provider_type).to_unsafe_h
    end
  end
end
