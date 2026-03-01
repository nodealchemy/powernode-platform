# frozen_string_literal: true

module Ai
  module CodeFactory
    class OrchestratorService
      class OrchestrationError < StandardError; end

      def initialize(account:, risk_contract: nil)
        @account = account
        @risk_contract = risk_contract
        @preflight = PreflightGateService.new(account: account, risk_contract: risk_contract)
        @sha_validator = ShaValidationService.new(account: account)
        @rerun_coordinator = RerunCoordinatorService.new(account: account)
        @thread_resolver = ThreadResolverService.new(account: account)
        @evidence_validator = EvidenceValidatorService.new(account: account)
        @harness_gap_service = HarnessGapService.new(account: account)
        @logger = Rails.logger
      end

      # Process a full PR event through the Code Factory loop
      def process_pr_event(event_type:, pr_number:, head_sha:, changed_files:, repository: nil)
        @logger.info("[CodeFactory::Orchestrator] Processing #{event_type} for PR ##{pr_number} sha:#{head_sha[0..7]}")

        case event_type
        when "opened", "synchronize", "push"
          on_push_event(pr_number: pr_number, new_head_sha: head_sha, changed_files: changed_files,
                        repository: repository)
        when "review_submitted"
          review_state = find_current_review_state(pr_number: pr_number, head_sha: head_sha)
          on_review_completed(review_state: review_state, findings: []) if review_state
        else
          @logger.warn("[CodeFactory::Orchestrator] Unknown event type: #{event_type}")
          { success: false, reason: "Unknown event type: #{event_type}" }
        end
      rescue StandardError => e
        @logger.error("[CodeFactory::Orchestrator] Error processing PR event: #{e.message}")
        raise OrchestrationError, e.message
      end

      # Handle new push: invalidate stale states, run preflight
      def on_push_event(pr_number:, new_head_sha:, changed_files:, repository: nil)
        repository_id = repository&.id

        # Invalidate stale review states
        @sha_validator.invalidate_for_new_push(
          repository_id: repository_id,
          pr_number: pr_number,
          new_head_sha: new_head_sha
        )

        # Run preflight gate
        preflight_result = @preflight.evaluate(
          pr_number: pr_number,
          head_sha: new_head_sha,
          changed_files: changed_files,
          repository_id: repository_id
        )

        broadcast_event("preflight_complete", {
          pr_number: pr_number,
          head_sha: new_head_sha,
          passed: preflight_result[:passed],
          risk_tier: preflight_result[:risk_tier]
        })

        preflight_result
      end

      # Handle review completion: check findings, trigger remediation or mark clean
      def on_review_completed(review_state:, findings:)
        if findings.empty?
          review_state.mark_clean!
          @thread_resolver.resolve_bot_threads(review_state: review_state)

          broadcast_event("review_clean", {
            pr_number: review_state.pr_number,
            review_state_id: review_state.id
          })

          { status: "clean", merge_ready: review_state.merge_ready? }
        else
          review_state.mark_dirty!(
            findings_count: findings.size,
            critical_count: findings.count { |f| (f[:severity] || f["severity"]) == "critical" }
          )

          broadcast_event("review_dirty", {
            pr_number: review_state.pr_number,
            findings_count: findings.size,
            review_state_id: review_state.id
          })

          { status: "dirty", findings_count: findings.size, review_state: review_state }
        end
      end

      # Handle evidence submission
      def on_evidence_submitted(review_state:, manifest:)
        result = @evidence_validator.validate_evidence(
          review_state: review_state,
          manifest: manifest
        )

        broadcast_event("evidence_validated", {
          pr_number: review_state.pr_number,
          passed: result[:passed],
          manifest_id: manifest.id
        })

        result
      end

      # Check if PR is merge-ready
      def merge_ready?(review_state:)
        review_state.merge_ready?
      end

      private

      def find_current_review_state(pr_number:, head_sha:)
        @account.ai_code_factory_review_states
          .find_by(pr_number: pr_number, head_sha: head_sha, status: %w[pending reviewing dirty])
      end

      def broadcast_event(event_type, payload)
        CodeFactoryChannel.broadcast_to_account(
          @account.id,
          event: "code_factory.#{event_type}",
          payload: payload,
          timestamp: Time.current.iso8601
        )
      rescue StandardError => e
        @logger.warn("[CodeFactory::Orchestrator] Broadcast failed: #{e.message}")
      end
    end
  end
end
