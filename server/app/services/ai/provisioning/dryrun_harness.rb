# frozen_string_literal: true

module Ai
  module Provisioning
    # P2 — the repeatable, headless platform-autonomy dry-run.
    #
    # OBSERVER MODE. The harness is a *supervisor*, not a driver: it creates a
    # `dryrun-<runId>` mission, then lets the REAL provisioning pipeline
    # self-drive — exactly as the operator-in-the-loop runs (a–g) did — while
    # the harness only (a) approves its OWN gates, one at a time, and (b) grades
    # the outcome against the protocol §5 oracles and tears the stack down.
    #
    # Phase execution (capture → compose → execute → verify) happens where it
    # lives in production: the worker's AiProvisioning*Job POST to the internal
    # ProvisioningController, whose actions run the real services and self-advance
    # (F6). The harness never re-implements that stitching — so a regression in
    # the controllers, the runner, or F6 surfaces here instead of hiding behind a
    # parallel in-process reimplementation.
    #
    # The ONE seam that differs between live and spec is who *pumps* the async
    # work between the harness's phase polls:
    #   - LIVE  (rails runner on ops-hub): `phase_pump` is nil → the harness
    #     sleeps and polls; the standalone worker drains the job queue over HTTP.
    #   - SPEC  (no worker): the caller injects a `phase_pump` that synchronously
    #     drains the enqueued phase/step jobs by POSTing to the real internal
    #     endpoints, so the controllers run in-process, one request at a time.
    # The harness's supervisory code is byte-identical in both.
    #
    #   result = DryrunHarness.new(account:, user:, objective:, run_id: "20260809h").run
    #   result.exit_code   # == result.findings.size (0 = clean pass)
    #   result.to_markdown / result.to_h
    #
    # SAFETY: every artifact carries the `dryrun-<runId>` prefix (the
    # blast-radius boundary); teardown terminates ONLY instances under that
    # prefix, account-scoped, LIKE-escaped; the account's routing gate is
    # restored to its prior value on the way out whether the run passes, fails,
    # or raises.
    class DryrunHarness
      GATE_SETTING = "ai_task_tier_routing_enabled"
      # A supervised run always approves handoff to reach adapting; handoff is a
      # gate, never a valid resting place (M5: a second-signature account parks
      # there, and grading that as terminal would be a false PASS).
      TERMINAL_PHASES = %w[adapting completed].freeze

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

      # @param phase_pump [#call, nil] spec-only driver that drains enqueued
      #   phase/step jobs and returns the count processed; nil ⇒ live (sleep+poll).
      # @param compose_timeout/execute_timeout [Numeric] seconds to wait for the
      #   pipeline to reach the review_plan and handoff gates respectively.
      def initialize(account:, user:, objective:, run_id:, cleanup: true, auto_approve: true,
                     expected_count: nil, phase_pump: nil, poll_interval: 2,
                     compose_timeout: 120, execute_timeout: 900)
        @account = account
        @user = user
        @objective = objective
        @run_id = run_id.to_s
        # M4: run_id is the teardown blast-radius boundary and is interpolated
        # into a SQL LIKE. Reject anything but [alnum-hyphen] so an operator can
        # never pass a LIKE metacharacter ('%' matches every dryrun instance on
        # the box; '_' is a single-char wildcard) or a prefix that subsumes
        # another run.
        unless @run_id.match?(/\A[A-Za-z0-9][A-Za-z0-9-]*\z/)
          raise ArgumentError,
                "run_id must be alphanumeric/hyphen (got #{@run_id.inspect}) — it scopes teardown"
        end
        @cleanup = cleanup
        @auto_approve = auto_approve
        @expected_count = expected_count
        @phase_pump = phase_pump
        @poll_interval = poll_interval
        @compose_timeout = compose_timeout
        @execute_timeout = execute_timeout
        @findings = []
        @started_at = Time.current
        @mission_id = nil
      end

      def run
        prior_gate = enable_gate!
        mission = nil
        begin
          mission = create_and_start_mission!
          drive!(mission)
        ensure
          # M3: teardown must never rob the account of its gate restore. Nest so
          # a raise in finalize! (cancel / teardown / instance query) still runs
          # restore_gate!.
          begin
            finalize!(mission) if mission
          ensure
            restore_gate!(prior_gate)
          end
        end
        # build_result runs AFTER finalize! so teardown findings (M3) are counted
        # in the exit code. It is skipped only when the body raised (a hard error
        # the caller must see) — the safety-guard raises are exactly that.
        build_result(mission)
      end

      private

      def name_prefix = "dryrun-#{@run_id}"

      # ---- supervision ---------------------------------------------------
      # Supervise the real pipeline to completion. The harness only approves its
      # own gates; capture/compose/execute/verify run on the worker (live) or
      # the injected pump (spec), never re-implemented here.
      def drive!(mission)
        if await_phase(mission, "review_plan", gate: true, timeout: @compose_timeout)
          if approve_gate!(mission, "review_plan") &&
             await_phase(mission, "handoff", gate: true, timeout: @execute_timeout)
            approve_gate!(mission, "handoff")
            await_phase(mission, "adapting", gate: false, timeout: @poll_interval * 5)
          end
        end
        record_stall_findings!(mission)
        grade!(mission)
      end

      # Poll (or pump) until the mission reaches `phase`. Returns true on reach,
      # false on timeout / a failure park / no-progress. The failure DETAIL is
      # recorded by record_stall_findings! so the wording stays in one place.
      def await_phase(mission, phase, gate:, timeout:)
        deadline = monotonic + timeout
        loop do
          m = uncached_reload(mission)
          reached = m.current_phase.to_s == phase && (!gate || m.awaiting_approval?)
          return true if reached
          return false if %w[failed cancelled].include?(m.status.to_s)
          # Any phase that records an error_message has failed and will not
          # self-advance (F2 parks an unhealthy verify this way; a composer/
          # capture failure similarly) — stop waiting immediately rather than
          # sleeping to the deadline live (S4).
          return false if m.error_message.present?
          return false if monotonic > deadline

          progressed = pump_or_sleep
          # A pump that drained zero jobs without reaching the phase means the
          # in-process pipeline has stalled — don't spin real-time to the
          # deadline (live has no pump; it legitimately sleeps and re-polls).
          return false if @phase_pump && progressed.to_i.zero?
        end
      end

      def pump_or_sleep
        return @phase_pump.call if @phase_pump

        sleep(@poll_interval)
        0
      end

      def approve_gate!(mission, gate)
        mission = uncached_reload(mission)
        unless mission.current_phase.to_s == gate
          add_finding("gate", "expected to approve '#{gate}' but mission is at '#{mission.current_phase}'", :high)
          return false
        end
        unless @auto_approve
          add_finding("gate", "auto-approve disabled; halted at #{gate}", :high)
          return false
        end
        # SAFETY: only ever approve the dryrun mission this harness created.
        unless mission.name.to_s.start_with?("dryrun-")
          raise "refusing to approve a non-dryrun mission (#{mission.name})"
        end
        ::Ai::Missions::OrchestratorService.new(mission: mission)
          .handle_approval!(gate: gate, user: @user, decision: "approved")
        # M5: the approval must actually move the mission off the gate. A
        # second-signature gate (Business+ plans) records the first approval and
        # stays put — headless we can never supply a second DISTINCT approver, so
        # fail loudly instead of letting grade! bless a parked mission as PASS.
        after = uncached_reload(mission)
        if after.current_phase.to_s == gate
          add_finding("gate", "approved '#{gate}' but mission did not advance (second-signature required?)", :high)
          return false
        end
        true
      end

      # ---- setup / teardown ----------------------------------------------
      # S4: settings is the account's DB-driven config surface; an unlocked
      # read-modify-write of the whole hash clobbers any concurrent writer.
      # Lock the row for both the enable and the restore.
      def enable_gate!
        @account.with_lock do
          settings = @account.settings.is_a?(Hash) ? @account.settings : {}
          prior = settings[GATE_SETTING]
          @account.update!(settings: settings.merge(GATE_SETTING => true))
          prior
        end
      end

      def restore_gate!(prior)
        @account.with_lock do
          settings = @account.settings.is_a?(Hash) ? @account.settings : {}
          if prior.nil?
            settings.delete(GATE_SETTING)
          else
            settings[GATE_SETTING] = prior
          end
          @account.update!(settings: settings)
        end
      end

      def create_and_start_mission!
        # M4: two concurrent runs whose ids prefix-subsume each other would let
        # one teardown catch the other's instances. Refuse to start when another
        # live dryrun mission already exists for this account.
        active = ::Ai::Mission
                 .where(account_id: @account.id, mission_type: "infrastructure")
                 .where("name LIKE ?", "dryrun-%")
                 .where.not(status: ::Ai::Mission::TERMINAL_STATUSES)
        if active.exists?
          raise "refusing to start: a live dryrun mission already exists for this account " \
                "(#{active.first.name}) — concurrent dryruns can cross blast radius"
        end

        mission = ::Ai::Mission.create!(
          account: @account, created_by: @user, mission_type: "infrastructure",
          name: name_prefix, objective: @objective, status: "draft",
          configuration: { "dryrun" => true, "dryrun_run_id" => @run_id }
        )
        # start! dispatches the capture_intent job — the pipeline drives itself
        # from here (worker live, injected pump in-spec).
        ::Ai::Missions::OrchestratorService.new(mission: mission).start!
        @mission_id = mission.id
        mission.reload
      end

      # Always runs (pass, fail, or stall). Order matters:
      #   1. cancel the harness's OWN mission — M1 (a live/adapting mission would
      #      block every future run) and M2 (a stalled run must terminalize the
      #      pipeline before sweeping, not tear down under a still-live worker).
      #   2. tear down the instances (only when @cleanup), recording completeness.
      def finalize!(mission)
        cancel_mission!(mission)
        teardown!(mission) if @cleanup
      end

      def cancel_mission!(mission)
        m = uncached_reload(mission)
        return if ::Ai::Mission::TERMINAL_STATUSES.include?(m.status.to_s)

        ::Ai::Missions::OrchestratorService.new(mission: m).cancel!(reason: "dryrun harness teardown")
      rescue StandardError => e
        Rails.logger.warn("[DryrunHarness] cancel of mission #{m&.id} failed: #{e.message}")
      end

      def teardown!(mission)
        return unless defined?(::System::ProvisioningService)

        svc = ::System::ProvisioningService.new
        failed = []
        dryrun_instances.each do |i|
          next if i.status.to_s == "terminated"

          # M3: terminate_instance returns Runtime::Result.err on provider refusal
          # (it does NOT raise) — capture that, don't discard it.
          result = svc.terminate_instance(instance: i)
          failed << i.name if result.respond_to?(:success?) && !result.success?
        rescue StandardError => e
          failed << i.name
          Rails.logger.warn("[DryrunHarness] teardown of #{i.name} failed: #{e.message}")
        end

        # S1/M3: teardown completeness (protocol §5 HARD criterion) is a FINDING,
        # not just a log line — it must move the exit code so CI/cron can't read a
        # leaked stack as a clean pass. build_result runs after finalize! so this
        # is counted.
        leftover = dryrun_instances.reject { |i| i.status.to_s == "terminated" }
        if leftover.any?
          add_finding("teardown", "teardown incomplete: #{leftover.size} instance(s) still present under " \
                                  "#{name_prefix} (#{leftover.map(&:name).join(', ')})", :high)
        elsif failed.any?
          add_finding("teardown", "terminate reported failure for #{failed.uniq.join(', ')}", :high)
        end
      end

      # ---- §5 grading ----------------------------------------------------
      # Record WHY the pipeline halted short of a terminal phase, in one place.
      def record_stall_findings!(mission)
        m = uncached_reload(mission)
        reason = m.error_message.presence
        case m.current_phase.to_s
        when "capture_intent"
          missing = m.configuration.is_a?(Hash) ? m.configuration["brief_missing_fields"] : nil
          add_finding("extraction", "brief incomplete, parked at capture_intent#{" (missing #{missing.inspect})" if missing.present?}", :high)
        when "compose_plan"
          add_finding("compose", "composer produced no plan#{" (#{reason})" if reason}", :high) unless plan_pointer(m)
        when "verify"
          add_finding("verify", "verification failed: #{reason || 'unhealthy'}", :high)
        end
      end

      def grade!(mission)
        brief = (mission.configuration.is_a?(Hash) ? mission.configuration["brief"] : nil) || {}
        plan = resolve_plan(mission)
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
        if plan && brief["budget_cap_usd_monthly"].present?
          snapshot = ::Ai::Provisioning::PlanSnapshotService.new(account: @account).snapshot(plan: plan)
          add_finding("budget", "snapshot did not surface a budget block", :low) if snapshot[:budget].nil?
        end

        # S1: a plan with docker_provision legs must yield DockerHosts — run g's
        # headline oracle. Grading 0-as-fine would let the container-runtime
        # handshake silently regress.
        if plan_has_docker_leg?(plan) && docker_host_count.zero?
          add_finding("docker", "plan has docker_provision leg(s) but no DockerHost was recorded", :medium)
        end

        # M2: the run must actually reach a terminal (adapting/completed) phase.
        # A silently parked mission with instances present would otherwise grade
        # PASS. S7: suppress this generic finding when a more specific stall
        # reason (compose/verify/extraction/gate) already names the same defect —
        # one defect, one finding, so the exit code stays a faithful count.
        final = uncached_reload(mission).current_phase.to_s
        already_explained = @findings.any? { |f| %w[compose verify extraction gate].include?(f.dimension) }
        unless TERMINAL_PHASES.include?(final) || already_explained
          add_finding("phase", "mission never reached adapting/completed (parked at '#{final}')", :high)
        end
      end

      def build_result(mission)
        Result.new(
          run_id: @run_id, mission_id: mission&.id,
          reached_phase: mission && uncached_reload(mission).current_phase,
          findings: @findings,
          oracles: {
            "instances" => dryrun_instances.size,
            "docker_hosts" => docker_host_count,
            "skill_usage" => skill_usage_count,
            # account-wide, time-windowed best-effort — see the oracle queries.
            "llm_executions" => execution_count,
            "routing_decisions" => routing_count,
            "verify_healthy" => (mission&.configuration&.dig("verification", "healthy") ||
              mission&.configuration&.dig("verification_result", "healthy")) == true
          }
        )
      end

      # A synthesized plan carries one docker_provision leg per instance; if any
      # exists, the run is expected to produce DockerHosts.
      def plan_has_docker_leg?(plan)
        return false unless plan

        steps = plan.respond_to?(:steps) ? plan.steps.to_a : Array(plan)
        steps.any? do |s|
          cfg = s.respond_to?(:execution_config) ? (s.execution_config || {}) : {}
          (cfg["skill"] || cfg[:skill]).to_s == "docker_provision"
        end
      rescue StandardError
        false
      end

      # ---- oracle / plan queries -----------------------------------------
      def plan_pointer(mission)
        mission.configuration.is_a?(Hash) ? mission.configuration.dig("plan", "plan_id") : nil
      end

      def resolve_plan(mission)
        id = plan_pointer(mission)
        return nil unless id && defined?(::Ai::GoalPlan)

        ::Ai::GoalPlan.find_by(id: id)
      end

      def dryrun_instances
        return [] unless defined?(::System::NodeInstance)

        # M4: escape LIKE metacharacters in the prefix and scope to THIS account
        # so teardown/grading can never reach another run's or tenant's instances.
        like = "#{ActiveRecord::Base.sanitize_sql_like(name_prefix)}%"
        ::System::NodeInstance.where(account_id: @account.id).where("name LIKE ?", like).to_a
      end

      def docker_host_count
        return 0 unless defined?(::Devops::DockerHost)

        ::Devops::DockerHost.where(node_instance_id: dryrun_instances.map(&:id)).count
      end

      # S2: mission-scoped by design. The old rescue fell back to an account-wide
      # ALL-TIME provisioning_step count that prior runs make positive — masking
      # both a query error and a genuine zero. The metadata->>'mission_id' query
      # is valid (jsonb column; the runner writes mission_id), so no fallback.
      def skill_usage_count
        ::Ai::SkillUsageRecord.where(account_id: @account.id)
          .where("metadata->>'mission_id' = ?", @mission_id.to_s).count
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

      def uncached_reload(mission)
        # rails-runner poll loops otherwise serve stale rows from the query cache.
        mission.class.uncached { mission.reload }
      end

      def monotonic = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      def add_finding(dimension, detail, severity)
        @findings << Finding.new(dimension: dimension, detail: detail, severity: severity)
      end
    end
  end
end
