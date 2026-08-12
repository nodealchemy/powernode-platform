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
    # SOAK MODE (`soak: true`, INC-5) adds one leg after the provisioning ones:
    # the mission is HELD active at `adapting` for a bounded window so the
    # evolution loop has a baseline to observe, then torn down as usual. The
    # supervisory posture does not change — a soak still refuses a non-dryrun
    # subject, approves only its own gates, and sweeps only its own prefix.
    # `teardown_only!` is the same finalize path on its own, for a run left
    # standing.
    #
    # SAFETY: every artifact carries the `dryrun-<runId>` prefix (the
    # blast-radius boundary); teardown terminates ONLY instances under that
    # prefix, account-scoped, LIKE-escaped; the account's routing gate is
    # restored to its prior value on the way out whether the run passes, fails,
    # or raises.
    class DryrunHarness
      GATE_SETTING = "ai_task_tier_routing_enabled"
      # Bookkeeping for the refcounted gate (see enable_gate!): who currently
      # holds it, and the account's own value from before the first holder.
      GATE_HOLDERS_SETTING = "ai_dryrun_gate_holders"
      GATE_PRIOR_SETTING   = "ai_dryrun_gate_prior"
      # The provisioning legs are DONE at one of these; a supervised run always
      # approves handoff to reach adapting, because handoff is a gate, never a
      # valid resting place (M5: a second-signature account parks there, and
      # grading that as done would be a false PASS).
      #
      # `adapting` is NOT an end of life. The mission template calls it
      # "long-lived, sensor-driven (no job class)", and ProjectSloSensor only
      # watches missions with status "active" — so a mission parked here with a
      # live status is exactly what the evolution loop observes. Soak mode holds
      # it here instead of terminalizing it (INC-5).
      DRIVE_COMPLETE_PHASES = %w[adapting completed].freeze
      # The phase a soak observes from.
      SOAK_PHASE = "adapting"

      # Soak bounds + spend ceiling — DB-driven config, resolved
      # Account#settings → SiteSetting → the DEFAULT_* constant below, the same
      # order Ai::FableRouting/TaskTierResolver use. `ai.dryrun.budget_usd` is
      # the key the dry-run protocol already documents; the two soak keys join
      # it. The constants are a last-resort floor, not a policy: an operator
      # changes any of them without a deploy.
      SOAK_SECONDS_SETTING    = "ai.dryrun.soak_max_seconds"
      SOAK_ITERATIONS_SETTING = "ai.dryrun.soak_max_iterations"
      BUDGET_SETTING          = "ai.dryrun.budget_usd"
      DEFAULT_SOAK_MAX_SECONDS    = 900
      DEFAULT_SOAK_MAX_ITERATIONS = 600
      DEFAULT_BUDGET_USD          = 5.0

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
      # @param soak [Boolean] hold the mission ACTIVE at `adapting` after the
      #   provisioning legs, so the evolution loop has a baseline to observe.
      # @param soak_pump [#call, nil] spec-only stand-in for the observation
      #   lane's production driver — the standalone worker's 60s cron POST to
      #   the fleet reconcile endpoint (FleetAutonomyService.tick!). nil ⇒ live:
      #   the harness sleeps and the real worker ticks. Observer mode holds here
      #   exactly as it does for phase_pump: the harness never ticks production.
      # @param soak_max_seconds/soak_max_iterations [Numeric, nil] explicit
      #   bounds; nil ⇒ resolved from config. Both are ceilings — whichever is
      #   reached first ends the soak.
      # @param force_teardown [Boolean] sweep even when the zero-orphan check
      #   fails. The halt is permanent otherwise (the orphan is recorded on the
      #   plan for good), so this is how an operator finishes a teardown after
      #   reading the leak. The finding is still recorded either way.
      def initialize(account:, user:, objective:, run_id:, cleanup: true, auto_approve: true,
                     expected_count: nil, phase_pump: nil, poll_interval: 2,
                     compose_timeout: 120, execute_timeout: 900,
                     soak: false, soak_pump: nil, soak_max_seconds: nil, soak_max_iterations: nil,
                     force_teardown: false)
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
        @soak = soak
        @force_teardown = force_teardown
        @soak_pump = soak_pump
        @soak_max_seconds = soak_max_seconds
        @soak_max_iterations = soak_max_iterations
        @soak_iterations = 0
        @soak_elapsed = 0.0
        @soak_stop_reason = nil
        @soak_started_at = nil
        @halt_before_teardown = false
        @findings = []
        @started_at = Time.current
        @mission_id = nil
      end

      def run
        enable_gate!
        mission = nil
        begin
          mission = create_and_start_mission!
          drive!(mission)
          soak!(mission) if @soak
        ensure
          # M3: teardown must never rob the account of its gate restore. Nest so
          # a raise in finalize! (cancel / teardown / instance query) still runs
          # restore_gate!.
          begin
            finalize!(mission) if mission
          ensure
            restore_gate!
          end
        end
        # build_result runs AFTER finalize! so teardown findings (M3) are counted
        # in the exit code. It is skipped only when the body raised (a hard error
        # the caller must see) — the safety-guard raises are exactly that.
        build_result(mission)
      end

      # The explicit teardown command (charter §9: "cancel mission BEFORE
      # sweep"). Finishes a run that was left standing — a `--no-cleanup` soak
      # an operator has since read, or a soak whose process died before its
      # `ensure` could run. Same order and same rails as an in-run finalize:
      # cancel this run_id's OWN mission first (so nothing keeps actuating
      # against a fleet being swept), assert the zero-orphan family, then sweep
      # by prefix — account-scoped, LIKE-escaped, halting before the sweep if an
      # orphan is present. It never touches the routing gate: it did not enable
      # it, and silently rewriting an account's settings from a cleanup command
      # is not this command's business.
      def teardown_only!
        refuse_overlapping_teardown!
        # ANY status, not just live: after a `--no-cleanup` soak the mission is
        # already cancelled, and it is the only handle on the plan whose steps
        # carry the actuator's recorded orphans. Cancelling is a no-op on a
        # terminal mission, so cancel-before-sweep still holds.
        mission = mission_for_prefix
        @mission_id = mission&.id
        # "Swept nothing" and "there was nothing to sweep" produce identical
        # output otherwise, so a mistyped run_id would exit 0 with a green
        # report. An already-swept run still has its (terminated) instance rows
        # under the prefix, so a genuine second teardown stays quiet.
        if mission.nil? && dryrun_instances.empty?
          add_finding("teardown", "no mission and no instance exists under #{name_prefix} — " \
                                  "nothing was torn down (wrong run_id?)", :medium)
        end
        finalize!(mission)
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

      # ---- soak (INC-5) ---------------------------------------------------
      # Hold the baseline under observation. The provisioning legs are over; the
      # mission sits at `adapting` with status "active", which is precisely the
      # scope ProjectSloSensor and ProjectMetricsCollector query. The harness
      # stays an OBSERVER here too — live it sleeps while the worker's 60s fleet
      # reconcile cron does the sensing; in-spec the injected soak_pump calls the
      # same service the cron's endpoint calls.
      #
      # BOUNDED BY CONSTRUCTION. Every exit is a ceiling: iterations, wall-clock
      # seconds, the LLM spend ceiling, or the mission leaving the observable
      # state. There is no "wait until something adapts" — the drift signal has
      # no live data source today (the collector resolves a mission's instance
      # ids one level too shallow, so replica_count/region_count report
      # `unavailable`), so a soak that waited for a sensor-driven adaptation
      # would wait for its whole window and call the timeout a result. It waits
      # for its window and says so instead; what the window OBSERVED is graded.
      def soak!(mission)
        m = uncached_reload(mission)
        unless m.current_phase.to_s == SOAK_PHASE && m.status.to_s == "active"
          @soak_stop_reason = "not_observable"
          unless stall_already_explained?
            add_finding("soak", "soak requested but the mission never became observable " \
                                "(phase='#{m.current_phase}', status='#{m.status}')", :high)
          end
          return
        end

        @soak_started_at = Time.current
        started = monotonic
        deadline = started + soak_max_seconds
        iterations = 0

        loop do
          iterations += 1
          @soak_pump ? @soak_pump.call : sleep(@poll_interval)

          m = uncached_reload(mission)
          unless m.status.to_s == "active"
            # ACTIVE, not merely non-terminal: the sensor's scope is
            # `status: "active"`, so a PAUSED mission is just as unobserved as a
            # cancelled one, and the rest of the window would see nothing while
            # reporting a full soak.
            @soak_stop_reason = "mission_#{m.status}"
            add_finding("soak", "mission left the observable state mid-soak (status='#{m.status}') " \
                                "after #{iterations} iteration(s)", :high)
            break
          end

          if budget_exhausted?
            # Stopping is the safe direction, so the ceiling acts on the
            # account-wide window it can actually measure (executions carry no
            # mission link). The FINDING says so rather than claiming the soak
            # itself spent it — on a busy account it may not have.
            @soak_stop_reason = "budget_ceiling"
            add_finding("soak", "soak stopped at the LLM budget ceiling: $#{format('%.4f', llm_spend_usd)} " \
                                "spent account-wide since the run started, ceiling $#{budget_ceiling_usd} " \
                                "(#{BUDGET_SETTING})", :medium)
            break
          end

          if iterations >= soak_max_iterations
            @soak_stop_reason = "max_iterations"
            break
          end

          if monotonic >= deadline
            @soak_stop_reason = "max_seconds"
            break
          end
        end

        @soak_iterations = iterations
        @soak_elapsed = (monotonic - started).round(2)
        grade_soak!(mission)
      end

      # §5 grading for the soak leg. Reads what production WROTE, not what the
      # harness was told: ProjectMetric rows are the collector's own output, and
      # the collector runs inside the same tick, over the same mission scope, as
      # the sensor. Rows for this mission ⇒ the mission really was under
      # observation for the window.
      def grade_soak!(mission)
        samples = project_metric_samples(mission)
        if samples.nil?
          add_finding("observation", "project metrics are unavailable in this install — " \
                                     "soak observation was not measured", :medium)
        elsif samples.zero?
          add_finding("observation", "no project-metric sample was recorded for the mission during the " \
                                     "soak — it was not under sensor observation", :high)
        elsif live_project_metric_samples(mission).zero?
          add_finding("observation", "#{samples} project-metric sample(s) recorded but none from a live " \
                                     "source — every metric reported `unavailable`, so no drift signal " \
                                     "can fire off this baseline", :medium)
        end
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
      #
      # REFCOUNTED, because non-overlapping runs may now be concurrent on one
      # account. A capture-and-restore pair is not composable: A captures nil and
      # sets true; B captures A's `true`; A exits and deletes the key, dropping
      # tier routing under a still-running B; B exits and writes `true` back,
      # leaving the account permanently gated. So the PRIOR value is captured
      # once, by whichever run arrives first, and held in the settings hash
      # beside a holder list — the last run out is the one that restores.
      #
      # A hard-killed run leaves a stale holder, which is the same failure class
      # as the existing "hard kill skips the ensure" hazard the README documents,
      # and it fails in the safe direction (the gate stays as the dryrun set it
      # rather than being restored out from under a live run).
      def enable_gate!
        @account.with_lock do
          settings = settings_hash
          holders = Array(settings[GATE_HOLDERS_SETTING]).map(&:to_s)
          # First holder captures the account's own value; later ones must not
          # capture a predecessor's `true`.
          settings[GATE_PRIOR_SETTING] = settings[GATE_SETTING] if holders.empty?
          settings[GATE_HOLDERS_SETTING] = (holders | [ @run_id ])
          settings[GATE_SETTING] = true
          @account.update!(settings: settings)
        end
        nil
      end

      def restore_gate!(_prior = nil)
        @account.with_lock do
          settings = settings_hash
          holders = Array(settings[GATE_HOLDERS_SETTING]).map(&:to_s) - [ @run_id ]
          if holders.any?
            # Another run is still inside its window — leave the gate enabled for
            # it and only drop this run's claim.
            settings[GATE_HOLDERS_SETTING] = holders
          else
            prior = settings[GATE_PRIOR_SETTING]
            prior.nil? ? settings.delete(GATE_SETTING) : settings[GATE_SETTING] = prior
            settings.delete(GATE_PRIOR_SETTING)
            settings.delete(GATE_HOLDERS_SETTING)
          end
          @account.update!(settings: settings)
        end
      end

      def settings_hash
        @account.settings.is_a?(Hash) ? @account.settings.dup : {}
      end

      def create_and_start_mission!
        # M4: two concurrent runs whose ids prefix-subsume each other would let
        # one teardown catch the other's instances.
        #
        # The property being defended is BLAST-RADIUS OVERLAP, not "a dryrun
        # exists". Teardown sweeps `dryrun-<runId>%`, so two runs collide iff one
        # prefix is a prefix of the other — `dryrun-evo-1` subsumes
        # `dryrun-evo-10`, while `dryrun-evo-01` and `dryrun-evo-02` can never
        # touch each other's instances. Refusing every concurrent dryrun was the
        # coarse form of this test, and it makes soak mode self-defeating: a
        # baseline held ACTIVE for the evolution loop would block every
        # subsequent run for the life of the soak, including the one meant to
        # observe it. Compared in Ruby over the (small) live set rather than in
        # SQL, so the prefix test is the same code in both directions and no
        # LIKE-escaping subtlety can widen it.
        overlapping = ::Ai::Mission
                      .where(account_id: @account.id, mission_type: "infrastructure")
                      .where("name LIKE ?", "dryrun-%")
                      .where.not(status: ::Ai::Mission::TERMINAL_STATUSES)
                      .find { |m| prefixes_overlap?(m.name.to_s, name_prefix) }
        if overlapping
          raise "refusing to start: run '#{name_prefix}' overlaps the blast radius of live dryrun " \
                "mission '#{overlapping.name}' — one run's teardown would sweep the other's instances"
        end

        # ...and the same test against INSTANCES, which now routinely outlive
        # their mission: a `--no-cleanup` neighbour and a halted-before-teardown
        # run both leave a standing fleet behind a terminal mission. This run has
        # created nothing yet, so anything already inside its blast radius is
        # someone else's — it would be mis-graded as this run's outcome and then
        # terminated by this run's sweep.
        standing = dryrun_instances.reject { |i| i.status.to_s == "terminated" }
        if standing.any?
          raise "refusing to start: run '#{name_prefix}' overlaps the blast radius of #{standing.size} " \
                "standing instance(s) (#{standing.first(3).map(&:name).join(', ')}) — this run's sweep " \
                "would terminate a fleet it did not provision"
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

      # Always runs (pass, fail, stall, or end of soak). Order matters:
      #   1. cancel the harness's OWN mission — M2 (a stalled run must terminalize
      #      the pipeline before sweeping, not tear down under a still-live
      #      worker) and, for a soak, so no mission keeps actuating unattended
      #      against a fleet that is about to be swept. Unconditional, exactly as
      #      before: `--no-cleanup` opts out of the SWEEP, never out of stopping
      #      the pipeline.
      #   2. assert the zero-orphan family — ALWAYS, `--no-cleanup` included: the
      #      halt is only the consequence, the oracle is the point, and a
      #      retained run is precisely the forensics case that must not be the
      #      one that says nothing.
      #   3. HALT before the sweep when that oracle fails (charter §9 stop
      #      condition) so the leak is read against a fleet that still matches
      #      the plan.
      #   4. tear down the instances (only when @cleanup), recording completeness.
      def finalize!(mission)
        cancel_mission!(mission) if mission
        orphaned = record_orphan_findings!(mission)
        return unless @cleanup

        if orphaned && !@force_teardown
          @halt_before_teardown = true
          Rails.logger.warn("[DryrunHarness] orphan(s) present under #{name_prefix} — " \
                            "halting before teardown; once the leak has been read, sweep with the " \
                            "teardown command's force option")
          return
        end

        # The recorded orphan is permanent — it lives on the plan step forever —
        # so without an acknowledgement the recovery command could never finish
        # the one run it exists to recover: every later teardown would re-read
        # the same row and halt again. Forcing does not erase the finding, so the
        # sweep is never silently blessed; it only says a human has now looked.
        if orphaned
          add_finding("orphan", "swept anyway: teardown was forced past the orphan halt", :medium)
        end

        teardown!(mission)
      end

      # The zero-orphan family, asserted before any sweep. TWO readers, on
      # purpose:
      #
      #   1. What the ACTUATOR recorded. `remove_replicas` runs its own
      #      post-teardown ground-truth sweep per victim (instance, SDWAN peer,
      #      provider volume, membership mirror) and records the survivors under
      #      `outputs.orphans`. Reading that beats reimplementing it — one
      #      reader of the family, so harness and actuator cannot disagree.
      #   2. An INDEPENDENT check core can make for itself: a provider volume
      #      still attached to a terminated instance under this run's prefix.
      #      Narrower than (1) — SDWAN peers are not reachable from core without
      #      depending on the extension — but it does not take the actuator's
      #      word for its own sweep, which is the whole lesson of the F5 oracle.
      #
      # Returns true when the run must halt.
      def record_orphan_findings!(mission)
        reported = actuator_reported_orphans(mission)
        if reported.any?
          add_finding("orphan", "the removal actuator recorded #{reported.size} orphaned resource(s) " \
                                "that survived teardown: #{reported.inspect[0, 300]}", :high)
        end

        dangling = dangling_volume_attachments
        if dangling.any?
          add_finding("orphan", "#{dangling.size} volume attachment(s) survive a terminated instance " \
                                "under #{name_prefix}: #{dangling.inspect[0, 300]}", :high)
        end

        reported.any? || dangling.any?
      end

      # Orphans as the actuator itself recorded them, on the live plan's steps —
      # nested under `last_outputs.outputs`, the convention the executors write
      # and VerificationService reads.
      def actuator_reported_orphans(mission)
        plan = mission && resolve_plan(mission)
        return [] unless plan

        plan.steps.to_a.flat_map do |step|
          meta = step.metadata.is_a?(Hash) ? step.metadata.deep_stringify_keys : {}
          Array(meta.dig("last_outputs", "outputs", "orphans"))
        end
      rescue StandardError => e
        Rails.logger.warn("[DryrunHarness] orphan read failed: #{e.class}: #{e.message}")
        []
      end

      # Volumes still pointing at an instance THIS RUN saw terminated, under this
      # run's prefix. Traversed through the association rather than the volume
      # model so the check reads whatever storage the instance actually carries.
      #
      # Scoped to the run's own window on purpose. Terminating an instance does
      # not detach its volumes, so every instance the harness itself sweeps ends
      # up looking exactly like this — a real gap (the sweep leaks volumes), but
      # a separate one, and halting a LATER teardown over it would strand a fleet
      # to protest something that teardown cannot fix. What this catches is a
      # removal that dropped its instance and left the storage behind while the
      # run is still live, which is the leak the charter stops for.
      def dangling_volume_attachments
        window = @started_at || 1.hour.ago
        dryrun_instances.select { |i|
          i.status.to_s == "terminated" && i.updated_at.present? && i.updated_at >= window
        }.flat_map do |instance|
          next [] unless instance.respond_to?(:provider_volumes)

          # A row that says it is already gone is not an attachment. `deleting`
          # IS still counted: the pump has drained by now, so a delete still in
          # flight at the end of the window is a leak, not a race.
          instance.provider_volumes
                  .where.not(status: "deleted")
                  .pluck(:id).map { |vid| { instance: instance.name, volume_id: vid } }
        end
      rescue StandardError => e
        Rails.logger.warn("[DryrunHarness] volume orphan read failed: #{e.class}: #{e.message}")
        []
      end

      # This run's OWN mission, whatever its status. Exact name match: the
      # teardown command finishes the run it was given, never a neighbour whose
      # prefix merely starts the same way.
      def mission_for_prefix
        ::Ai::Mission
          .where(account_id: @account.id, mission_type: "infrastructure", name: name_prefix)
          .order(created_at: :desc)
          .first
      end

      # The sweep is the most dangerous thing this class does, and
      # `--teardown-only` reaches it without passing the start-time guard. A
      # neighbour whose prefix this one subsumes (`evo-1` sweeping `evo-10`)
      # would lose its fleet, so re-run the same overlap test here.
      #
      # Covered: any neighbour whose mission is still live. NOT covered: a
      # neighbour whose mission is already terminal while its fleet stands —
      # that one is unreachable for a legally started run (the start-time
      # standing-instance guard refuses either run before it can exist), but it
      # is not re-derived here, so a hand-built pair of nested retained fleets
      # would still be swept together.
      def refuse_overlapping_teardown!
        neighbour = ::Ai::Mission
                    .where(account_id: @account.id, mission_type: "infrastructure")
                    .where("name LIKE ?", "dryrun-%")
                    .where.not(status: ::Ai::Mission::TERMINAL_STATUSES)
                    .where.not(name: name_prefix)
                    .find { |m| prefixes_overlap?(m.name.to_s, name_prefix) }
        return unless neighbour

        raise "refusing to tear down: sweeping '#{name_prefix}' overlaps the blast radius of live " \
              "dryrun mission '#{neighbour.name}' — it would terminate that run's instances"
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

        # M2: the run must actually get through the provisioning legs. A silently
        # parked mission with instances present would otherwise grade PASS. S7:
        # suppress this generic finding when a more specific stall reason
        # (compose/verify/extraction/gate) already names the same defect — one
        # defect, one finding, so the exit code stays a faithful count.
        final = uncached_reload(mission).current_phase.to_s
        unless DRIVE_COMPLETE_PHASES.include?(final) || stall_already_explained?
          add_finding("phase", "mission never reached adapting/completed (parked at '#{final}')", :high)
        end
      end

      # Whether a more specific finding already names why the pipeline halted
      # short. Shared by grade! and soak! so one defect stays one finding.
      def stall_already_explained?
        @findings.any? { |f| %w[compose verify extraction gate phase].include?(f.dimension) }
      end

      def build_result(mission)
        oracles = {
          "instances" => dryrun_instances.size,
          "docker_hosts" => docker_host_count,
          "skill_usage" => skill_usage_count,
          # account-wide, time-windowed best-effort — see the oracle queries.
          "llm_executions" => execution_count,
          "routing_decisions" => routing_count,
          "verify_healthy" => (mission&.configuration&.dig("verification", "healthy") ||
            mission&.configuration&.dig("verification_result", "healthy")) == true
        }
        oracles.merge!(soak_oracles(mission)) if @soak
        oracles["teardown"] = "halted (orphan present)" if @halt_before_teardown

        Result.new(
          run_id: @run_id, mission_id: mission&.id,
          reached_phase: mission && uncached_reload(mission).current_phase,
          findings: @findings,
          oracles: oracles
        )
      end

      # Soak-leg oracles. `soak_metric_samples` / `soak_live_metrics` are the
      # self-observation row of the charter's §8 table, read from
      # system_project_metrics — the collector's own output, not the harness's
      # opinion. `soak_live_metrics` is reported separately from the raw count
      # precisely because a batch of `unavailable` samples must never read as
      # observation.
      def soak_oracles(mission)
        {
          "soak_stop_reason" => @soak_stop_reason,
          "soak_iterations" => @soak_iterations,
          "soak_seconds" => @soak_elapsed,
          "soak_metric_samples" => project_metric_samples(mission),
          "soak_live_metrics" => live_project_metric_samples(mission),
          "soak_adaptations" => adaptation_plan_count(mission)
        }
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

      # ---- soak oracle / config queries -----------------------------------
      # Samples the collector wrote for THIS mission inside the soak window.
      # nil (not 0) when the metrics store is unavailable — "cannot see" and
      # "saw nothing" are different answers and grade differently.
      def project_metric_samples(mission)
        return nil unless mission && defined?(::System::ProjectMetric)

        scope = ::System::ProjectMetric.where(mission_id: mission.id)
        scope = scope.where("sampled_at >= ?", @soak_started_at) if @soak_started_at
        scope.count
      rescue StandardError => e
        Rails.logger.warn("[DryrunHarness] project metric read failed: #{e.class}: #{e.message}")
        nil
      end

      # Of those, the ones carrying a real measurement. The collector stamps
      # `source: "live"` only for a metric whose backend is actually wired;
      # everything else is an honest `unavailable` with observed nil.
      def live_project_metric_samples(mission)
        return 0 unless mission && defined?(::System::ProjectMetric)

        scope = ::System::ProjectMetric.where(mission_id: mission.id)
                                       .where("value->>'source' = ?", "live")
        scope = scope.where("sampled_at >= ?", @soak_started_at) if @soak_started_at
        scope.count
      rescue StandardError
        0
      end

      # Adaptation plans minted against this mission — the loop's own output,
      # by the key the proposer stamps.
      def adaptation_plan_count(mission)
        return 0 unless mission

        ::Ai::GoalPlan.where(account_id: @account.id)
                      .where("plan_data->>'kind' = ? AND plan_data->>'mission_id' = ?",
                             "adaptation_diff", mission.id)
                      .count
      rescue StandardError
        0
      end

      def llm_spend_usd
        ::Ai::AgentExecution.where(account_id: @account.id)
                            .where("created_at > ?", @started_at || 1.hour.ago)
                            .sum(:cost_usd).to_f
      rescue StandardError
        0.0
      end

      def budget_exhausted?
        ceiling = budget_ceiling_usd
        ceiling.positive? && llm_spend_usd >= ceiling
      end

      def budget_ceiling_usd = @budget_ceiling_usd ||= config_number(BUDGET_SETTING, DEFAULT_BUDGET_USD).to_f

      def soak_max_seconds = @resolved_soak_seconds ||=
        (@soak_max_seconds || config_number(SOAK_SECONDS_SETTING, DEFAULT_SOAK_MAX_SECONDS)).to_f

      def soak_max_iterations = @resolved_soak_iterations ||=
        (@soak_max_iterations || config_number(SOAK_ITERATIONS_SETTING, DEFAULT_SOAK_MAX_ITERATIONS)).to_i

      # DB-driven config: Account#settings → SiteSetting → default, reusing the
      # settings reader Ai::FableRouting/TaskTierResolver already share. A
      # non-numeric or non-positive configured value falls back to the default
      # rather than yielding a zero-length (or endless) soak from a typo — the
      # bound exists to guarantee termination, so it may never resolve to
      # "unbounded".
      def config_number(key, default)
        [ ::Ai::FableRouting.setting(@account, key), ::Ai::FableRouting.global_setting(key) ].each do |raw|
          next if raw.nil?

          value = raw.to_f
          return value if value.positive?

          Rails.logger.warn("[DryrunHarness] ignoring non-positive #{key}=#{raw.inspect}; using #{default}")
        end
        default
      rescue StandardError
        default
      end

      # Blast-radius overlap between two `dryrun-<runId>` names: teardown sweeps
      # `<name>%`, so either name being a prefix of the other means one run's
      # sweep can reach the other's instances.
      def prefixes_overlap?(a, b)
        a.start_with?(b) || b.start_with?(a)
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
