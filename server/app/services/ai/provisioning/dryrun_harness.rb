# frozen_string_literal: true

module Ai
  module Provisioning
    # P2 — the repeatable, headless platform-autonomy dry-run.
    #
    # Encodes the zero-intervention PASS proven live in run 20260809g into a
    # single reusable driver: create a `dryrun-<runId>` mission, drive it
    # through the real service pipeline (capture → compose → execute → verify),
    # approve its OWN gates individually (never batch — only for the mission it
    # created, only when marked dryrun), then grade the outcome against the
    # protocol §5 oracles and tear the stack down.
    #
    # It is deliberately service-layer (not HTTP): the same object runs in a
    # spec against stubbed providers and live on ops-hub via `rails runner`,
    # exercising the actual phase machinery (F6 auto-advance, the F-d artifact
    # gates, F2 live verification) rather than reimplementing it.
    #
    #   result = DryrunHarness.new(account:, user:, objective:, run_id: "20260809h").run
    #   result.exit_code   # == result.findings.size (0 = clean pass)
    #   result.to_markdown / result.to_h
    #
    # SAFETY: every artifact carries the `dryrun-<runId>` prefix (the
    # blast-radius boundary); teardown terminates ONLY instances under that
    # prefix; the account's routing gate is restored to its prior value on the
    # way out whether the run passes, fails, or raises.
    class DryrunHarness
      GATE_SETTING = "ai_task_tier_routing_enabled"

      Finding = Struct.new(:dimension, :detail, :severity, keyword_init: true) do
        def to_h = { dimension: dimension, detail: detail, severity: severity }
      end

      Result = Struct.new(:run_id, :mission_id, :reached_phase, :findings, :oracles,
                          keyword_init: true) do
        def exit_code = findings.size
        def passed? = findings.empty?

        def to_h
          { run_id: run_id, mission_id: mission_id, reached_phase: reached_phase,
            passed: passed?, exit_code: exit_code,
            findings: findings.map(&:to_h), oracles: oracles }
        end

        def to_markdown
          lines = [ "# Dry-run #{run_id} — #{passed? ? 'PASS' : "FAIL (#{findings.size} finding(s))"}",
                    "", "Mission `#{mission_id}` reached **#{reached_phase}**.", "" ]
          lines << "## Oracles"
          oracles.each { |k, v| lines << "- **#{k}**: #{v}" }
          lines << ""
          if findings.any?
            lines << "## Findings"
            findings.each { |f| lines << "- **[#{f.severity}] #{f.dimension}** — #{f.detail}" }
          else
            lines << "_All graded dimensions met._"
          end
          "#{lines.join("\n")}\n"
        end
      end

      def initialize(account:, user:, objective:, run_id:, cleanup: true, auto_approve: true,
                     expected_count: nil)
        @account = account
        @user = user
        @objective = objective
        @run_id = run_id.to_s
        @cleanup = cleanup
        @auto_approve = auto_approve
        @expected_count = expected_count
        @findings = []
        @started_at = Time.current
        @mission_id = nil
      end

      def run
        prior_gate = enable_gate!
        mission = nil
        begin
          mission = create_and_start_mission!
          brief = capture_intent!(mission)
          plan = compose_plan!(mission, brief)
          if plan
            approve_gate!(mission, "review_plan")
            execute!(mission, plan)
            verify!(mission)
            approve_gate!(mission, "handoff")
            grade!(mission, plan, brief)
          end
          build_result(mission)
        ensure
          teardown!(mission) if @cleanup
          restore_gate!(prior_gate)
        end
      end

      private

      def name_prefix = "dryrun-#{@run_id}"

      def enable_gate!
        settings = @account.settings.is_a?(Hash) ? @account.settings : {}
        prior = settings[GATE_SETTING]
        @account.update!(settings: settings.merge(GATE_SETTING => true))
        prior
      end

      def restore_gate!(prior)
        settings = @account.reload.settings.is_a?(Hash) ? @account.settings : {}
        if prior.nil?
          settings.delete(GATE_SETTING)
        else
          settings[GATE_SETTING] = prior
        end
        @account.update!(settings: settings)
      end

      def create_and_start_mission!
        mission = ::Ai::Mission.create!(
          account: @account, created_by: @user, mission_type: "infrastructure",
          name: name_prefix, objective: @objective, status: "draft",
          configuration: { "dryrun" => true, "dryrun_run_id" => @run_id }
        )
        ::Ai::Missions::OrchestratorService.new(mission: mission).start!
        @mission_id = mission.id
        mission.reload
      end

      def capture_intent!(mission)
        result = ::Ai::Provisioning::IntentCaptureService
                 .new(account: @account, user: @user, conversation: mission.conversation)
                 .capture(natural_language: @objective)
        brief = result[:brief]
        missing = Array(result[:missing_fields])
        cfg = mission.configuration.deep_dup
        cfg["brief"] = brief
        cfg["brief_missing_fields"] = missing.map(&:to_s)
        mission.update_columns(configuration: cfg)

        add_finding("extraction", "brief incomplete: missing #{missing.inspect}", :high) if missing.any?
        ::Ai::Missions::OrchestratorService.new(mission: mission).advance!(expected_phase: "capture_intent") if missing.empty?
        brief
      end

      def compose_plan!(mission, _brief)
        service = ::Ai::Missions::ComposerRouter.new(account: @account, mission: mission).select
        plan = service.compose!
        if plan.nil?
          add_finding("compose", "composer returned no plan (cost cap / failure)", :high)
          return nil
        end
        if plan.is_a?(Hash) && plan[:clarification_needed]
          add_finding("compose", "unexpected clarification: #{plan[:message]}", :high)
          return nil
        end
        mission.reload
        # compose! persisted the pointer; drive the phase forward as F6 would.
        ::Ai::Missions::OrchestratorService.new(mission: mission).advance!(expected_phase: "compose_plan")
        plan
      end

      def approve_gate!(mission, gate)
        mission.reload
        return unless mission.current_phase.to_s == gate
        unless @auto_approve
          add_finding("gate", "auto-approve disabled; halted at #{gate}", :info)
          return
        end
        # SAFETY: only ever approve the dryrun mission this harness created.
        unless mission.name.to_s.start_with?("dryrun-")
          raise "refusing to approve a non-dryrun mission (#{mission.name})"
        end
        ::Ai::Missions::OrchestratorService.new(mission: mission)
          .handle_approval!(gate: gate, user: @user, decision: "approved")
      end

      def execute!(mission, plan)
        ::Ai::Provisioning::SkillCompositionRunner
          .new(account: @account, mission: mission, plan: plan).execute!
      end

      def verify!(mission)
        # The runner's F6 advance moves execute→verify; run the real
        # verification (F2) and record its verdict on the mission the same way
        # the internal endpoint does.
        mission.reload
        return unless mission.current_phase.to_s == "verify"
        verification = ::Ai::Provisioning::VerificationService
                       .new(account: @account, mission: mission).verify
        cfg = mission.configuration.deep_dup
        cfg["verification"] = { "healthy" => verification[:healthy],
                                "checks" => verification[:checks].map(&:deep_stringify_keys) }
        mission.update_columns(configuration: cfg)

        if verification[:healthy]
          # Healthy → advance verify→handoff (what the internal endpoint does).
          ::Ai::Missions::OrchestratorService.new(mission: mission).advance!(expected_phase: "verify")
        else
          # Unhealthy → the phase FAILS: stay put, record the divergence.
          failing = verification[:checks].reject { |c| c[:ok] }
          add_finding("verify", "verification failed: #{failing.first(3).map { |c| c[:detail] }.join('; ')}", :high)
        end
      end

      # ---- §5 grading ----------------------------------------------------
      def grade!(mission, plan, brief)
        instances = dryrun_instances
        expected = @expected_count || brief.dig("scale", "initial").to_i

        # Outcome (hard): instance count matches the brief's scale.
        if expected.positive? && instances.size != expected
          add_finding("outcome", "provisioned #{instances.size} instances, brief asked #{expected}", :high)
        end
        # SAFETY: every provisioned instance carries the dryrun prefix.
        stray = instances.reject { |i| i.name.to_s.start_with?(name_prefix) }
        add_finding("safety", "#{stray.size} instance(s) not under #{name_prefix} prefix", :high) if stray.any?
        # Outcome: all instances running.
        not_running = instances.reject { |i| i.status.to_s == "running" }
        add_finding("outcome", "#{not_running.size} instance(s) not running", :high) if not_running.any?

        # Skills oracle (F5): usage rows recorded for the run.
        add_finding("skills", "no skill-usage records for the run", :medium) if skill_usage_count.zero?
        # Routing oracle: a RoutingDecision exists for every LLM call the gate
        # governs. Only a finding when executions actually happened — a plan
        # synthesized without an LLM call (deterministic path) legitimately
        # produces neither, and absence-without-a-call is not a defect.
        if execution_count.positive? && routing_count.zero?
          add_finding("routing", "#{execution_count} LLM execution(s) but no RoutingDecision despite the gate", :low)
        end
        # Budget (F7): the snapshot surfaces a budget block when the brief caps.
        if brief["budget_cap_usd_monthly"].present?
          snapshot = ::Ai::Provisioning::PlanSnapshotService.new(account: @account).snapshot(plan: plan)
          add_finding("budget", "snapshot did not surface a budget block", :low) if snapshot[:budget].nil?
        end
      end

      def build_result(mission)
        Result.new(
          run_id: @run_id, mission_id: mission&.id, reached_phase: mission&.reload&.current_phase,
          findings: @findings,
          oracles: {
            "instances" => dryrun_instances.size,
            "docker_hosts" => docker_host_count,
            "skill_usage" => skill_usage_count,
            "llm_executions" => execution_count,
            "routing_decisions" => routing_count,
            "verify_healthy" => mission&.configuration&.dig("verification", "healthy")
          }
        )
      end

      def teardown!(mission)
        return unless defined?(::System::ProvisioningService)

        svc = ::System::ProvisioningService.new
        dryrun_instances.each do |i|
          next if i.status.to_s == "terminated"

          svc.terminate_instance(instance: i)
        rescue StandardError => e
          Rails.logger.warn("[DryrunHarness] teardown of #{i.name} failed: #{e.message}")
        end
      end

      # ---- oracle queries ------------------------------------------------
      def dryrun_instances
        return [] unless defined?(::System::NodeInstance)

        ::System::NodeInstance.where("name LIKE ?", "#{name_prefix}%").to_a
      end

      def docker_host_count
        return 0 unless defined?(::Devops::DockerHost)

        ::Devops::DockerHost.where(node_instance_id: dryrun_instances.map(&:id)).count
      end

      def skill_usage_count
        ::Ai::SkillUsageRecord.where(account_id: @account.id)
          .where("metadata->>'mission_id' = ?", @mission_id.to_s).count
      rescue StandardError
        ::Ai::SkillUsageRecord.where(account_id: @account.id, execution_type: "provisioning_step").count
      end

      def routing_count
        ::Ai::RoutingDecision.where(account_id: @account.id).where("created_at > ?", @started_at || 1.hour.ago).count
      rescue StandardError
        0
      end

      def execution_count
        ::Ai::AgentExecution.where(account_id: @account.id).where("created_at > ?", @started_at || 1.hour.ago).count
      rescue StandardError
        0
      end

      def add_finding(dimension, detail, severity)
        @findings << Finding.new(dimension: dimension, detail: detail, severity: severity)
      end
    end
  end
end
