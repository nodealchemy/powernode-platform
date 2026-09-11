# frozen_string_literal: true

module Ai
  module Learning
    class EvaluationService
      # Quality (0..1) at or above which the served skill version is credited
      # with a success. The judge scores 1-5, so 0.6 here is an average of 3.4 —
      # deliberately ABOVE the neutral 3, because "no worse than average" is not
      # evidence a version worked. Account#settings override, matching the
      # ai_learning_* thresholds in Ai::Learning::LearningClusterService.
      DEFAULT_SUCCESS_QUALITY_THRESHOLD = 0.6
      SUCCESS_QUALITY_THRESHOLD_SETTING = "ai_evaluation_success_quality_threshold"

      # D5 — the judge's on/off switch and its spend ceiling: two SiteSettings,
      # both rendered on the admin Autonomy tab. They replace the
      # :agent_evaluation Flipper flag, which no UI and no API could flip.
      #
      # ai.evaluation.enabled DEFAULTS TO ON. An absent row means ON: seeds do
      # not re-run after first boot, so an established deployment has no row
      # until an operator writes one (the seed guards with unless-exists). Only
      # an explicit "true"/"false" is a value; anything else fails CLOSED and is
      # logged, so a typo can never silently turn the spending on.
      #
      # ai.evaluation.daily_cap is the same shape as platform.investigation.
      # daily_cap: per account, rolling day, positive?-guarded so a zero or
      # unparseable value falls back to the default instead of meaning
      # "unlimited" or "never". Turning the judge OFF is the switch's job.
      # It counts judge ATTEMPTS (Ai::EvaluationAttempt), degraded ones
      # included, because every attempt is a paid call (D5 review F-D5-1).
      ENABLED_SETTING = "ai.evaluation.enabled"
      DAILY_CAP_SETTING = "ai.evaluation.daily_cap"
      DEFAULT_DAILY_CAP = 20
      REFUSED_DAILY_CAP = "DailyCapReached"
      # The attempt ledger could not be written, so the judge was not called.
      # Same reason string as the A6 investigation ledger.
      REFUSED_LEDGER_UNAVAILABLE = "LedgerUnavailable"
      # Another request for the same (execution, task) holds the attempt and
      # is making the one paid call; this one makes none.
      REFUSED_IN_FLIGHT = "EvaluationInFlight"

      def self.enabled?
        raw = ::SiteSetting.get(ENABLED_SETTING)
        return true if raw.nil?

        case raw.to_s.strip.downcase
        when "true" then true
        when "false" then false
        else
          Rails.logger.warn("[EvaluationService] #{ENABLED_SETTING}=#{raw.inspect} is not true/false; treating it as OFF")
          false
        end
      end

      def self.daily_cap
        configured = ::SiteSetting.get(DAILY_CAP_SETTING)
        configured.present? && configured.to_i.positive? ? configured.to_i : DEFAULT_DAILY_CAP
      end

      def initialize(account:)
        @account = account
      end

      # Runs the judge SYNCHRONOUSLY in the caller's thread. The caller is the
      # worker's request (AgentEvaluationJob -> POST
      # /api/v1/internal/ai/evaluations/run), which is what a background job is
      # for. The previous implementation did the work in a bare Thread.new
      # inside a Puma request: nothing awaited it, an exception only reached a
      # log line, and a request that finished first took the thread's database
      # connection with it. It also had zero production callers, so the whole
      # judge subsystem was unreachable.
      #
      # Three statuses, always explicit — this method never returns nil:
      #   not_measured + reason  — nothing was judged, and the reason says why
      #   evaluated              — a row exists and carries the scores
      # An UNAVAILABLE judge is not_measured, never evaluated: LlmJudgeService
      # returns neutral 3/3/3/5 defaults flagged `degraded` when it cannot get a
      # verdict, and persisting those would be indistinguishable from a real
      # mediocre evaluation in trust, in skill effectiveness and in the trend
      # charts.
      def evaluate_execution(execution:, output: nil, context: {}, task_id: nil)
        return not_measured("EvaluationDisabled") unless self.class.enabled?

        # The kill switch reaches the judge too. Evaluating spends an LLM call
        # against this account, so an emergency_halt that stopped every other
        # AI cadence but left the judge running would be a hole in it — the
        # closure driver refuses on the same check.
        return not_measured("AiSuspended") if @account.respond_to?(:ai_suspended?) && @account.ai_suspended?

        agent = execution.respond_to?(:agent) ? execution.agent : nil
        return not_measured("NoEvaluableExecution") unless execution && agent
        # D4 review F2 — tenancy here as well as at the door: another account's
        # execution is never judged under this one. Same reason as a missing
        # row, so this answer discloses nothing about rows it will not serve.
        return not_measured("NoEvaluableExecution") unless execution.try(:account_id) == @account.id

        transcript = output.presence || default_transcript(execution)
        return not_measured("NoEvaluableExecution") if transcript.blank?

        # Idempotency, before the judge runs: a retried worker job must not pay
        # for a second LLM call, and must not move trust or a skill version a
        # second time.
        if (existing = find_existing(execution, task_id))
          return evaluated(existing, idempotent: true)
        end

        # ONE PAID CALL PER (execution, task) (F-D5-1 dedupe). A degraded
        # verdict writes no result row, so the check above cannot see its
        # retry, and the worker's Sidekiq retry after a 408 paid the judge
        # again. The first attempt answers instead: its outcome, or
        # EvaluationInFlight while it is still running. Before the cap, so a
        # retry at the cap still gets its own answer.
        if (prior = find_attempt(execution, task_id))
          return answer_for_attempt(prior, execution, task_id)
        end

        # After idempotency, so a retry of a completion already judged still
        # gets its answer at the cap; before the judge, so the cap is a ceiling
        # on spend and not a report of it.
        return not_measured(REFUSED_DAILY_CAP) if daily_cap_reached?

        # NO LEDGER ROW, NO CALL (D5 review F-D5-1). The cap counts attempts,
        # so an attempt that cannot be recorded must not be made: it would be
        # a paid call the cap never sees. A request that loses the insert to a
        # concurrent one for the same (execution, task) gets that one's answer.
        attempt, refusal = open_attempt(execution, task_id)
        return refusal if refusal

        judge = Ai::Learning::LlmJudgeService.new(account: @account)
        verdict = judge.evaluate(
          agent_output: transcript,
          task_description: context[:task_description] || execution.input_parameters&.dig("prompt"),
          expected_output: context[:expected_output]
        )
        # D4 review F1 — degraded carries its cause (JudgeUnavailable,
        # JudgeUnparseable, JudgeDimensionMissing, JudgeDimensionNotNumeric).
        # None of them persists a row, moves trust or touches a skill version.
        # The ATTEMPT stays: the call was made, and the cap counts it.
        if verdict[:degraded]
          reason = verdict[:degraded_reason].presence || "JudgeUnavailable"
          close_attempt(attempt, "not_measured", reason)
          return not_measured(reason, detail: verdict[:degraded_detail])
        end

        result = persist_evaluation(execution, agent, task_id, judge, verdict)
        close_attempt(attempt, "evaluated")
        return evaluated(result, idempotent: true) if result[:already_existed]

        record = result[:record]
        quality = quality_from(record)
        record_trust_quality(execution, agent, quality)

        evaluated(record).merge(skill_outcome: record_skill_outcome(execution, quality))
      rescue StandardError => e
        Rails.logger.error("[EvaluationService] evaluation failed: #{e.class}: #{e.message}")
        # An attempt opened before the failure keeps counting: the call may
        # already have been paid for.
        close_attempt(attempt, "not_measured", "EvaluationError") if attempt&.outcome == "pending"
        not_measured("EvaluationError", detail: e.message)
      end

      def agent_score_trends(agent_id, period: 30.days)
        results = Ai::EvaluationResult.for_agent(agent_id)
                                       .in_time_range(period.ago)
                                       .order(:created_at)

        return {} if results.empty?

        {
          count: results.count,
          average_correctness: average_dimension(results, "correctness"),
          average_completeness: average_dimension(results, "completeness"),
          average_helpfulness: average_dimension(results, "helpfulness"),
          average_safety: average_dimension(results, "safety"),
          trend: calculate_trend(results)
        }
      end

      # Aggregate evaluation scores per skill node for an agent.
      #
      # ai_evaluation_results has no jsonb column suited to structured
      # attribution (only `scores`, which holds the four dimension numbers,
      # and `feedback`, which is free text) and `execution_id` carries no DB
      # foreign key, so it isn't locked to one execution model. In the
      # post_execution_extract flow, EvaluationResult#execution_id and
      # CompoundLearning#source_execution_id are populated from the same
      # team-execution id (see AutoExtractorService#extract_from_evaluations
      # and CompoundLearningService#store_learning), so attribution is
      # resolved by joining through that shared id rather than adding a
      # migration.
      def skill_performance_breakdown(agent_id:, period: 30.days)
        results = Ai::EvaluationResult.for_agent(agent_id)
                                       .in_time_range(period.ago)
                                       .to_a

        skill_ids_by_execution = skill_node_ids_by_execution(results.map(&:execution_id).compact.uniq)

        breakdown = {}

        results.each do |result|
          skill_ids = skill_ids_by_execution[result.execution_id] || legacy_feedback_skill_ids(result.feedback)
          next if skill_ids.blank?

          avg = result.average_score
          next unless avg

          skill_ids.uniq.each do |skill_id|
            breakdown[skill_id] ||= { scores: [], count: 0 }
            breakdown[skill_id][:scores] << avg
            breakdown[skill_id][:count] += 1
          end
        end

        breakdown.transform_values do |data|
          {
            average_score: (data[:scores].sum / data[:scores].size).round(2),
            evaluation_count: data[:count],
            min_score: data[:scores].min&.round(2),
            max_score: data[:scores].max&.round(2)
          }
        end
      rescue => e
        Rails.logger.warn "[EvaluationService] Skill performance breakdown failed: #{e.message}"
        {}
      end

      private

      # ==================================================
      # D4 — evaluation arms, idempotency, trust, skill credit
      # ==================================================

      def not_measured(reason, detail: nil)
        { status: "not_measured", reason: reason }.tap { |h| h[:detail] = detail if detail.present? }
      end

      def evaluated(record, idempotent: false)
        {
          status: "evaluated",
          evaluation_id: record.id,
          execution_id: record.execution_id,
          task_id: record.task_id,
          scores: record.scores,
          quality: quality_from(record),
          idempotent: idempotent
        }
      end

      def find_existing(execution, task_id)
        # Account-scoped (D4 review F2): an idempotent hit must never hand back
        # another account's row.
        Ai::EvaluationResult.find_by(account_id: @account.id, execution_id: execution.id, task_id: task_id)
      end

      # The unique index (execution_id, task_id) NULLS NOT DISTINCT is the real
      # guard; the find_by above only avoids paying an LLM call in the common
      # case. Two workers racing the same completion both reach here, and the
      # loser must return the winner's row rather than raise.
      def persist_evaluation(execution, agent, task_id, judge, verdict)
        record = Ai::EvaluationResult.create!(
          account: @account,
          agent: agent,
          execution_id: execution.id,
          task_id: task_id,
          # Derived from the evaluator agent at call time — no hardcoded model
          # id. A sentinel rather than nil so the presence validation cannot
          # silently drop a result whose evaluator could not be resolved.
          evaluator_model: judge.evaluator_model || "unresolved",
          scores: verdict[:scores],
          feedback: verdict[:feedback]
        )
        { record: record, already_existed: false }
      rescue ActiveRecord::RecordNotUnique
        existing = find_existing(execution, task_id)
        raise if existing.nil?

        Rails.logger.info(
          "[EvaluationService] concurrent evaluation for execution #{execution.id} " \
          "task #{task_id.inspect}; keeping #{existing.id}"
        )
        { record: existing, already_existed: true }
      end

      # 1-5 average onto the 0..1 scale the trust dimension uses.
      def quality_from(record)
        average = record.average_score
        return nil unless average

        ((average.to_f - 1.0) / 4.0).clamp(0.0, 1.0).round(4)
      end

      # There is no record_quality! on Ai::AgentTrustScore — the quality column
      # is written by Ai::Autonomy::TrustEngineService, which reads
      # performance_metrics["quality_score"] (0..1) as the highest-precedence
      # signal in #calculate_quality. So the judge's verdict is written there
      # and the engine is invoked directly: the model's own after_update hook
      # only fires on a STATUS change, and an execution being evaluated is
      # already terminal.
      def record_trust_quality(execution, agent, quality)
        return if quality.nil?
        return unless execution.respond_to?(:performance_metrics)

        metrics = (execution.performance_metrics || {}).merge("quality_score" => quality)
        execution.update_columns(performance_metrics: metrics)
        Ai::Autonomy::TrustEngineService.new(account: @account).evaluate(agent: agent, execution: execution)
      rescue StandardError => e
        Rails.logger.error("[EvaluationService] trust quality write failed: #{e.class}: #{e.message}")
      end

      # Credits every skill VERSION that served the execution. The serving
      # paths stamp them (Ai::SkillVersion.record_served!, D5). An agent serves
      # several skills in one prompt, and one verdict on the run is the only
      # evidence about each of them, so each is credited. The ids are re-scoped
      # to this account before anything is written — the key is data on a row,
      # not authority.
      def record_skill_outcome(execution, quality)
        # D4 review F6 — one code per cause: a nil quality means the row carried
        # no scores, which is not the same fact as "no version served".
        return not_measured("UnscoredEvaluation") if quality.nil?

        stamped = Array(execution.try(:execution_context)&.dig(Ai::SkillVersion::SERVED_CONTEXT_KEY))
        versions = stamped.empty? ? [] : Ai::SkillVersion.where(id: stamped, account_id: @account.id).to_a
        return not_measured("NoServedVersion") if versions.empty?

        successful = quality >= success_quality_threshold
        versions.each { |version| version.record_outcome!(successful: successful) }
        { status: "recorded", skill_version_ids: versions.map(&:id), successful: successful }
      rescue StandardError => e
        Rails.logger.error("[EvaluationService] skill outcome failed: #{e.class}: #{e.message}")
        not_measured("SkillOutcomeError", detail: e.message)
      end

      # Counts ATTEMPTS, not result rows (D5 review F-D5-1): a degraded verdict
      # is a paid call that writes no result row, so counting results let five
      # degraded calls through a cap of 1.
      def daily_cap_reached?
        Ai::EvaluationAttempt.where(account_id: @account.id)
                             .since(1.day.ago)
                             .count >= self.class.daily_cap
      end

      # Written before the judge is called. Returns [attempt, nil] when the
      # call may go ahead, or [nil, answer] when it may not. NO ROW, NO CALL.
      def open_attempt(execution, task_id)
        attempt = Ai::EvaluationAttempt.create!(account: @account, execution_id: execution.id,
                                                task_id: task_id, outcome: "pending")
        [ attempt, nil ]
      rescue ActiveRecord::RecordNotUnique
        # A concurrent request for the same (execution, task) won the insert,
        # and it makes the call. The unique index is the real guard; the
        # find_attempt check in evaluate_execution only answers early.
        [ nil, answer_for_attempt(find_attempt(execution, task_id), execution, task_id) ]
      rescue StandardError => e
        Rails.logger.error("[EvaluationService] attempt ledger write failed: #{e.class}: #{e.message}")
        [ nil, not_measured(REFUSED_LEDGER_UNAVAILABLE) ]
      end

      # The same key as the unique index (execution_id, task_id) NULLS NOT
      # DISTINCT, so the early check and the constraint guard the same thing.
      def find_attempt(execution, task_id)
        Ai::EvaluationAttempt.find_by(execution_id: execution.id, task_id: task_id)
      end

      # What a second request for an already-attempted (execution, task) gets:
      # the first attempt's outcome, never a second paid call.
      def answer_for_attempt(prior, execution, task_id)
        case prior&.outcome
        when "evaluated"
          existing = find_existing(execution, task_id)
          existing ? evaluated(existing, idempotent: true) : not_measured(REFUSED_IN_FLIGHT)
        when "not_measured"
          not_measured(prior.reason.presence || "EvaluationError", detail: "already attempted; not judged again")
        else
          not_measured(REFUSED_IN_FLIGHT)
        end
      end

      # Closing only records what the call produced. A close that fails leaves
      # the row pending, and a pending row still counts toward the cap.
      def close_attempt(attempt, outcome, reason = nil)
        return unless attempt

        attempt.update_columns(outcome: outcome, reason: reason, updated_at: Time.current)
      rescue StandardError => e
        Rails.logger.error("[EvaluationService] attempt #{attempt.id} close failed: #{e.class}: #{e.message}")
      end

      def success_quality_threshold
        configured = setting(SUCCESS_QUALITY_THRESHOLD_SETTING)
        (configured.presence || DEFAULT_SUCCESS_QUALITY_THRESHOLD).to_f.clamp(0.0, 1.0)
      end

      # Account#settings -> constant, the convention this service family uses
      # (Ai::Learning::LearningClusterService, Ai::Learning::CompoundLearningService).
      def setting(key)
        s = @account&.settings
        return nil unless s.is_a?(Hash)

        s[key] || s[key.to_sym]
      end

      # What the judge reads when the caller passed no explicit output. The
      # worker sends ids only, so the transcript is resolved here rather than
      # round-tripping an execution's output through the job payload.
      def default_transcript(execution)
        output = execution.try(:output_data)
        return nil if output.blank?

        output.is_a?(String) ? output : output.to_json
      end

      def skill_node_ids_by_execution(execution_ids)
        return {} if execution_ids.blank?

        Ai::CompoundLearning
          .for_account(@account.id)
          .where(source_execution_id: execution_ids)
          .each_with_object({}) do |learning, memo|
            ids = Array(learning.metadata&.dig("skill_node_ids"))
            next if ids.blank?

            (memo[learning.source_execution_id] ||= []).concat(ids)
          end
      end

      # Legacy fallback only: historical writers may have serialized
      # structured feedback as a JSON string before attribution existed.
      # Plain free-text feedback (the normal case) must not raise or be
      # treated as an error.
      def legacy_feedback_skill_ids(feedback)
        return [] if feedback.blank?

        parsed = JSON.parse(feedback)
        return [] unless parsed.is_a?(Hash)

        Array(parsed["skill_node_ids"] || parsed.dig("metadata", "skill_node_ids"))
      rescue JSON::ParserError, TypeError
        []
      end

      def average_dimension(results, dimension)
        values = results.filter_map { |r| r.scores&.dig(dimension) }
        return nil if values.empty?

        (values.sum.to_f / values.size).round(2)
      end

      def calculate_trend(results)
        return "stable" if results.count < 5

        recent = results.last(5).filter_map(&:average_score)
        older = results.first(5).filter_map(&:average_score)

        return "stable" if recent.empty? || older.empty?

        recent_avg = recent.sum / recent.size
        older_avg = older.sum / older.size

        if recent_avg > older_avg + 0.3
          "improving"
        elsif recent_avg < older_avg - 0.3
          "declining"
        else
          "stable"
        end
      end
    end
  end
end
