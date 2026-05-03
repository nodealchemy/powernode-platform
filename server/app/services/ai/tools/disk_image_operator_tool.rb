# frozen_string_literal: true

module Ai
  module Tools
    # MCP wrappers for the disk-image registration operator workflow.
    # Each action collapses what would otherwise be 4-7 separate API
    # calls + manual secret-paste-into-Gitea into a single operator-
    # meaningful step.
    #
    # Highest-leverage action: `bootstrap_disk_image_ci` — provisions a
    # webhook + CI worker via the platform API, sets all 4 needed
    # secrets in the Gitea repo via the Gitea Actions API, returns the
    # webhook URL + secret previews. After this single call, an
    # operator's CI workflow can publish disk images end-to-end.
    #
    # Plan: docs/plans/wondrous-yawning-anchor.md (Phase 2 — operator UX).
    class DiskImageOperatorTool < BaseTool
      REQUIRED_PERMISSION = "system.platforms.publish_disk_image"

      ACTIONS = %w[
        provision_disk_image_webhook
        provision_ci_worker
        bootstrap_disk_image_ci
      ].freeze

      def self.definition
        {
          name: "disk_image_operator",
          description: "One-shot operator wrappers for disk-image webhook + CI worker provisioning + Gitea secret setup",
          parameters: {
            action: { type: "string", required: true, description: "One of: #{ACTIONS.join(', ')}" }
          }
        }
      end

      def self.action_definitions
        {
          "provision_disk_image_webhook" => {
            description: "Create a per-pipeline disk-image webhook for the current account. Returns plaintext secret + absolute URL EXACTLY ONCE — caller must capture both, no recovery.",
            parameters: {
              label: { type: "string", required: true, description: "Operator-chosen identifier (unique per account, e.g. 'main-ci', 'release-pipeline')" }
            }
          },
          "provision_ci_worker" => {
            description: "Create a per-pipeline CI worker (narrowly scoped: system.platforms.publish_disk_image only). Returns plaintext token EXACTLY ONCE.",
            parameters: {
              name:        { type: "string", required: true,  description: "Operator-chosen name (e.g. 'release-pipeline-runner')" },
              description: { type: "string", required: false, description: "Optional description shown in the operator UI" }
            }
          },
          "bootstrap_disk_image_ci" => {
            description: "End-to-end setup: provision webhook + CI worker, set all 4 needed Gitea Actions secrets in one call (POWERNODE_DISK_IMAGE_WEBHOOK_URL, POWERNODE_DISK_IMAGE_WEBHOOK_SECRET, POWERNODE_CI_WORKER_TOKEN, POWERNODE_API_BASE). Idempotent: re-running with the same label updates existing rows + re-sets secrets.",
            parameters: {
              owner:           { type: "string", required: true,  description: "Gitea repo owner" },
              repo:            { type: "string", required: true,  description: "Gitea repo name" },
              label:           { type: "string", required: true,  description: "Operator-chosen identifier (used for both webhook label and CI worker name)" },
              platform_api_base: { type: "string", required: false, description: "Public-routable platform API base URL CI runners will call back to (default: ENV['POWERNODE_PUBLIC_URL'] or 'http://localhost:3000')" }
            }
          }
        }
      end

      protected

      def call(params)
        case params[:action].to_s
        when "provision_disk_image_webhook" then provision_webhook(params)
        when "provision_ci_worker"          then provision_ci_worker(params)
        when "bootstrap_disk_image_ci"      then bootstrap(params)
        else
          { success: false, error: "Unknown action: #{params[:action].inspect} (supported: #{ACTIONS.join(', ')})" }
        end
      end

      private

      def provision_webhook(params)
        label = params[:label].to_s
        return { success: false, error: "label required" } if label.blank?

        webhook, secret = ::System::DiskImageWebhook.create_with_secret!(
          account: account,
          label:   label
        )
        {
          success: true,
          webhook_id:       webhook.id,
          label:            webhook.label,
          secret_plaintext: secret,
          webhook_url:      build_webhook_url(webhook),
          note:             "Save secret + URL now — secret is not recoverable. Rotate to replace."
        }
      rescue ActiveRecord::RecordInvalid => e
        { success: false, error: "Validation failed: #{e.record.errors.full_messages.join(', ')}" }
      end

      def provision_ci_worker(params)
        name = params[:name].to_s
        return { success: false, error: "name required" } if name.blank?

        worker = ::Worker.create_worker!(
          name:        name,
          description: params[:description].to_s.presence,
          account:     account,
          roles:       ["ci_worker"]
        )
        {
          success: true,
          worker_id:       worker.id,
          name:            worker.name,
          token_plaintext: worker.token,
          roles:           worker.roles.pluck(:name),
          note:             "Save token now — not recoverable. Use as POWERNODE_CI_WORKER_TOKEN in your CI."
        }
      rescue StandardError => e
        { success: false, error: "Failed to create CI worker: #{e.message}" }
      end

      # End-to-end: provision webhook + CI worker → set all 4 Gitea
      # secrets → return summary. Idempotent on the label/name (will
      # rotate if existing webhook/worker has same label).
      def bootstrap(params)
        owner = params[:owner].to_s
        repo  = params[:repo].to_s
        label = params[:label].to_s
        return { success: false, error: "owner/repo/label all required" } if [owner, repo, label].any?(&:blank?)

        platform_api_base = params[:platform_api_base].to_s.presence ||
                            ENV.fetch("POWERNODE_PUBLIC_URL", "http://localhost:3000")

        # Reuse-or-create webhook (same label = rotate secret on existing).
        existing_webhook = ::System::DiskImageWebhook.find_by(account: account, label: label)
        if existing_webhook
          webhook_secret = existing_webhook.rotate_secret!
          webhook = existing_webhook
          webhook_action = "rotated_secret_for_existing"
        else
          webhook, webhook_secret = ::System::DiskImageWebhook.create_with_secret!(
            account: account, label: label
          )
          webhook_action = "created_new"
        end

        # Reuse-or-create CI worker.
        existing_worker = account.workers.joins(:roles).where(roles: { name: "ci_worker" }, name: label).first
        if existing_worker
          new_token = "swt_#{SecureRandom.urlsafe_base64(32)}"
          existing_worker.update!(token_digest: ::Digest::SHA256.hexdigest(new_token))
          worker = existing_worker
          worker_token = new_token
          worker_action = "rotated_token_for_existing"
        else
          worker = ::Worker.create_worker!(
            name:    label,
            account: account,
            roles:   ["ci_worker"]
          )
          worker_token = worker.token
          worker_action = "created_new"
        end

        # Push all 4 secrets to Gitea via the GiteaActionsTool's underlying client.
        gitea_credential = find_gitea_credential
        return { success: false, error: "No active Gitea credential found for this account" } unless gitea_credential

        gitea_client = ::Devops::Git::ApiClient.for(gitea_credential)
        secret_results = {}
        {
          "POWERNODE_DISK_IMAGE_WEBHOOK_URL"    => build_webhook_url(webhook),
          "POWERNODE_DISK_IMAGE_WEBHOOK_SECRET" => webhook_secret,
          "POWERNODE_CI_WORKER_TOKEN"           => worker_token,
          "POWERNODE_API_BASE"                  => platform_api_base
        }.each do |k, v|
          result = gitea_client.create_or_update_action_secret(owner, repo, k, v)
          secret_results[k] = result[:success] ? "ok" : "error: #{result[:error]}"
        end

        {
          success: true,
          webhook:  { id: webhook.id, label: webhook.label, action: webhook_action, url: build_webhook_url(webhook), secret_preview: webhook_secret[0, 12] + "..." },
          ci_worker: { id: worker.id, name: worker.name, action: worker_action, token_preview: worker_token[0, 12] + "..." },
          gitea_secrets_set: secret_results,
          note:    "Operator's CI workflow can now publish disk images. Trigger via dispatch_gitea_workflow or push a tag."
        }
      rescue StandardError => e
        { success: false, error: "Bootstrap failed: #{e.class}: #{e.message}" }
      end

      def build_webhook_url(webhook)
        base = ENV.fetch("POWERNODE_PUBLIC_URL", "http://localhost:3000")
        "#{base}/api/v1/system/webhooks/disk_image/built/#{webhook.id}"
      end

      def find_gitea_credential
        gitea_provider = ::Devops::GitProvider.find_by(provider_type: "gitea")
        return nil unless gitea_provider

        account.git_provider_credentials
               .where(git_provider_id: gitea_provider.id, is_active: true)
               .order(is_default: :desc, created_at: :desc)
               .first
      end
    end
  end
end
