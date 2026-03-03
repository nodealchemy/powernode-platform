# frozen_string_literal: true

module Api
  module V1
    module Webhooks
      class ContainerRegistryController < ApplicationController
        skip_before_action :authenticate_request
        skip_before_action :verify_authenticity_token, raise: false

        # POST /api/v1/webhooks/container_registry
        #
        # Receives build completion notifications from Gitea container image CI/CD.
        # Always returns 200 per webhook receiver rules (never 500 to avoid retry storms).
        def handle
          payload = parse_payload
          return render_ok unless payload

          template = find_template(payload)
          return render_ok("Template not found") unless template

          unless verify_signature(template.webhook_secret)
            Rails.logger.warn "[ContainerRegistry] Invalid signature for #{template.name}"
            return render_ok("Invalid signature")
          end

          process_build_event(template, payload)
          render_ok
        rescue StandardError => e
          Rails.logger.error "[ContainerRegistry] Webhook processing error: #{e.message}"
          render_ok("Processing error")
        end

        private

        def parse_payload
          body = request.body.read
          return nil if body.blank?

          @raw_body = body
          JSON.parse(body).with_indifferent_access
        rescue JSON::ParserError => e
          Rails.logger.warn "[ContainerRegistry] Invalid JSON payload: #{e.message}"
          nil
        end

        def find_template(payload)
          repo_name = payload[:repo] || payload.dig(:repository, :full_name)
          return nil unless repo_name

          Devops::ContainerTemplate.find_by(gitea_repo_full_name: repo_name)
        end

        def verify_signature(secret)
          return true if secret.blank? # No secret configured — accept all

          signature = request.headers["X-Gitea-Signature"] || request.headers["X-Hub-Signature-256"]
          return false unless signature

          # Handle sha256= prefix
          signature = signature.sub(/\Asha256=/, "")
          expected = OpenSSL::HMAC.hexdigest("sha256", secret, @raw_body)

          Rack::Utils.secure_compare(expected, signature)
        end

        def process_build_event(template, payload)
          image_tag = payload[:tag] || payload[:sha] || "latest"
          git_sha = payload[:tag] || payload[:sha]

          # Find or create a build record
          build = template.image_builds.find_by(git_sha: git_sha, status: "building") ||
                  template.image_builds.create!(
                    account: template.account,
                    trigger_type: "push",
                    status: "building",
                    git_sha: git_sha,
                    started_at: Time.current
                  )

          # Delegate to build service for completion + cascade handling
          Devops::ContainerImageBuildService.new(account: template.account)
            .handle_build_completed(
              template: template,
              image_tag: image_tag,
              git_sha: git_sha,
              build: build
            )

          Rails.logger.info "[ContainerRegistry] Processed build for #{template.name}: #{image_tag}"
        end

        def render_ok(message = "OK")
          render json: { status: "ok", message: message }, status: :ok
        end
      end
    end
  end
end
