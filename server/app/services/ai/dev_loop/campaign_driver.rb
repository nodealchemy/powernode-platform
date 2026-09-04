# frozen_string_literal: true

module Ai
  module DevLoop
    # Orchestrates an Autonomous Improvement Campaign on top of the existing Ralph-loop machinery.
    # Starting a campaign creates the Campaign record plus a dedicated, campaign-scoped Ralph loop
    # that /dev-loop drains via dev_next_task / dev_complete_task. The driver is the single seam the
    # MCP campaign_* tools call, and where decision-authority / parked-question policy is applied.
    class CampaignDriver
      # Shared head + tail (incl. Fable autonomy/honesty tunings) live in
      # Ai::DevLoop::LoopGuardrails; only the campaign-specific middle lines are here.
      DEFAULT_GUARDRAILS = LoopGuardrails.compose(
        "Re-verify the finding against current code BEFORE changing anything (findings rot)",
        "Write a failing test reproducing the finding FIRST; confirm it is red",
        "Independent review of the diff before committing (don't trust green alone)",
        "Commit only to the campaign branch — never develop/master, never push"
      )

      # What a campaign drives: drain improvements, build a feature, or stand up a
      # new project. The loop body + guardrails are shared; the workload tags the
      # loop so /campaign run picks the right posture and discovery refill.
      WORKLOADS = %w[improvement-campaign feature-development new-project].freeze
      DEFAULT_WORKLOAD = "improvement-campaign"

      # Defaults merged UNDER caller-supplied stop_conditions (caller wins). G2: a
      # default acceptance-rate floor (anti-churn) so a campaign stops on sustained
      # net-loss even when the operator doesn't set one. Deliberately NO default
      # completion_pct here — a 100% target on an unseeded loop self-finalizes early.
      DEFAULT_STOP_CONDITIONS = { "min_acceptance_pct" => 50 }.freeze

      def initialize(account:, user: nil)
        @account = account
        @user = user
      end

      # Create the campaign + its dedicated Ralph loop, mark it active, take a first snapshot.
      def start(name:, description: nil, configuration: {}, decision_authority: "trusted",
                stop_conditions: {}, workload: DEFAULT_WORKLOAD)
        workload = DEFAULT_WORKLOAD unless WORKLOADS.include?(workload)
        config = (configuration || {}).merge("workload" => workload)
        # Atomic: a mid-way failure must not leave an orphan campaign with no loop.
        campaign = nil
        loop = nil
        Ai::Campaign.transaction do
          campaign = @account.ai_campaigns.create!(
            name: name, description: description, created_by_id: @user&.id,
            configuration: config, decision_authority: decision_authority,
            stop_conditions: DEFAULT_STOP_CONDITIONS.merge((stop_conditions || {}).stringify_keys),
            status: "created"
          )
          loop = create_campaign_loop(campaign, workload: workload)
          # Seed one pending task per planned increment so total_tasks reflects the WHOLE
          # plan (an increment passing reads e.g. 1/15, not 1/1 = 100%). No-op when the
          # caller supplied no plan_increments — behavior is then unchanged (no seeded tasks).
          seed_plan_increments!(loop, config["plan_increments"])
          campaign.start!
        end
        # Snapshot after seeding so total_tasks/completion_pct reflect the seeded plan.
        campaign.snapshot_progress!
        { campaign: campaign, loop: loop }
      end

      # Live status: refresh the ledger, then return the campaign summary, its open questions, its
      # recent decisions, and its loops — everything the dashboard / an operator needs.
      def status(campaign)
        campaign.snapshot_progress!
        {
          campaign: campaign.reload.summary,
          activity: campaign.activity_feed(limit: 20),
          open_questions: campaign.open_questions_list.map(&:summary),
          recent_decisions: campaign.campaign_decisions.recent(10).map(&:summary),
          loops: campaign.ralph_loops.map do |l|
            { id: l.id, name: l.name, branch: l.branch, status: l.status,
              total_tasks: l.ralph_tasks.count }
          end
        }
      end

      # Become (or renew being) the single active driver for this campaign before
      # driving it. A campaign/<id> branch + the progress ledger are mutated by
      # whoever drives the campaign; two concurrent drivers race. Returns
      # { ok: true, lease: {holder:, expires_at:} } when this holder now holds the
      # lease, or { ok: false, held_by:, expires_at: } when another driver holds it —
      # the caller backs off instead of double-driving. `holder` identifies the driver
      # (e.g. a session id); defaults to the driver's user id.
      def claim(campaign, holder: nil, ttl: nil)
        who = (holder.presence || @user&.id&.to_s)
        ok = if ttl
               campaign.acquire_driver_lease!(holder: who, ttl: ttl)
             else
               campaign.acquire_driver_lease!(holder: who)
             end
        campaign.reload
        if ok
          campaign.touch_activity!
          { ok: true, lease: campaign.driver_lease_info }
        else
          { ok: false, held_by: campaign.driver_lease_holder, expires_at: campaign.driver_lease_expires_at }
        end
      end

      # Release this campaign's single-driver lease (call when done driving). Returns
      # { ok: true } once the lease is free, { ok: false } if a different driver holds it.
      def release(campaign, holder: nil)
        who = (holder.presence || @user&.id&.to_s)
        { ok: campaign.release_driver_lease!(holder: who) }
      end

      # Route a campaign's loop(s) to a driver — interchangeably between a Claude Code
      # session (the dev-loop pull queue) and the platform executor (a platform
      # agent/group/mission). The single-driver lease enforces one active driver, so a
      # REASSIGNMENT releases the current lease first (the new driver then claims it),
      # and the loop's scheduling is flipped so the right executor picks it up:
      #   claude_code → scheduling_mode "manual" (CC pulls; platform scheduler skips it);
      #   platform_*  → scheduling_mode "continuous" + due now (platform scheduler runs it),
      #                 wiring the target agent/mission onto the loop.
      # `target` carries the platform ref ({ "agent_id"|"group_id"|"mission_id" => ... }).
      # `holder` (claude_code only) immediately takes the lease for that session.
      def delegate(campaign, driver_kind:, target: {}, holder: nil)
        raise ArgumentError, "unknown driver_kind: #{driver_kind}" unless Ai::RalphLoop::DRIVER_KINDS.include?(driver_kind)

        # Validate + account-scope the target BEFORE any mutation: a caller may only wire
        # THEIR OWN account's agent/mission onto a loop (cross-account IDOR guard), and a
        # platform_* delegation must carry the executor ref it needs (no wedged loops).
        normalized_target = validate_and_resolve_target!(driver_kind, (target || {}).deep_stringify_keys)

        lease = nil
        # Atomic reassignment under the campaign row lock: release the incumbent lease
        # (operator override), re-route every loop, and — for a flat-rate CLI driver — take
        # the lease, as one unit. Without the lock a concurrent pull/scheduler/delegate could interleave
        # between release and re-acquire and leave the lease holder misaligned with driver_kind.
        campaign.with_lock do
          campaign.release_driver_lease!(holder: campaign.driver_lease_holder) if campaign.driver_lease_active?
          campaign.ralph_loops.find_each { |loop_record| apply_driver_routing!(loop_record, driver_kind, normalized_target) }
          if Ai::RalphLoop::FLAT_RATE_DRIVER_KINDS.include?(driver_kind) && holder.present?
            campaign.acquire_driver_lease!(holder: holder) # succeeds: lease was just released under this lock
            lease = campaign.driver_lease_info
          end
        end
        campaign.touch_activity! if campaign.respond_to?(:touch_activity!)

        {
          campaign_id: campaign.id, driver_kind: driver_kind, target: normalized_target, lease: lease,
          loops: campaign.ralph_loops.reload.map do |l|
            { id: l.id, driver_kind: l.driver_kind, scheduling_mode: l.scheduling_mode, status: l.status }
          end
        }
      end

      # Answer a parked question (which can unblock its associated task downstream).
      def answer_question(campaign, question_id:, answer:)
        q = campaign.parked_questions.find(question_id)
        q.answer!(answer, user: @user)
        q.reload.summary
      end

      # Stop the campaign: pause its loops' scheduling (executors stop pulling) + mark completed.
      def stop(campaign, summary: nil)
        campaign.ralph_loops.each do |l|
          l.pause_schedule!(reason: "campaign stopped") if l.respond_to?(:pause_schedule!)
        end
        campaign.complete!(summary)
        campaign.reload.summary
      end

      # Record one completed campaign increment in a single call: mark a RalphTask
      # on the campaign loop (passed by default), log a decision, and snapshot
      # progress — so completion% reflects real work without each driver having to
      # hand-assemble those three steps (previously manual/instruction-dependent).
      # Idempotent on task_key.
      def record_increment!(campaign, title:, summary: nil, task_key: nil, decision_type: "build",
                            rationale: nil, status: "passed", metadata: {}, check_results: {})
        loop_record = campaign.ralph_loops.order(:created_at).first
        raise ArgumentError, "campaign has no loop to record against" unless loop_record

        key = (task_key.presence || "increment-#{title}").to_s.parameterize
        key = "increment-#{SecureRandom.hex(4)}" if key.blank?

        task = nil
        iteration = nil
        decision = nil
        # Atomic: the task transition + iteration + decision + snapshot are one unit, so a
        # mid-way failure can't leave a passed task with an orphan iteration and no decision.
        campaign.transaction do
          # A CC/CLI-drained campaign loop is never claimed via dev_next_task, so the
          # first recorded increment is the moment it factually starts running (also a
          # prerequisite for closeout: only a running/paused loop can legally complete!).
          loop_record.start! if loop_record.can_start?

          task = loop_record.ralph_tasks.find_or_initialize_by(task_key: key[0, 120])
          task.description = summary.presence || title
          task.status = status
          task.iteration_completed_at = Time.current if Ai::RalphTask::TERMINAL_STATUSES.include?(status)
          task.metadata = (task.metadata || {}).merge(metadata)
          task.save!

          iteration = record_iteration!(loop_record, task, status: status, summary: summary.presence || title,
                                        metadata: metadata, check_results: check_results)

          decision = campaign.record_decision!(
            decision_type: decision_type, title: title, rationale: rationale,
            task: task, user: @user, metadata: metadata
          )
          campaign.snapshot_progress!
        end

        # Goal-driven loop completion — the follow-up promised by the
        # IMP-af21b11d476c investigation note that previously lived here. A bare
        # all_tasks_completed? check on every increment would reopen the
        # premature-finalization bug on UNSEEDED loops (the first passed
        # increment reads 1/1 = 100%; see Campaign#should_stop?'s guard and the
        # regression spec), so completion is keyed to the loop's OWN completion
        # criteria instead, which seed_plan_increments! sets only when the
        # campaign was started with a seeded plan: the plan defines the whole
        # work, so every planned task terminal ⇒ the loop is genuinely done.
        # Unseeded loops have no criteria (goal_met? is false) and stay
        # open-ended, exactly as before.
        if loop_record.goal_met? && loop_record.can_complete?
          loop_record.complete!(result: { "reason" => "seeded_plan_drained" })
        end

        # Finalize the campaign if this increment drained it (all loops ended,
        # tasks terminal, no open questions) or met a stop condition — so it
        # doesn't linger at status=active/100% forever.
        campaign.maybe_finalize!

        {
          task_key: task.task_key, status: task.status,
          iteration_number: iteration&.iteration_number, decision_id: decision.id,
          campaign: campaign.reload.summary
        }
      end

      # Record a Ralph iteration for a CC-driven increment. The platform executor
      # writes RalphIteration rows per run; loops driven from Claude Code (composing
      # /improve + /dev-loop) otherwise have NO iteration history. This fills it in.
      # Idempotent-ish: re-recording the same task adds a new iteration row (each run
      # is a real iteration); callers pass a stable task_key for the task itself.
      def record_iteration!(loop_record, task, status:, summary:, metadata: {}, check_results: {})
        iter_status = case status
                      when "failed" then "failed"
                      when "skipped" then "skipped"
                      else "completed"
                      end
        # checks_passed is a VERIFIED claim, adjudicated with the same vocabulary
        # as the dev-loop bridge (IMP-aa8a2f58e01e): a passed increment records
        # true only when its evidence carries a green machine tally. Unlike the
        # bridge this seam never REJECTS a contradicted increment — it is history
        # recording, and the revert metric is the backstop — but an attested or
        # contradicted pass records false.
        evidence = check_results.is_a?(Hash) ? check_results : {}
        adjudication = Ai::Ralph::TestVerificationService.adjudicate_check_results(evidence)
        now = Time.current
        number = (loop_record.ralph_iterations.maximum(:iteration_number) || 0) + 1
        loop_record.ralph_iterations.create!(
          iteration_number: number, ralph_task: task, status: iter_status,
          started_at: now, completed_at: now, duration_ms: 0,
          checks_passed: (status == "passed" && adjudication[:verdict] == :verified),
          ai_output: summary,
          check_results: evidence.merge("evidence_verdict" => adjudication[:verdict].to_s),
          git_branch: loop_record.branch, git_commit_sha: metadata["commit"]
        )
      rescue ActiveRecord::RecordInvalid => e
        Rails.logger.warn("[CampaignDriver] record_iteration! failed: #{e.message}")
        nil
      end

      # Backfill: give existing campaign loops their campaign's display name (for the
      # execution interface), replacing the legacy "campaign-<id>" names. Idempotent.
      # Returns the count renamed.
      def relabel_campaign_loops!
        renamed = 0
        @account.ai_campaigns.find_each do |campaign|
          campaign.ralph_loops.where.not(name: campaign.name).find_each do |loop_record|
            loop_record.update!(name: campaign.name)
            renamed += 1
          end
        end
        renamed
      end

      # Request that a completed campaign change-set be landed to a target branch.
      # Creates an Ai::CampaignLand behind the approval gate (auto-approves only
      # for an autonomous campaign). The land worker drives it from there.
      def request_land(campaign, source_branch: nil, target_branch: "develop", description: nil, priority: 0)
        Ai::Land::ApprovalBinding.request_land_approval(
          campaign: campaign,
          source_branch: source_branch || campaign.ralph_loops.first&.branch,
          target_branch: target_branch,
          description: description,
          requested_by: @user,
          priority: priority
        )
      end

      # Advise the drivers of any open campaign whose branch is behind `target_branch`
      # that a rebase is needed (conflict avoidance). Covers target advances from ANY
      # source — auto-lands, manual lands (operator ff), other-repo pushes — so it can
      # be invoked on a schedule or after a manual land. Deduped per target tip.
      def notify_rebase_advisories(target_branch: "develop", exclude: nil)
        advised = Ai::Land::RebaseAdvisor.new(account: @account)
                                         .notify_stale!(target_branch: target_branch, exclude: exclude)
        {
          target_branch: target_branch,
          advised: advised.map do |adv|
            { id: adv.campaign.id, name: adv.campaign.name,
              commits_behind: adv.commits_behind, likely_conflicts: adv.likely_conflicts }
          end
        }
      end

      private

      # Validate the delegation target and resolve it to account-owned refs. Raises
      # ArgumentError (→ REST 422 / MCP error_result) on a missing-or-foreign ref. The
      # model-level mission_belongs_to_account / default_agent_belongs_to_account
      # validations are the defense-in-depth backstop.
      def validate_and_resolve_target!(driver_kind, target)
        case driver_kind
        when *Ai::RalphLoop::FLAT_RATE_DRIVER_KINDS
          # Flat-rate CLI drivers (claude_code / external_cli) pull from the queue; no platform target.
          {}
        when "platform_agent"
          # HIER-P2B-ENG (operator ruling 2026-09-03 #4): the Platform Developer
          # is the platform_agent driver of dev-improve, so a delegation that
          # names no agent resolves to it. A default is a RESOLUTION, not a
          # bypass: with no Platform Developer canonical present the empty
          # target still raises, so no loop is ever wedged on a nil agent.
          #
          # OWNERSHIP is still the scope. The resolution hands back an
          # ACCOUNT-OWNED row — the account's existing clone of the canonical,
          # or a fresh clone minted here — never the global canonical itself,
          # because Ai::AgentToolBridgeService executes a loop's agent as
          # `agent.creator` and a global canonical's creator belongs to the
          # seeding account (see RalphLoop#default_agent_belongs_to_account).
          id = target["agent_id"].presence || default_platform_agent&.id
          raise ArgumentError, "platform_agent delegation requires target.agent_id" if id.blank?
          raise ArgumentError, "agent not found in this account" unless @account.ai_agents.exists?(id: id)

          { "agent_id" => id }
        when "platform_mission"
          id = target["mission_id"].presence
          raise ArgumentError, "platform_mission delegation requires target.mission_id" if id.blank?
          raise ArgumentError, "mission not found in this account" unless @account.ai_missions.exists?(id: id)

          { "mission_id" => id }
        when "platform_team"
          # "Agent group" is unified into Ai::AgentTeam (the canonical agent grouping) — a
          # platform_team delegation routes the loop to a team the account owns.
          id = target["team_id"].presence
          raise ArgumentError, "platform_team delegation requires target.team_id" if id.blank?
          raise ArgumentError, "team not found in this account" unless @account.ai_agent_teams.exists?(id: id)

          { "team_id" => id }
        else
          raise ArgumentError, "unknown driver_kind: #{driver_kind}"
        end
      end

      # The account's OWN Platform Developer: its existing row for the slug if it
      # has one, otherwise a clone of the global canonical minted through the
      # HIER-P1 canonical rule. Nil when no canonical is seeded, which the
      # caller turns into the "requires target.agent_id" refusal.
      #
      # Why a clone and not the canonical: Ai::Ralph::TaskExecutor runs a loop's
      # default_agent through Ai::AgentToolBridgeService, which resolves tools
      # and permissions as `agent.creator`. The canonical's creator is a user in
      # the SEEDING account, so driving another account's loop with the global
      # row would execute that account's work under a foreign principal — and
      # since HIER-P2I the tool seam refuses a global canonical outright.
      #
      # The rule lives in Ai::Agents::AccountPrincipalResolver (HIER-P2I
      # extracted it from here so the fleet tick, the CVE responder and the
      # concierge resolve through the SAME copy); this is one consumer of it.
      def default_platform_agent
        Ai::Agents::AccountPrincipalResolver.for(
          canonical_slug: Ai::RalphLoop::PLATFORM_AGENT_DEFAULT_SLUG, account: @account, user: @user
        )
      end

      # Apply one loop's driver routing + scheduling for #delegate (see its docs).
      def apply_driver_routing!(loop_record, driver_kind, target)
        attrs = { driver_kind: driver_kind, driver_target: target }
        case driver_kind
        when *Ai::RalphLoop::FLAT_RATE_DRIVER_KINDS
          # Flat-rate CLI drivers (claude_code / external_cli) pull manually; keep them off the platform scheduler.
          attrs[:scheduling_mode] = "manual"
          attrs[:next_scheduled_at] = nil
        else # platform_agent | platform_team | platform_mission
          attrs[:default_agent_id] = target["agent_id"] if target["agent_id"].present?
          attrs[:mission_id] = target["mission_id"] if target["mission_id"].present?
          attrs[:scheduling_mode] = "continuous"
          attrs[:schedule_config] = (loop_record.schedule_config || {}).merge("iteration_interval_seconds" => 60)
          attrs[:schedule_paused] = false
          attrs[:status] = "running" unless loop_record.status == "running"
        end
        loop_record.update!(attrs)
        # The scheduling_mode change recomputes next_scheduled_at into the future; make the
        # loop due immediately so the platform scheduler picks it up on its next pass.
        # Flat-rate CLI drivers pull manually and are never on the platform scheduler.
        loop_record.update_columns(next_scheduled_at: Time.current) unless Ai::RalphLoop::FLAT_RATE_DRIVER_KINDS.include?(driver_kind)
      end

      # Seed the campaign plan as pending RalphTasks on its loop, one per increment, so
      # completion_pct measures progress against the whole plan rather than against the
      # single task the first increment would otherwise create. Each increment is either a
      # String title or a Hash { "title" =>, "description" =>, "task_key" => }. task_key
      # derivation mirrors #record_increment! ("increment-<title>".parameterize, 120-char
      # cap), so a later record_increment! on the same title flips the seeded task from
      # pending → passed instead of adding a duplicate. Duplicate keys within one plan are
      # disambiguated with a -N suffix to satisfy the (loop, task_key) uniqueness constraint.
      def seed_plan_increments!(loop_record, increments)
        return unless increments.is_a?(Array)

        seen = Hash.new(0)
        seeded = 0
        increments.each_with_index do |inc, idx|
          spec = inc.is_a?(Hash) ? inc.deep_stringify_keys : { "title" => inc.to_s }
          title = spec["title"].to_s
          next if title.blank? && spec["task_key"].blank?

          key = (spec["task_key"].presence || "increment-#{title}").to_s.parameterize
          key = "increment-#{idx + 1}" if key.blank?
          key = key[0, 120]
          seen[key] += 1
          key = "#{key}-#{seen[key]}"[0, 120] if seen[key] > 1

          loop_record.ralph_tasks.create!(
            task_key: key,
            description: spec["description"].presence || title.presence || key,
            status: "pending",
            position: idx + 1
          )
          seeded += 1
        end
        return if seeded.zero?

        # A seeded plan defines the campaign's WHOLE work upfront, so "every planned
        # task terminal" is a genuine completion goal: set the loop's completion
        # criteria so the goal-driven terminator (record_increment! / G5 in
        # dev_next_task) can end the loop when the plan drains and maybe_finalize!
        # can close the campaign. Unseeded loops get NO criteria and stay
        # open-ended by design (premature-finalization guard).
        loop_record.update!(
          configuration: loop_record.configuration.merge("completion" => { "all_tasks_terminal" => true })
        )
      end

      def create_campaign_loop(campaign, workload: DEFAULT_WORKLOAD)
        campaign.ralph_loops.create!(
          account: @account,
          # Human campaign name for the execution interface (loops are referenced by
          # id / campaign_id / branch, never by this name — safe to be display-friendly).
          name: campaign.name,
          description: "Drives #{workload} campaign: #{campaign.name}",
          ai_tool: "claude_code",
          scheduling_mode: "manual",
          # Campaigns start drained by a Claude Code session (pull queue); delegate to a
          # platform driver via #delegate. nil would mean "legacy" — campaigns are explicit.
          driver_kind: "claude_code",
          status: "pending",
          branch: "campaign/#{campaign.id}",
          max_iterations: 500,
          configuration: {
            "workload" => workload,
            "campaign_id" => campaign.id,
            "guardrails" => DEFAULT_GUARDRAILS
          }
        )
      end
    end
  end
end
