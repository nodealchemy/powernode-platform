# frozen_string_literal: true

module Ai
  module Land
    # Creates a CampaignLand for a completed change-set and decides whether it
    # needs explicit approval before landing. Default is to REQUIRE approval
    # (the land sits in pending_approval until an operator approves via the
    # proposal card / governance chain). An `autonomous` campaign — or any
    # mission land (the mission already cleared its own gates) — auto-approves
    # (enqueues immediately).
    #
    # Source-keyed: the land source is polymorphic (Ai::Campaign, Ai::Mission,
    # ...). A back-compat `campaign:` shim keeps existing call sites working.
    # Campaign lands keep campaign_id populated; other sources set only the
    # polymorphic source (campaign_id stays NULL).
    #
    # Core-pure: only touches the governance extension behind defined?() guards,
    # mirroring Ai::AutonomyGate#require_approval_or_proceed.
    class ApprovalBinding
      def self.request_land_approval(source: nil, campaign: nil, source_branch: nil,
                                     target_branch: "develop", description: nil,
                                     requested_by: nil, priority: 0)
        new(source || campaign).request_land_approval(
          source_branch: source_branch, target_branch: target_branch,
          description: description, requested_by: requested_by, priority: priority
        )
      end

      def initialize(source)
        @source = source
      end

      def request_land_approval(source_branch: nil, target_branch: "develop",
                                description: nil, requested_by: nil, priority: 0)
        land = build_land(source_branch: source_branch, target_branch: target_branch, priority: priority)

        # BLOCKING security gate (G4): runs BEFORE the auto-approve/governance
        # decision so an autonomous campaign land can NEVER auto-merge a leaked
        # secret (or, once external scanners register, a SAST/CVE finding). On a
        # block the land is forced to a human-gated state with findings recorded —
        # no enqueue!, regardless of decision authority.
        gate = security_gate_result(land)
        if gate[:blocked]
          block_for_security!(land, gate)
          return land
        end

        if auto_land_approved?
          land.enqueue! # auto-approve reversible land
        elsif governance_available?
          create_governance_request(land, description: description, requested_by: requested_by)
          # If the chain couldn't be created, leave it pending for the proposal card.
        end

        # Whenever the land still needs human approval, surface it for review.
        ::Ai::Land::ProposalService.deliver(land) if land.reload.status == "pending_approval"

        land
      end

      private

      # Run the blocking security gate; never let a gate error silently allow a
      # land — treat an evaluation error as a block (fail-closed → human review).
      def security_gate_result(land)
        ::Ai::Land::SecurityGateService.evaluate(land)
      rescue StandardError => e
        Rails.logger.warn("[ApprovalBinding] security gate errored (land #{land.id}): #{e.message}")
        { blocked: true, findings: [ { scanner: "security_gate", severity: "high",
                                       detail: "gate error: #{e.message}" } ] }
      end

      # Record findings on the land metadata and park it for a human. Findings
      # carry only scanner/severity/category labels (never raw secret values), so
      # they are safe to persist and display. Surfaces through the source's park
      # notification seam when available (mirrors LandService#notify_park).
      def block_for_security!(land, gate)
        findings = Array(gate[:findings])
        reason = "security gate blocked: #{findings_summary(findings)}"
        land.update!(metadata: land.metadata.to_h.merge(
          "security_gate" => {
            "blocked" => true,
            "scanned_content" => gate[:scanned_content],
            "findings" => findings.map { |f| f.transform_keys(&:to_s) },
            "evaluated_at" => Time.current.iso8601
          }
        ))
        land.park!(reason: reason)
        notify_security_park(land, reason)
        land
      end

      def findings_summary(findings)
        return "policy violation" if findings.empty?

        findings.map { |f| "#{f[:scanner]}:#{f[:severity]}" }.uniq.join(", ")
      end

      def notify_security_park(land, reason)
        @source.land_park_notify!(reason: reason, land: land) if @source.respond_to?(:land_park_notify!)
      rescue StandardError => e
        Rails.logger.warn("[ApprovalBinding] security park notify failed (land #{land.id}): #{e.message}")
      end

      def build_land(source_branch:, target_branch:, priority:)
        attrs = {
          account: @source.account,
          source: @source,
          source_branch: source_branch.presence || default_source_branch,
          target_branch: target_branch,
          priority: priority,
          status: "pending_approval"
        }
        # Campaign lands keep the legacy campaign_id populated (indexes,
        # has_many :campaign_lands, existing queries). Other sources leave it nil.
        attrs[:campaign] = @source if campaign_source?
        ::Ai::CampaignLand.create!(attrs)
      end

      def campaign_source?
        @source.is_a?(::Ai::Campaign)
      end

      def default_source_branch
        if campaign_source?
          "campaign/#{@source.id}"
        else
          @source.try(:branch_name).presence || "land/#{@source.id}"
        end
      end

      # Campaign lands auto-approve only for `autonomous` decision authority;
      # every other authority requires approval. Mission lands auto-approve —
      # the mission already cleared its own approval gates before reaching here.
      def auto_land_approved?
        if campaign_source?
          @source.decision_authority == "autonomous"
        else
          true
        end
      end

      # Approval-chain kind so missions and campaigns can route through distinct
      # default chains when the governance extension is present.
      def chain_kind
        campaign_source? ? "campaign_land" : "mission_land"
      end

      def governance_available?
        return false unless defined?(::Ai::ApprovalChain) && defined?(::Ai::Autonomy::ApprovalWorkflowService)

        ::Ai::Autonomy::ApprovalWorkflowService.governance_enabled?
      rescue StandardError
        false
      end

      # Best-effort: bind a formal ApprovalRequest to the land via a chain. The
      # request's after_update calls land.on_approval_decision, which enqueues/rejects.
      # source_type stays "Ai::CampaignLand" (the durable land row) for both kinds.
      def create_governance_request(land, description:, requested_by:)
        chain = ::Ai::ApprovalChain.find_or_create_default_for(@source.account, chain_kind)
        return nil unless chain.respond_to?(:create_request!)

        chain.create_request!(
          source_type: "Ai::CampaignLand", source_id: land.id,
          description: description || "Land #{land.source_branch} → #{land.target_branch}",
          requested_by: requested_by
        )
      rescue StandardError => e
        Rails.logger.warn("[ApprovalBinding] governance request failed (land #{land.id}): #{e.message}")
        nil
      end
    end
  end
end
