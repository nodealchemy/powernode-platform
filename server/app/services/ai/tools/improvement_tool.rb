# frozen_string_literal: true

module Ai
  module Tools
    # Dual-surface MCP tool for the improvement-discovery loop (Tier-1).
    #
    # Claude Code's /improve skill (and platform agents) call this to persist
    # vetted code-quality findings as Ai::ImprovementRecommendation "offers",
    # triage them, and promote an approved offer into a dev-improve Ralph Loop
    # task that /dev-loop drains. Discovery intelligence (running the code_*
    # analyzers + verify-before-offer) lives in the caller; this tool owns
    # persistence, fingerprint dedupe, the human-approval gate, core-purity
    # tagging (gate #9), and task promotion.
    class ImprovementTool < BaseTool
      REQUIRED_PERMISSION = "ai.agents.update"

      CODE_TYPES = Ai::ImprovementRecommendation::CODE_QUALITY_TYPES

      def self.definition
        {
          name: "improvement",
          description: "Discover, offer, triage and approve code-quality improvements for the dev-improve loop",
          parameters: {
            action: { type: "string", required: true, description: "discover_improvements | create_improvement | list_improvements | approve_improvement | dismiss_improvement | revert_improvement | enable_autonomy | disable_autonomy | scoreboard" },
            class_tag: { type: "string", required: false, description: "Recurring-bug-class learning tag (as used by query_learnings); switches discover_improvements to a class-sweep that exhausts ALL instances of the class in one pass" },
            recommendation_type: { type: "string", required: false, description: CODE_TYPES.join(" | ") },
            repository: { type: "string", required: false, description: "Repository id/full_name; resolved to a Devops::GitRepository target when known, else recorded as a tag" },
            agent_id: { type: "string", required: false, description: "Agent (UUID/slug/name) to drain the dev-improve loop when enabling autonomy" },
            max_iterations_per_day: { type: "integer", required: false, description: "Daily iteration cap for unattended autonomy" },
            reason: { type: "string", required: false, description: "Reason for revert_improvement" },
            title: { type: "string", required: false, description: "Short finding title" },
            description: { type: "string", required: false, description: "What to fix and why" },
            files: { type: "array", required: false, description: "Files the finding touches" },
            fingerprint: { type: "string", required: false, description: "Stable dedupe key, e.g. kind|file|rule" },
            fix: { type: "string", required: false, description: "Suggested fix / acceptance detail" },
            verifier_evidence: { type: "string", required: false, description: "Proof the finding reproduces on HEAD (verify-before-offer)" },
            confidence_score: { type: "number", required: false, description: "0..1 confidence (default 0.6)" },
            recommendation_id: { type: "string", required: false, description: "Target recommendation for approve/dismiss" },
            status: { type: "string", required: false, description: "Filter for list: pending|approved|applied|dismissed" }
          }
        }
      end

      def self.action_definitions
        {
          "discover_improvements" => {
            description: "Guidance for running discovery: run code_static_analysis + pattern-validation.sh " \
                         "(and code_dead_code / code_find_duplicates), verify each finding reproduces on HEAD, " \
                         "then call create_improvement for each vetted finding. Pass class_tag (a recurring " \
                         "bug-class learning tag) to switch to a targeted class-sweep that returns the known " \
                         "instances and exhausts every pattern match of the class in ONE pass.",
            parameters: {
              class_tag: { type: "string", required: false, description: "Recurring-bug-class learning tag, e.g. class:server-worker-jobseam" }
            }
          },
          "create_improvement" => {
            description: "Persist one vetted code-quality finding as a pending offer. Idempotent on fingerprint " \
                         "(re-creating updates the open offer). Findings under extensions/private/* are tagged to " \
                         "the extension (gate #9), never globalized.",
            parameters: {
              recommendation_type: { type: "string", required: true, description: CODE_TYPES.join(" | ") },
              title: { type: "string", required: true, description: "Short finding title" },
              fingerprint: { type: "string", required: true, description: "Stable dedupe key, e.g. kind|file|rule" },
              repository: { type: "string", required: false, description: "Repository id/full_name; resolved to a GitRepository target when known" },
              description: { type: "string", required: false, description: "What to fix and why" },
              files: { type: "array", required: false, description: "Files the finding touches" },
              fix: { type: "string", required: false, description: "Suggested fix / acceptance detail" },
              verifier_evidence: { type: "string", required: false, description: "Proof the finding reproduces on HEAD" },
              confidence_score: { type: "number", required: false, description: "0..1 confidence (default 0.6)" }
            }
          },
          "list_improvements" => {
            description: "List improvement offers, newest first.",
            parameters: {
              status: { type: "string", required: false, description: "pending | approved | applied | dismissed (default pending)" },
              repository: { type: "string", required: false, description: "Filter by repository (id/full_name); matches the GitRepository target or legacy tag" }
            }
          },
          "approve_improvement" => {
            description: "Approve an offer and promote it to a dev-improve Ralph Loop task that /dev-loop drains. " \
                         "No-op (halted) when the account kill switch is active.",
            parameters: {
              recommendation_id: { type: "string", required: true, description: "Recommendation to approve" }
            }
          },
          "dismiss_improvement" => {
            description: "Dismiss an offer so it is never promoted. If it was already approved/promoted, the " \
                         "pending/blocked dev-improve task is cascaded to skipped in the same transaction; an " \
                         "in_progress or already-terminal task is left untouched and named back in the response.",
            parameters: {
              recommendation_id: { type: "string", required: true, description: "Recommendation to dismiss" }
            }
          },
          "revert_improvement" => {
            description: "Mark the dev-improve task promoted from a recommendation as reverted (ground-truth " \
                         "signal for the ungameable metric). Works even while the kill switch is active.",
            parameters: {
              recommendation_id: { type: "string", required: true, description: "Recommendation whose promoted task was reverted" },
              reason: { type: "string", required: false, description: "Why it was reverted" }
            }
          },
          "enable_autonomy" => {
            description: "Gated opt-in: flip the dev-improve loop to unattended autonomous push drained by a " \
                         "capability-matched platform agent. OFF by default; refused while the kill switch is active.",
            parameters: {
              agent_id: { type: "string", required: true, description: "Agent (UUID/slug/name) to drain the loop" },
              max_iterations_per_day: { type: "integer", required: false, description: "Daily iteration cap" }
            }
          },
          "disable_autonomy" => {
            description: "Return the dev-improve loop to operator-driven (pull) execution.",
            parameters: {}
          },
          "scoreboard" => {
            description: "Improvement scoreboard: discovered/approved/applied/dismissed offer counts plus the " \
                         "ungameable metric (revert-adjusted net_improvement_velocity + per-kind revert_rate).",
            parameters: {}
          }
        }
      end

      protected

      def call(params)
        return error_result("Account context required") unless account

        case params[:action]
        when "discover_improvements" then discover_guidance(params)
        when "create_improvement" then create_improvement(params)
        when "list_improvements" then list_improvements(params)
        when "approve_improvement" then approve_improvement(params)
        when "dismiss_improvement" then dismiss_improvement(params)
        when "revert_improvement" then revert_improvement(params)
        when "enable_autonomy" then enable_autonomy(params)
        when "disable_autonomy" then disable_autonomy(params)
        when "scoreboard" then scoreboard(params)
        else error_result("Unknown action: #{params[:action]}")
        end
      end

      private

      def discover_guidance(params = {})
        class_tag = params[:class_tag].to_s.strip
        return class_sweep_guidance(class_tag) if class_tag.present?

        success_result(
          mode: "general",
          guidance: "Run platform.code_static_analysis and scripts/pattern-validation.sh (plus code_dead_code / " \
                    "code_find_duplicates as needed). For EACH finding: verify it still reproduces on HEAD " \
                    "(use code_blast_radius before proposing a deletion), then call create_improvement with a " \
                    "stable fingerprint and verifier_evidence. Findings under extensions/private/* are tagged to " \
                    "the extension automatically — never offer them as core/global. " \
                    "TRUST pattern-validation.sh's PASS/FAIL results — do NOT hand-roll an ad-hoc regex that " \
                    "re-flags a check the script reports as PASS (e.g. its color-on-color badge check). A " \
                    "regex-derived 'N files affected' count is a HYPOTHESIS, not ground truth: re-derive it with a " \
                    "precise pattern before offering, because it can be almost entirely false positives. Specifically, " \
                    "a Tailwind/theme '\\b' word-boundary also matches the position before a '-bg'/'-fg'/'-border' " \
                    "suffix, so 'bg-theme-<c>\\b.*text-theme-<c>' wrongly flags the CORRECT fg/bg triad " \
                    "('bg-theme-<c>-bg' / 'text-theme-<c>-fg') — anchor with '(?![-a-z])' as that check does.",
          code_types: CODE_TYPES
        )
      end

      # Targeted all-instances class-sweep: when a recurring bug class has been
      # identified (tagged learnings — the same tag query_learnings uses), widen
      # discovery from "the finding that surfaced it" to EVERY pattern match of
      # the class so it is exhausted in one pass instead of resurfacing one
      # instance per round.
      def class_sweep_guidance(class_tag)
        learnings = Ai::CompoundLearning
                    .where(account: account, status: %w[active verified])
                    .with_tag(class_tag)
                    .recent
                    .limit(25)

        success_result(
          mode: "class_sweep",
          class_tag: class_tag,
          known_instances: learnings.map { |l|
            { id: l.id, title: l.title, category: l.category, content: l.content.to_s.truncate(500) }
          },
          guidance: "Class sweep for '#{class_tag}': derive the class's detection pattern from the known " \
                    "instances above (query_learnings with this tag reads the same source), then widen the scan " \
                    "to EVERY pattern match across the whole tree — not just the file that surfaced the class — " \
                    "and exhaust the class in ONE pass. Verify each candidate reproduces on HEAD, then call " \
                    "create_improvement once per instance with a fingerprint embedding the class tag " \
                    "(e.g. '#{class_tag}|<file>|<detail>') so instances dedupe individually and the class's " \
                    "recurrence stays measurable. Approval remains per-offer (bulk-operation rule unchanged); " \
                    "instances under extensions/private/* stay extension-tagged (gate #9).",
          code_types: CODE_TYPES
        )
      end

      def create_improvement(params)
        return success_result(halted: true, reason: "emergency_halt") if halted?

        type = params[:recommendation_type].to_s
        return error_result("recommendation_type must be one of: #{CODE_TYPES.join(', ')}") unless CODE_TYPES.include?(type)
        return error_result("fingerprint is required") if params[:fingerprint].blank?
        return error_result("title is required") if params[:title].blank?

        files = Array(params[:files]).map(&:to_s)
        repo = resolve_repository(params[:repository])
        target_type, target_id = repo ? ["Devops::GitRepository", repo.id] : ["Account", account.id]

        evidence = {
          "title" => params[:title],
          "description" => params[:description],
          "files" => files,
          "fingerprint" => params[:fingerprint].to_s,
          "repository" => repository_label(repo, params[:repository]),
          "extension" => private_extension_for(files), # gate #9: tag, don't globalize
          "verifier_evidence" => params[:verifier_evidence]
        }.compact

        attrs = {
          current_config: {},
          recommended_config: ({ "fix" => params[:fix] }.compact),
          evidence: evidence,
          confidence_score: clamp_confidence(params[:confidence_score])
        }

        # Tier-2(b): dedupe is scoped to the target — the same fingerprint in two
        # different repositories is two distinct offers, not a collision.
        existing = open_offer_for(params[:fingerprint].to_s, target_type: target_type, target_id: target_id)
        if existing
          existing.update!(attrs)
          success_result(recommendation: serialize(existing), deduped: true)
        else
          rec = Ai::ImprovementRecommendation.create!(
            attrs.merge(account: account, recommendation_type: type,
                        target_type: target_type, target_id: target_id, status: "pending")
          )
          success_result(recommendation: serialize(rec), deduped: false)
        end
      end

      def list_improvements(params)
        status = params[:status].presence || "pending"
        scope = Ai::ImprovementRecommendation.where(account: account, recommendation_type: Ai::ImprovementRecommendation::CODE_QUALITY_TYPES)
        scope = scope.where(status: status) if Ai::ImprovementRecommendation::STATUSES.include?(status)
        scope = filter_by_repository(scope, params[:repository]) if params[:repository].present?
        success_result(improvements: scope.recent(50).map { |r| serialize(r) })
      end

      def approve_improvement(params)
        return success_result(halted: true, reason: "emergency_halt") if halted?

        rec = find_recommendation(params[:recommendation_id])
        return error_result("Recommendation not found") unless rec
        return error_result("Recommendation is #{rec.status}, cannot approve") unless %w[pending approved].include?(rec.status)
        unless CODE_TYPES.include?(rec.recommendation_type)
          return error_result(
            "#{rec.recommendation_type} is not a code-quality recommendation — this tool only promotes " \
            "#{CODE_TYPES.join(', ')} offers into dev-improve coding tasks. Approve it via " \
            "POST /api/v1/ai/learning/recommendations/#{rec.id}/apply (Ai::Learning::ImprovementRecommender) instead."
          )
        end

        rec.approve!(user) unless rec.status == "approved"
        result = Ai::DevLoop::ImprovementPromotionService.new(recommendation: rec).call
        loop_record = result.ralph_loop

        response = {
          recommendation_id: rec.id,
          status: rec.status,
          loop: loop_record.name,
          task_key: result.ralph_task.task_key,
          task_created: result.created
        }
        merge_loop_halt_status!(response, loop_record)
        response[:next] = "Drain with: /dev-loop #{loop_record.name}"

        success_result(response)
      end

      def dismiss_improvement(params)
        rec = find_recommendation(params[:recommendation_id])
        return error_result("Recommendation not found") unless rec

        response = nil
        ActiveRecord::Base.transaction do
          rec.dismiss!
          response = { recommendation_id: rec.id, status: rec.status }
          cascade = cascade_dismiss_promoted_task!(rec)
          response.merge!(cascade) if cascade
        end

        success_result(response)
      end

      # Mark the dev-improve task promoted from a recommendation as reverted — the
      # ground-truth signal for the ungameable metric. NOT kill-switch gated: undoing
      # a bad change must work even while AI execution is suspended.
      def revert_improvement(params)
        rec = find_recommendation(params[:recommendation_id])
        return error_result("Recommendation not found") unless rec

        task = promoted_task_for(rec)
        return error_result("No promoted task found for this recommendation") unless task

        task.revert!(reason: params[:reason])
        success_result(recommendation_id: rec.id, task_key: task.task_key, reverted_at: task.reverted_at&.iso8601)
      end

      # Gated opt-in (Tier-2e): flip the dev-improve loop to unattended autonomous
      # push, drained by a capability-matched platform agent. OFF by default — the
      # loop is created manual; an operator must explicitly enable this. Refused
      # while the kill switch is active.
      def enable_autonomy(params)
        return success_result(halted: true, reason: "emergency_halt") if halted?

        loop_record = dev_improve_loop
        return error_result("No dev-improve loop yet — approve an improvement first") unless loop_record

        agent = resolve_agent(params[:agent_id])
        return error_result("Active agent not found for agent_id") unless agent

        cap = params[:max_iterations_per_day].presence&.to_i
        sc = (loop_record.schedule_config || {}).dup
        sc["max_iterations_per_day"] = cap if cap

        loop_record.update!(
          scheduling_mode: "autonomous",
          default_agent_id: agent.id,
          schedule_paused: false,
          schedule_config: sc,
          next_scheduled_at: Time.current
        )
        success_result(loop: loop_record.name, scheduling_mode: "autonomous",
                       default_agent: agent.name, max_iterations_per_day: sc["max_iterations_per_day"])
      end

      # Return the dev-improve loop to operator-driven (pull) execution.
      def disable_autonomy(_params = {})
        loop_record = dev_improve_loop
        return error_result("No dev-improve loop found") unless loop_record

        loop_record.update!(scheduling_mode: "manual", schedule_paused: true, next_scheduled_at: nil)
        success_result(loop: loop_record.name, scheduling_mode: "manual", schedule_paused: true)
      end

      # Improvement scoreboard backing `/improve status`: offer-funnel counts plus
      # the ungameable metric (one source of truth — RalphTask.improvement_scoreboard).
      def scoreboard(_params = {})
        recs = Ai::ImprovementRecommendation.where(
          account: account, recommendation_type: Ai::ImprovementRecommendation::CODE_QUALITY_TYPES
        )
        success_result(
          discovered: recs.pending.count,
          approved: recs.approved.count,
          applied: recs.applied.count,
          dismissed: recs.dismissed.count,
          metric: Ai::RalphTask.improvement_scoreboard(account: account)
        )
      end

      # --- helpers -------------------------------------------------------------

      def halted?
        account.respond_to?(:ai_suspended?) && account.ai_suspended?
      end

      def find_recommendation(id)
        return nil if id.blank?

        Ai::ImprovementRecommendation.find_by(id: id, account: account)
      end

      # IMP-bf2265feec4e: dismissing a RECOMMENDATION that was already approved
      # left its promoted RalphTask `pending`/`blocked` — dev_next_task kept
      # handing it out, exactly backwards from "dismiss an offer so it is never
      # promoted". Cascades onto the task in the SAME transaction as the
      # dismissal: pending/blocked -> skipped, reason recorded. An in_progress
      # (or already-terminal) task is left alone — a dismissal must never yank
      # work out from under a running agent — and the caller is told so
      # explicitly rather than the change silently no-op'ing on that task.
      def cascade_dismiss_promoted_task!(rec)
        task = promoted_task_for(rec)
        return nil unless task

        if task.can_skip?
          task.skip!(reason: "Recommendation #{rec.id} dismissed")
          { promoted_task_key: task.task_key, promoted_task_status: task.status }
        else
          { promoted_task_key: task.task_key, promoted_task_status: task.status,
            note: "task #{task.task_key} is #{task.status} and was left alone" }
        end
      end

      # IMP-957902bf8474: a dev-improve loop that drains its queue goes
      # `completed` (terminal) — halt_reason then refuses every dev_next_task
      # pull forever, and approve_improvement used to create a task there
      # anyway and hand back "Drain with: /dev-loop dev-improve", advice that
      # cannot work. `completed` here is just "the queue ran dry", not an
      # operator decision, so reopen it automatically — non-destructively
      # (RalphLoop#reopen! leaves ralph_iterations and every task's status
      # alone) — so the newly-created task is immediately claimable.
      # `failed`/`cancelled` ARE deliberate/adverse terminal states an operator
      # or the platform put the loop into; approving more work must not
      # silently resurrect those — surface the halt instead (ralph_loop
      # reopen_ralph_loop is the explicit, operator-driven way back).
      def merge_loop_halt_status!(response, loop_record)
        if loop_record.status == "completed"
          loop_record.reopen!
          response[:loop_reopened] = true
        end

        reason = loop_record.halt_reason
        return unless reason

        response[:warning] = "#{loop_record.name} is halted (#{reason}) — the task was created but dev_next_task " \
                             "will refuse to pull it until the loop is un-halted (see ralph_loop " \
                             "reopen_ralph_loop / resume_ralph_loop / update_ralph_loop)."
        response[:halt_reason] = reason
      end

      def promoted_task_for(rec)
        Ai::RalphTask.joins(:ralph_loop)
                     .where(ai_ralph_loops: { account_id: account.id })
                     .where("ai_ralph_tasks.metadata->>'recommendation_id' = ?", rec.id)
                     .order(created_at: :desc)
                     .first
      end

      def dev_improve_loop
        account.ai_ralph_loops.find_by(name: Ai::DevLoop::ImprovementPromotionService::LOOP_NAME)
      end

      def resolve_agent(agent_id)
        return nil if agent_id.blank?

        scope = account.ai_agents.where(status: "active")
        agent = (scope.find_by(id: agent_id) if agent_id.to_s.match?(UUID_RE))
        agent || scope.find_by(slug: agent_id) || scope.find_by(name: agent_id)
      end

      def open_offer_for(fingerprint, target_type:, target_id:)
        Ai::ImprovementRecommendation
          .where(account: account, status: "pending", target_type: target_type, target_id: target_id)
          .where("evidence->>'fingerprint' = ?", fingerprint)
          .first
      end

      UUID_RE = /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i

      # Resolve a repository identifier (id | full_name | name) to a GitRepository
      # in this account so findings target the repo first-class via the polymorphic
      # target. Returns nil when the identifier doesn't resolve (caller falls back
      # to an Account target + evidence tag).
      def resolve_repository(identifier)
        identifier = identifier.to_s
        return nil if identifier.blank?

        repos = Devops::GitRepository.where(account_id: account.id)
        if identifier.match?(UUID_RE)
          found = repos.find_by(id: identifier)
          return found if found
        end
        repos.find_by(full_name: identifier) || repos.find_by(name: identifier)
      rescue StandardError => e
        Rails.logger.warn("[ImprovementTool] repository resolve failed: #{e.message}")
        nil
      end

      # Human-readable label persisted in evidence for display + legacy filtering.
      def repository_label(repo, raw)
        repo&.full_name.presence || raw.presence
      end

      # Match both new target-scoped records and legacy evidence-tagged records.
      def filter_by_repository(scope, identifier)
        repo = resolve_repository(identifier)
        label = repository_label(repo, identifier)
        if repo
          scope.where(
            "(target_type = ? AND target_id = ?) OR evidence->>'repository' = ?",
            "Devops::GitRepository", repo.id, label
          )
        else
          scope.where("evidence->>'repository' = ?", label)
        end
      end

      def private_extension_for(files)
        files.each do |f|
          m = f.match(%r{extensions/private/([^/]+)/})
          return m[1] if m
        end
        nil
      end

      def clamp_confidence(value)
        (value.presence || 0.6).to_f.clamp(0.0, 1.0)
      end

      def serialize(rec)
        evidence = rec.evidence.is_a?(Hash) ? rec.evidence : {}
        {
          id: rec.id,
          type: rec.recommendation_type,
          status: rec.status,
          # to_f, not the raw attribute: confidence_score is decimal(5,4), so
          # ActiveRecord hands back a BigDecimal and BigDecimal#to_json emits a
          # STRING ("0.87"). This tool declares confidence_score as
          # `type: "number"` on the way IN and the model validates it
          # numerically, so returning a quoted string made the schema lie to
          # every consumer — and a confidence exists to be compared and sorted
          # on. Serialized by both list_improvements and create_improvement,
          # so the coercion belongs here rather than at either call site.
          # (IMP-f83c0139529c)
          confidence: rec.confidence_score&.to_f,
          title: evidence["title"],
          files: evidence["files"],
          repository: evidence["repository"],
          repository_id: (rec.target_id if rec.target_type == "Devops::GitRepository"),
          target_type: rec.target_type,
          extension: evidence["extension"],
          fingerprint: evidence["fingerprint"],
          created_at: rec.created_at
        }
      end
    end
  end
end
