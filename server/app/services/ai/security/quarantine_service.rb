# frozen_string_literal: true

module Ai
  module Security
    class QuarantineService
      # OWASP ASI08/ASI10 - Rogue Agent Quarantine & Incident Response
      # Provides severity-tiered quarantine, escalation, restoration, and emergency kill.

      SEVERITY_COOLDOWNS = {
        "low" => 30,
        "medium" => 60,
        "high" => 240,
        "critical" => 1440
      }.freeze

      SEVERITY_RESTRICTIONS = {
        "low" => { monitoring_level: "enhanced", action: "increase_monitoring" },
        "medium" => { monitoring_level: "high", restrict_write: true, restrict_execute: true, action: "restrict_capabilities" },
        "high" => { monitoring_level: "maximum", revoke_tools: true, block_comms: true, action: "quarantine_isolate" },
        "critical" => { monitoring_level: "lockdown", revoke_all: true, cancel_tasks: true, action: "emergency_kill" }
      }.freeze

      class QuarantineError < StandardError; end

      def initialize(account:)
        @account = account
      end

      # Quarantine an agent with severity-based restrictions.
      # Returns the created QuarantineRecord.
      def quarantine!(agent:, severity:, reason:, source: "manual")
        validate_severity!(severity)

        # Capture forensic snapshot before applying restrictions
        snapshot = capture_forensic_snapshot(agent)
        previous_caps = capture_previous_capabilities(agent)

        # Apply restrictions based on severity
        restrictions = apply_restrictions(agent, severity)

        cooldown = SEVERITY_COOLDOWNS[severity] || 60
        scheduled_restore = severity == "critical" ? nil : (Time.current + cooldown.minutes)

        record = Ai::QuarantineRecord.create!(
          account: @account,
          agent_id: agent.id,
          severity: severity,
          status: "active",
          trigger_reason: reason,
          trigger_source: source,
          restrictions_applied: restrictions,
          forensic_snapshot: snapshot,
          previous_capabilities: previous_caps,
          cooldown_minutes: cooldown,
          scheduled_restore_at: scheduled_restore
        )

        audit_log("agent_quarantined", agent: agent, outcome: "quarantined",
                  severity_level: severity == "critical" ? "critical" : "warning",
                  details: {
                    quarantine_id: record.id, severity: severity,
                    reason: reason, source: source, restrictions: restrictions
                  })

        record
      rescue ActiveRecord::RecordInvalid => e
        Rails.logger.error "[QuarantineService] quarantine! failed: #{e.message}"
        raise QuarantineError, "Failed to quarantine agent: #{e.message}"
      end

      # Escalate an existing quarantine to a higher severity.
      # Returns the new QuarantineRecord.
      def escalate!(quarantine_record:, new_severity:)
        validate_severity!(new_severity)

        old_severity_level = Ai::QuarantineRecord::SEVERITIES.index(quarantine_record.severity) || 0
        new_severity_level = Ai::QuarantineRecord::SEVERITIES.index(new_severity) || 0

        if new_severity_level <= old_severity_level
          raise QuarantineError, "Cannot escalate to same or lower severity (#{quarantine_record.severity} -> #{new_severity})"
        end

        quarantine_record.update!(status: "escalated")

        agent = Ai::Agent.find(quarantine_record.agent_id)
        restrictions = apply_restrictions(agent, new_severity)

        cooldown = SEVERITY_COOLDOWNS[new_severity] || 60
        scheduled_restore = new_severity == "critical" ? nil : (Time.current + cooldown.minutes)

        new_record = Ai::QuarantineRecord.create!(
          account: @account,
          agent_id: quarantine_record.agent_id,
          severity: new_severity,
          status: "active",
          trigger_reason: "Escalated from #{quarantine_record.severity}: #{quarantine_record.trigger_reason}",
          trigger_source: quarantine_record.trigger_source,
          restrictions_applied: restrictions,
          forensic_snapshot: quarantine_record.forensic_snapshot,
          previous_capabilities: quarantine_record.previous_capabilities,
          escalated_from_id: quarantine_record.id,
          cooldown_minutes: cooldown,
          scheduled_restore_at: scheduled_restore
        )

        audit_log("quarantine_escalated", agent_id: quarantine_record.agent_id, outcome: "escalated",
                  severity_level: new_severity == "critical" ? "critical" : "warning",
                  details: {
                    old_quarantine_id: quarantine_record.id,
                    new_quarantine_id: new_record.id,
                    old_severity: quarantine_record.severity,
                    new_severity: new_severity
                  })

        new_record
      end

      # Restore an agent from quarantine, reinstating previous capabilities.
      def restore!(quarantine_record:, approved_by:)
        unless quarantine_record.active?
          raise QuarantineError, "Cannot restore non-active quarantine (status: #{quarantine_record.status})"
        end

        agent = Ai::Agent.find(quarantine_record.agent_id)
        remove_restrictions(agent, quarantine_record)

        quarantine_record.update!(
          status: "restored",
          restored_at: Time.current,
          approved_by_id: approved_by.id,
          restoration_notes: "Restored by #{approved_by.email}"
        )

        audit_log("agent_restored", agent: agent, outcome: "allowed",
                  details: {
                    quarantine_id: quarantine_record.id,
                    approved_by: approved_by.id,
                    severity: quarantine_record.severity
                  })

        quarantine_record
      end

      # Emergency kill: revoke all identity keys, terminate sessions, cancel tasks.
      def emergency_kill!(agent:, reason:)
        snapshot = capture_forensic_snapshot(agent)

        # Revoke all identity keys
        identity_service = AgentIdentityService.new(account: @account)
        begin
          identity_service.revoke!(agent: agent, reason: "Emergency kill: #{reason}")
        rescue StandardError => e
          Rails.logger.warn "[QuarantineService] identity revocation during emergency_kill: #{e.message}"
        end

        # Close all encrypted sessions
        begin
          comm_service = EncryptedCommunicationService.new(account: @account)
          Ai::EncryptedMessage.where(account: @account)
            .for_agent(agent.id)
            .delivered
            .select(:session_id).distinct
            .pluck(:session_id)
            .compact.each do |sid|
              comm_service.close_session!(session_id: sid)
            rescue StandardError => e
              Rails.logger.warn "[QuarantineService] session close during emergency_kill: #{e.message}"
            end
        rescue StandardError => e
          Rails.logger.warn "[QuarantineService] encrypted message cleanup: #{e.message}"
        end

        # Deactivate the agent
        agent.update!(status: "paused") if agent.respond_to?(:status=)

        record = quarantine!(
          agent: agent,
          severity: "critical",
          reason: "EMERGENCY KILL: #{reason}",
          source: "manual"
        )

        audit_log("emergency_kill", agent: agent, outcome: "blocked",
                  severity_level: "critical",
                  details: {
                    reason: reason,
                    quarantine_id: record.id,
                    forensic_snapshot_keys: snapshot.keys
                  })

        record
      end

      # Find quarantine records that are past their scheduled restore time.
      def restorable_records
        Ai::QuarantineRecord.where(account: @account).restorable
      end

      # Auto-restore agents whose scheduled_restore_at has passed.
      # Skips high/critical severity (require human approval).
      # Re-evaluates low/medium before restoring — extends quarantine if still anomalous.
      # Returns an array of restored record IDs.
      def auto_restore_expired!
        restored_ids = []

        restorable_records.find_each do |record|
          agent = Ai::Agent.find_by(id: record.agent_id)
          next unless agent

          # High/critical severity quarantines require human approval — skip auto-restore
          if %w[high critical].include?(record.severity)
            Rails.logger.info "[QuarantineService] Skipping auto-restore for #{record.id}: #{record.severity} severity requires human approval"
            next
          end

          # Re-evaluate agent before restoring low/medium quarantines
          if agent_still_anomalous?(agent)
            extend_quarantine!(record)
            Rails.logger.info "[QuarantineService] Extended quarantine #{record.id}: agent still anomalous"
            next
          end

          remove_restrictions(agent, record)
          record.update!(
            status: "restored",
            restored_at: Time.current,
            restoration_notes: "Auto-restored after scheduled_restore_at (re-evaluation passed)"
          )
          restored_ids << record.id

          audit_log("agent_auto_restored", agent: agent, outcome: "allowed",
                    details: { quarantine_id: record.id, severity: record.severity })
        rescue StandardError => e
          Rails.logger.error "[QuarantineService] auto_restore_expired! error for #{record.id}: #{e.message}"
        end

        restored_ids
      end

      private

      def validate_severity!(severity)
        unless Ai::QuarantineRecord::SEVERITIES.include?(severity)
          raise QuarantineError, "Invalid severity: #{severity}"
        end
      end

      def capture_forensic_snapshot(agent)
        {
          agent_id: agent.id,
          agent_status: agent.respond_to?(:status) ? agent.status : nil,
          agent_type: agent.respond_to?(:agent_type) ? agent.agent_type : nil,
          trust_tier: agent.respond_to?(:trust_score) ? agent.trust_score&.tier : nil,
          captured_at: Time.current.iso8601,
          recent_execution_count: agent.respond_to?(:executions) ? agent.executions.where("created_at >= ?", 1.hour.ago).count : 0,
          active_budgets: agent.respond_to?(:budgets) ? agent.budgets.active.count : 0
        }.compact
      rescue StandardError => e
        Rails.logger.error "[QuarantineService] capture_forensic_snapshot: #{e.message}"
        { error: e.message, captured_at: Time.current.iso8601 }
      end

      def capture_previous_capabilities(agent)
        {
          skill_slugs: agent.respond_to?(:skill_slugs) ? agent.skill_slugs : [],
          status: agent.respond_to?(:status) ? agent.status : nil,
          mcp_tool_manifest: agent.respond_to?(:mcp_tool_manifest) ? agent.mcp_tool_manifest : {}
        }
      rescue StandardError => e
        Rails.logger.error "[QuarantineService] capture_previous_capabilities: #{e.message}"
        { error: e.message }
      end

      def apply_restrictions(agent, severity)
        config = SEVERITY_RESTRICTIONS[severity] || {}

        case severity
        when "low"
          # Increase monitoring only - no active restrictions
          Rails.logger.info "[QuarantineService] LOW: Increased monitoring for agent #{agent.id}"
        when "medium"
          # Restrict write/execute tools via privilege policies
          create_restriction_policy(agent, severity, denied_tools: %w[write execute delete modify])
        when "high"
          # Revoke all tool access, block inter-agent comms
          create_restriction_policy(agent, severity, denied_tools: ["*"],
                                   communication_rules: { "blocked_pairs" => [[agent.id, "*"]] })
        when "critical"
          # Revoke all tokens, cancel active tasks
          create_restriction_policy(agent, severity, denied_actions: ["*"], denied_tools: ["*"],
                                   communication_rules: { "blocked_pairs" => [[agent.id, "*"]] })
          agent.update!(status: "paused") if agent.respond_to?(:status=)
        end

        config.merge(applied_at: Time.current.iso8601)
      rescue StandardError => e
        Rails.logger.error "[QuarantineService] apply_restrictions: #{e.message}"
        { error: e.message }
      end

      def create_restriction_policy(agent, severity, denied_tools: [], denied_actions: [], communication_rules: {})
        policy_name = "quarantine_#{agent.id}_#{severity}"

        existing = Ai::AgentPrivilegePolicy.where(account: @account, policy_name: policy_name).first
        if existing
          existing.update!(
            denied_tools: denied_tools,
            denied_actions: denied_actions,
            communication_rules: communication_rules,
            active: true,
            priority: 1000
          )
        else
          Ai::AgentPrivilegePolicy.create!(
            account: @account,
            agent_id: agent.id,
            policy_name: policy_name,
            policy_type: "system",
            denied_tools: denied_tools,
            denied_actions: denied_actions,
            communication_rules: communication_rules,
            active: true,
            priority: 1000
          )
        end
      rescue StandardError => e
        Rails.logger.error "[QuarantineService] create_restriction_policy: #{e.message}"
      end

      def remove_restrictions(agent, quarantine_record)
        severity = quarantine_record.severity
        policy_name = "quarantine_#{agent.id}_#{severity}"

        Ai::AgentPrivilegePolicy.where(account: @account, policy_name: policy_name).update_all(active: false)

        # Restore agent status if it was paused
        if quarantine_record.previous_capabilities["status"].present? && agent.respond_to?(:status=)
          previous_status = quarantine_record.previous_capabilities["status"]
          agent.update!(status: previous_status) if %w[active inactive].include?(previous_status)
        end
      rescue StandardError => e
        Rails.logger.error "[QuarantineService] remove_restrictions: #{e.message}"
      end

      # Check if agent is still showing anomalous behavior
      def agent_still_anomalous?(agent)
        analysis = Ai::Security::AgentAnomalyDetectionService.new(account: @account)
                     .analyze_agent(agent: agent, window_minutes: 60)
        %w[high critical].include?(analysis[:risk_level])
      rescue StandardError => e
        Rails.logger.error "[QuarantineService] agent_still_anomalous? error: #{e.message}"
        true # Fail-closed: assume still anomalous on error
      end

      # Extend a quarantine by pushing the scheduled_restore_at forward
      def extend_quarantine!(record)
        new_restore = Time.current + (record.cooldown_minutes || 60).minutes
        record.update!(
          scheduled_restore_at: new_restore,
          restoration_notes: "Auto-restore deferred: agent still anomalous at #{Time.current.iso8601}"
        )

        audit_log("quarantine_extended", agent_id: record.agent_id, outcome: "quarantined",
                  details: {
                    quarantine_id: record.id,
                    severity: record.severity,
                    new_restore_at: new_restore.iso8601
                  })
      rescue StandardError => e
        Rails.logger.error "[QuarantineService] extend_quarantine! error: #{e.message}"
      end

      def audit_log(action, agent: nil, agent_id: nil, outcome:, severity_level: "info", details: {})
        Ai::SecurityAuditTrail.log!(
          action: action,
          outcome: outcome,
          account: @account,
          agent_id: agent_id || agent&.id,
          asi_reference: "ASI08",
          csa_pillar: "incident_response",
          source_service: "QuarantineService",
          severity: severity_level,
          details: details
        )
      rescue StandardError => e
        Rails.logger.error "[QuarantineService] audit_log failed: #{e.message}"
      end
    end
  end
end
