# frozen_string_literal: true

module Ai
  module Tools
    # MCP wrappers for the disk-image registration operator workflow.
    # Each action collapses what would otherwise be 4-7 separate API
    # calls + manual secret-paste-into-Gitea into a single operator-
    # meaningful step.
    #
    # Highest-leverage action: `bootstrap_disk_image_ci` — provisions a
    # webhook + CI worker via the platform API and sets all 4 needed
    # secrets in the Gitea repo via the Gitea Actions API. After this
    # single call, an operator's CI workflow can publish disk images
    # end-to-end, and no plaintext ever rode the tool result: delivery
    # happened out of band, into Gitea's own secret store.
    #
    # SECRET DISCLOSURE (IMP-fa6cf8ee1eb6). No action here returns minted
    # key material — not in full, and not as a prefix "preview". A tool
    # RESULT is not a private channel the way an HTTP response is:
    # Ai::AgentToolBridgeService writes a 200-byte preview of it into
    # `tool_calls_log`, which Api::V1::Ai::ConversationsController persists
    # into ai_messages.processing_metadata (a durable jsonb column, never
    # re-filtered on read — Ai::SensitiveParams cannot reach it, since the
    # value is a String and `filter` returns non-Hash input unchanged), and
    # it appends the FULL json as a role:"tool" message sent to the model
    # provider on the next turn. So a mint that is correctly "shown once,
    # never stored" on the REST twin becomes, here, a durable at-rest copy
    # AND an outbound transmission to a third party.
    #
    # The REST twins are NOT the problem and are deliberately unchanged:
    # Api::V1::System::DiskImageWebhooksController#create/#rotate_secret and
    # Api::V1::System::CiWorkersController#create/#rotate_token reveal the
    # plaintext in an HTTP response, which acquires neither sink.
    #
    # This surface therefore returns a REFERENCE plus the retrieval path,
    # which is the shape Ai::Tools::AgentAutonomyTool#approve_deferred_operation
    # and Ai::Tools::SdwanTool#propose_federation_peer already hold. It does
    # not STRAND the caller: unlike a single-use federation acceptance token,
    # both of these have an operator-facing rotate endpoint that mints a fresh
    # usable secret on demand, named in the result.
    #
    # TWO CAVEATS ON THAT RETRIEVAL PATH, stated in the returned strings
    # because an agent reading only the result must know them:
    #
    #   * ci_workers#rotate_token is ungated and answers in one 200.
    #     disk_image_webhooks#rotate_secret is `gate!`-wrapped, and
    #     Ai::InterventionPolicyService#default_policy is "require_approval"
    #     whenever no policy row matches — the seeded declaration for
    #     system.disk_image_webhook_rotate_secret is "notify_and_proceed", but
    #     seeds do not re-run on an existing deployment, so `pending` is a live
    #     possibility. On that branch the plaintext reaches the approver
    #     through the reveal-once slot (IMP-7b81ca22f661) in the HTTP approval
    #     decision — and NOT through approve_deferred_operation, which
    #     deliberately drops it (agent_autonomy_tool.rb) and consumes the
    #     operation. So: approve over the operator UI/API.
    #   * this tool gates on system.platforms.publish_disk_image; the two
    #     retrieval endpoints gate on system.disk_image_webhooks.rotate_secret
    #     and system.ci_workers.rotate_token. Holding the tool does not imply
    #     holding either.
    #
    # Plan: docs/plans/wondrous-yawning-anchor.md (Phase 2 — operator UX).
    class DiskImageOperatorTool < BaseTool
      REQUIRED_PERMISSION = "system.platforms.publish_disk_image"

      ACTIONS = %w[
        provision_disk_image_webhook
        provision_ci_worker
        bootstrap_disk_image_ci
      ].freeze

      # CORE MODE (IMP-8f6ade11fbdf): this class is core-HOSTED but
      # extension-BACKED — `provision_disk_image_webhook` and
      # `bootstrap_disk_image_ci` both run through ::System::DiskImageWebhook,
      # which ships in extensions/system. PlatformApiToolRegistry.available_tools
      # drops extension-HOSTED tool classes on their own (constantize raises
      # NameError, which it rescues), but this class constantizes fine with the
      # extension absent, so all three actions stayed in tools/list and
      # provision_disk_image_webhook / bootstrap_disk_image_ci answered a call
      # with -32603 "Internal error: uninitialized constant System::...".
      #
      # This is the SAME defect class IMP-2836d290f99a (commit 5d4bcabc4) fixed
      # for Ai::Tools::DockerProvisioningTool — that commit named this class as
      # the other known instance and filed it separately. It is NOT the same
      # SHAPE, though: DockerProvisioningTool's four actions are all
      # extension-backed, so gating `.permitted?` for the whole class was
      # correct there. Here only 2 of 3 actions depend on the extension —
      # `provision_ci_worker` runs entirely on core's own ::Worker model and
      # must stay advertised and working with the extension absent. Gating the
      # whole class the same way would silently regress a core-only action, so
      # the guard is per-ACTION (`.action_advertised?`, a new hook
      # PlatformApiToolRegistry.available_tools consults) rather than
      # per-class (`.permitted?`).
      #
      # #action_advertised? is the ADVERTISEMENT gate for the surfaces that
      # filter on it (available_tools -> tools/list, AgentToolBridgeService,
      # ConciergeToolBridge, all of which call tool_definitions ->
      # available_tools): an action that cannot work must not be advertised.
      # #call covers invocation, since find_tool / McpPlatformToolRegistrar
      # resolve tools/call straight off the registry hash WITHOUT consulting
      # available_tools at all, so a client holding a stale catalog can still
      # invoke a de-advertised action and gets a plain envelope instead of a
      # NameError.
      #
      # CLOSED BY IMP-5039d026da0d (the three surfaces named in 5d4bcabc4's
      # commit message): McpPlatformToolRegistrar.sync_to_database! and
      # SemanticToolDiscoveryService#collect_all_tools now consult
      # PlatformApiToolRegistry.advertised_action?, which applies THIS hook, so
      # provision_disk_image_webhook / bootstrap_disk_image_ci drop out of the
      # DB-backed MCP browser catalog and the semantic discovery index in core
      # mode too. .register_all! filters per CLASS (.advertised_class?), which
      # correctly keeps this class's manifest — provision_ci_worker is core-only.
      #
      # NOT closed for that class manifest, stated so the block above is not read
      # as more than it is: McpPlatformToolRegistrar#build_manifest derives
      # "inputSchema" from `.definition[:parameters]`, and this class's `action`
      # parameter describes itself as "One of: #{ACTIONS.join(', ')}" — all
      # three names, unconditionally. So the ActionCable catalog served out of
      # Mcp::RegistryService still NAMES provision_disk_image_webhook and
      # bootstrap_disk_image_ci in core mode. Only the per-ACTION surfaces
      # (tools/list, the mcp_tools rows, the semantic index) drop them. Making
      # the manifest per-action is a register_all!-shaped change, not this hook's
      # job, and a call to either action still meets the envelope above.
      #
      # .tool_classes stays unfiltered on purpose: it is the RESOLUTION set
      # behind #find_tool_class, so a stale-catalog tools/call on the live
      # streamable-HTTP wire still reaches the envelope above.
      EXTENSION_BACKED_ACTIONS = %w[provision_disk_image_webhook bootstrap_disk_image_ci].freeze

      def self.extension_available?
        defined?(::System::DiskImageWebhook) ? true : false
      end

      def self.action_advertised?(action_name)
        return true unless EXTENSION_BACKED_ACTIONS.include?(action_name.to_s)

        extension_available?
      end

      # APO-1a (IMP-1e58753b3b6c) — governance declarations for every action
      # this tool advertises. NON-ENFORCING: `mutating:` alone leaves
      # BaseTool#gated_action? false, so #execute still routes to #call and
      # behaviour is unchanged. Gate wiring (categories/executors) is APO-1e.
      declare_action "bootstrap_disk_image_ci", mutating: true
      declare_action "provision_ci_worker", mutating: true
      declare_action "provision_disk_image_webhook", mutating: true

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
            description: "Create a per-pipeline disk-image webhook for the current account. Returns the webhook id + absolute URL. The plaintext secret is NOT returned on this surface — a tool result is persisted with the conversation and forwarded to the model provider. The webhook is inert until you fetch a secret: POST /api/v1/system/disk_image_webhooks/<id>/rotate_secret (separate permission; approval-gated — if it answers pending, the plaintext is revealed once in the HTTP approval-decision response, so approve via the operator UI/API, not via approve_deferred_operation). Or use bootstrap_disk_image_ci, which writes the secret straight into the repo's Gitea Actions secrets without returning it.",
            parameters: {
              label: { type: "string", required: true, description: "Operator-chosen identifier (unique per account, e.g. 'main-ci', 'release-pipeline')" }
            }
          },
          "provision_ci_worker" => {
            description: "Create a per-pipeline CI worker (narrowly scoped: system.platforms.publish_disk_image only). Returns the worker id + roles. The plaintext token is NOT returned on this surface — a tool result is persisted with the conversation and forwarded to the model provider. Obtain the token exactly once via POST /api/v1/system/ci_workers/<id>/rotate_token (ungated, separate permission), or use bootstrap_disk_image_ci, which writes it straight into the repo's Gitea Actions secrets without returning it.",
            parameters: {
              name:        { type: "string", required: true,  description: "Operator-chosen name (e.g. 'release-pipeline-runner')" },
              description: { type: "string", required: false, description: "Optional description shown in the operator UI" }
            }
          },
          "bootstrap_disk_image_ci" => {
            description: "End-to-end setup: provision webhook + CI worker, set all 4 needed Gitea Actions secrets in one call (POWERNODE_DISK_IMAGE_WEBHOOK_URL, POWERNODE_DISK_IMAGE_WEBHOOK_SECRET, POWERNODE_CI_WORKER_TOKEN, POWERNODE_API_BASE). Optionally also mints a Gitea PAT and sets it as PLATFORM_READ_TOKEN for the parent platform checkout step. Idempotent: re-running with the same label rotates secrets + token.",
            parameters: {
              owner:           { type: "string",  required: true,  description: "Gitea repo owner" },
              repo:            { type: "string",  required: true,  description: "Gitea repo name" },
              label:           { type: "string",  required: true,  description: "Operator-chosen identifier (used for both webhook label and CI worker name)" },
              platform_api_base: { type: "string", required: false, description: "Public-routable platform API base URL CI runners will call back to (default: ENV['POWERNODE_PUBLIC_URL'] or 'http://localhost:3000')" },
              create_platform_read_token: { type: "boolean", required: false, description: "When true (default false), mint a Gitea PAT with read:repository scope and set it as PLATFORM_READ_TOKEN secret in the same repo. Closes the manual 'go to Gitea web UI to generate a PAT' step." },
              platform_read_token_name:   { type: "string",  required: false, description: "Override the auto-generated PAT name (default: '<label>-platform-ci-readonly')" }
            }
          }
        }
      end

      protected

      def call(params)
        action = params[:action].to_s
        return extension_unavailable_error(action) if EXTENSION_BACKED_ACTIONS.include?(action) && !self.class.extension_available?

        case action
        when "provision_disk_image_webhook" then provision_webhook(params)
        when "provision_ci_worker"          then provision_ci_worker(params)
        when "bootstrap_disk_image_ci"      then bootstrap(params)
        else
          { success: false, error: "Unknown action: #{params[:action].inspect} (supported: #{ACTIONS.join(', ')})" }
        end
      end

      private

      def extension_unavailable_error(action)
        { success: false,
          error: "#{action} requires the 'system' extension, which is not installed on this control plane. " \
                 "This action is not advertised in core mode." }
      end

      def provision_webhook(params)
        label = params[:label].to_s
        return { success: false, error: "label required" } if label.blank?

        # The mint happens (the row needs a digest) and is then DROPPED on the
        # floor — deliberately. `secret` is never bound into the return, so it
        # reaches neither ai_messages.processing_metadata nor the provider. The
        # webhook is fully usable the moment the operator rotates, which is the
        # named retrieval path below; nothing is stranded.
        webhook, _unreturned_secret = ::System::DiskImageWebhook.create_with_secret!(
          account: account,
          label:   label
        )
        {
          success: true,
          webhook_id:       webhook.id,
          label:            webhook.label,
          webhook_url:      build_webhook_url(webhook),
          secret_delivery:  "not disclosed here — a tool result is persisted with the conversation and forwarded to the model provider. " \
                            "Get the plaintext at POST /api/v1/system/disk_image_webhooks/#{webhook.id}/rotate_secret " \
                            "(needs system.disk_image_webhooks.rotate_secret, which this tool's permission does not imply). " \
                            "That call is approval-gated: if it answers pending, the plaintext is revealed once in the HTTP " \
                            "approval-decision response — approve via the operator UI/API, NOT via approve_deferred_operation, " \
                            "which deliberately drops the reveal. Or call bootstrap_disk_image_ci to have the secret written " \
                            "directly into the repo's Gitea Actions secrets instead.",
          note:             "Save the webhook URL now. The webhook is inert until a secret is fetched over the operator API — " \
                            "the one minted here was discarded rather than disclosed."
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
        # worker.token holds the plaintext (a virtual attribute set by
        # create_worker!). It is deliberately NOT bound into the return — see
        # the class docstring. The operator API's rotate_token endpoint is the
        # disclosure surface.
        {
          success: true,
          worker_id:      worker.id,
          name:           worker.name,
          roles:          worker.roles.pluck(:name),
          token_delivery: "not disclosed here — a tool result is persisted with the conversation and forwarded to the model provider. " \
                          "Get the plaintext exactly once at POST /api/v1/system/ci_workers/#{worker.id}/rotate_token " \
                          "(ungated, answers in one response; needs system.ci_workers.rotate_token, which this tool's " \
                          "permission does not imply). Or call bootstrap_disk_image_ci to have it written directly into " \
                          "the repo's Gitea Actions secrets.",
          note:           "Fetch the token over the operator API and store it as POWERNODE_CI_WORKER_TOKEN in your CI."
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

        # Build the webhook URL using the operator-supplied platform_api_base
        # so the URL CI hits is reachable from the runner. POWERNODE_PUBLIC_URL
        # env (set on the platform host) is the secondary fallback. Default
        # localhost:3000 is the last resort for tests/dev.
        webhook_url = build_webhook_url(webhook, host_override: platform_api_base)

        gitea_client = ::Devops::Git::ApiClient.for(gitea_credential)
        secret_results = {}
        {
          "POWERNODE_DISK_IMAGE_WEBHOOK_URL"    => webhook_url,
          "POWERNODE_DISK_IMAGE_WEBHOOK_SECRET" => webhook_secret,
          "POWERNODE_CI_WORKER_TOKEN"           => worker_token,
          "POWERNODE_API_BASE"                  => platform_api_base
        }.each do |k, v|
          result = gitea_client.create_or_update_action_secret(owner, repo, k, v)
          secret_results[k] = result[:success] ? "ok" : "error: #{result[:error]}"
        end

        # Optionally also mint a Gitea PAT for the parent platform
        # checkout step (PLATFORM_READ_TOKEN). Closes the manual "go to
        # Gitea web UI" step that operators otherwise hit on first
        # workflow run. Idempotent across re-runs: deletes any prior
        # token with the same name first so each bootstrap call lands
        # a fresh, in-sync token.
        platform_token_result = nil
        if params[:create_platform_read_token]
          token_name = params[:platform_read_token_name].to_s.presence || "#{label}-platform-ci-readonly"

          # Idempotency: tokens with the same name are deleted to make
          # room for a fresh one (Gitea rejects duplicate-name creates).
          gitea_client.delete_user_token(token_name) rescue nil

          token_result = gitea_client.create_user_token(token_name, scopes: %w[read:repository read:user])
          if token_result[:success]
            set_secret_result = gitea_client.create_or_update_action_secret(owner, repo, "PLATFORM_READ_TOKEN", token_result[:token])
            secret_results["PLATFORM_READ_TOKEN"] = set_secret_result[:success] ? "ok" : "error: #{set_secret_result[:error]}"
            platform_token_result = {
              token_id:        token_result[:token_id],
              token_name:      token_result[:name],
              scopes:          token_result[:scopes],
              plaintext_set_as_secret: "PLATFORM_READ_TOKEN"
              # No token_preview. A 12-char prefix is a partial disclosure into
              # the same two durable sinks as the whole value, and nothing reads
              # it: the delivery evidence the caller needs is the
              # gitea_secrets_set["PLATFORM_READ_TOKEN"] status above.
            }
          else
            platform_token_result = { error: token_result[:error] }
          end
        end

        # `webhook_secret` / `worker_token` stay local to this method: they were
        # delivered to Gitea above and are not echoed back, not even as the
        # 12-char previews this used to carry. The operator-visible
        # disambiguator already exists on the row itself
        # (system_disk_image_webhooks.secret_preview, rendered in the CI/webhooks
        # tab); a copy on the tool result buys nothing and costs the same
        # persist-plus-forward as the whole secret.
        result = {
          success: true,
          webhook:  { id: webhook.id, label: webhook.label, action: webhook_action, url: webhook_url },
          ci_worker: { id: worker.id, name: worker.name, action: worker_action },
          gitea_secrets_set: secret_results,
          note:    "Operator's CI workflow can now publish disk images. Trigger via dispatch_gitea_workflow or push a tag."
        }
        result[:platform_read_token] = platform_token_result if platform_token_result
        result
      rescue StandardError => e
        { success: false, error: "Bootstrap failed: #{e.class}: #{e.message}" }
      end

      def build_webhook_url(webhook, host_override: nil)
        base = host_override.presence ||
               ENV.fetch("POWERNODE_PUBLIC_URL", "http://localhost:3000")
        "#{base.chomp('/')}/api/v1/system/webhooks/disk_image/built/#{webhook.id}"
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
