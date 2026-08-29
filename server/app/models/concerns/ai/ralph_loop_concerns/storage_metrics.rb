# frozen_string_literal: true

module Ai
  module RalphLoopConcerns
    # IMP-4bc71cfb2d2c — MEASURE the loop's durable store, and COMPARE it to a bound.
    #
    # WHY THIS EXISTS. `ai_ralph_loops.learnings` grew to 548 kB across 354 entries
    # and was rewritten IN FULL on every task completion — an O(n) read-modify-write
    # that reached ~1.5 GB of cumulative write traffic at the loop's 1000-iteration
    # ceiling. NOTHING REPORTED IT. There was no size field on any summary surface,
    # no cap, and no alert; it was found by reading code. The four increments that
    # fixed the growth (43e6394b8, 398f65780, 54aed757f, ca29bb58a) all fixed the
    # MECHANISM. This one closes the blind spot that let the mechanism run unseen.
    #
    # A METRIC WITH NO THRESHOLD COMPARISON REPRODUCES THE ORIGINAL SILENCE. That is
    # why #storage_limit_bytes and #storage_limit_exceeded? are not optional extras:
    # a number an operator has to eyeball against a remembered budget is the same
    # non-signal as no number at all.
    #
    # WHY ONE AGGREGATE QUERY. The defect being reported on is an O(n) read. A
    # reporter that walks iteration rows to weigh them would reintroduce exactly
    # that cost on every list render. So the measurement is a single grouped
    # aggregate in the database — pg_column_size reads the stored (compressed, and
    # for TOASTed values un-fetched) width, so no ai_output body is ever loaded into
    # Ruby. ::preload_storage_metrics does N loops in that one query; the
    # single-loop path is the same statement with one id.
    #
    # WHY ai_output AND ai_prompt ARE REPORTED SEPARATELY. `ai_prompt` measures
    # 0 bytes across all 493 production rows, which reads exactly like a dead column
    # — it is NOT. Its sole writer is the in-platform
    # Ai::Ralph::ExecutionService::IterationExecution; every production row was
    # written by the MCP dev_loop bridge instead, which never populates it.
    # `ai_output` is written on BOTH paths and is the larger consumer. Averaging the
    # two into one number hides that driver asymmetry and invites a wrong
    # "unused, drop it" conclusion. Keep them apart.
    #
    # The dormant loop-level `learnings` column is measured too. It is deliberately
    # NOT dropped (see TaskAndLearning#add_learning), so it stays empty by
    # convention only — this number is what would notice a regression re-growing it.
    module StorageMetrics
      extend ActiveSupport::Concern

      # Per-loop override, read from the loop's `configuration` jsonb. Tunable
      # without a migration, per loop, exactly like max_tokens / max_cost /
      # max_wall_clock_seconds already are.
      STORAGE_LIMIT_CONFIG_KEY = "max_storage_bytes"

      # Platform-wide default, DB-driven so an operator can retune the whole fleet
      # without a deploy (same resolution order as Ai::Agent#skill_prompt_token_budget).
      STORAGE_LIMIT_SETTING = "ralph_loop_max_storage_bytes"

      # DOCUMENTED DEFAULT: 64 MiB. Sized off the observed production shape — a
      # 493-iteration loop carries ~1.4 MB of ai_output, so a loop run to its 1000-
      # iteration ceiling lands near 3 MB. 64 MiB is therefore ~20x headroom over a
      # full healthy run: it will not fire on normal operation, and a loop that
      # reaches it is storing something categorically unlike iteration output.
      # This constant is the LAST resort — configuration wins, then SiteSetting.
      DEFAULT_STORAGE_LIMIT_BYTES = 64 * 1024 * 1024

      # Resolved 0 ⇒ NO CAP, matching max_wall_clock_seconds / max_tokens / max_cost.
      NO_CAP = 0

      EMPTY_METRICS = {
        iteration_count: 0,
        learning_iteration_count: 0,
        ai_output_bytes: 0,
        ai_prompt_bytes: 0,
        learnings_column_bytes: 0
      }.freeze

      # GROUP BY l.id alone is legal here: id is the primary key, so PostgreSQL's
      # functional-dependency rule lets pg_column_size(l.learnings) sit in the
      # select list ungrouped. Grouping by the jsonb column itself would work but
      # would make the planner hash every learnings value.
      #
      # LEFT JOIN, not INNER: a loop with zero iterations must report zeros, not
      # vanish from the result and silently fall back to the empty default.
      #
      # COALESCE on the SUMs: SUM over no rows is NULL, and pg_column_size(NULL) is
      # NULL, so an all-NULL column sums to NULL rather than 0.
      METRICS_SQL = <<~SQL.squish
        SELECT l.id AS loop_id,
               COUNT(i.id) AS iteration_count,
               COUNT(i.id) FILTER (
                 WHERE i.learning_extracted IS NOT NULL AND i.learning_extracted <> ''
               ) AS learning_iteration_count,
               COALESCE(SUM(pg_column_size(i.ai_output)), 0) AS ai_output_bytes,
               COALESCE(SUM(pg_column_size(i.ai_prompt)), 0) AS ai_prompt_bytes,
               COALESCE(pg_column_size(l.learnings), 0) AS learnings_column_bytes
        FROM ai_ralph_loops l
        LEFT JOIN ai_ralph_iterations i ON i.ralph_loop_id = l.id
        WHERE l.id IN (:ids)
        GROUP BY l.id
      SQL

      class_methods do
        # Batch entry point: ONE aggregate query for N loops, memoised onto each
        # record. Every list surface that renders #loop_summary must call this
        # first, or the per-loop fallback turns the list into an N+1.
        #
        # Returns the loops so it can be chained at a call site.
        def preload_storage_metrics(loops)
          records = Array(loops)
          return records if records.empty?

          rows = storage_metrics_rows(records.map(&:id))
          records.each { |record| record.assign_preloaded_storage_metrics(rows[record.id] || EMPTY_METRICS) }
          records
        end

        # id => metrics hash. Public so both the batch and the single-loop path
        # share one statement — there is only one way to measure this.
        def storage_metrics_rows(ids)
          ids = Array(ids).compact.uniq
          return {} if ids.empty?

          sql = sanitize_sql_array([ METRICS_SQL, { ids: ids } ])
          connection.select_all(sql, "RalphLoop Storage Metrics").each_with_object({}) do |row, acc|
            acc[row["loop_id"]] = {
              iteration_count: row["iteration_count"].to_i,
              learning_iteration_count: row["learning_iteration_count"].to_i,
              ai_output_bytes: row["ai_output_bytes"].to_i,
              ai_prompt_bytes: row["ai_prompt_bytes"].to_i,
              learnings_column_bytes: row["learnings_column_bytes"].to_i
            }
          end
        end
      end

      def assign_preloaded_storage_metrics(metrics)
        @storage_metrics = metrics
      end

      # #reload means "re-read this row from the database"; a caller that reloads
      # and then renders #loop_summary (ExecutionService does exactly that) must
      # not be handed a measurement taken before the iterations it just wrote.
      # ActiveRecord::Base#reload does not clear plain ivars, so drop it here.
      def reload(*)
        @storage_metrics = nil
        @storage_limit_bytes = nil
        super
      end

      # Counts and byte sizes for this loop's durable stores. Memoised: the value
      # is a point-in-time measurement, and a summary render must not re-query it.
      def storage_metrics
        @storage_metrics ||= self.class.storage_metrics_rows([ id ])[id] || EMPTY_METRICS
      end

      # The measured stores summed. This is what the bound compares against; the
      # components stay individually visible in #storage_summary so the number is
      # never the only thing an operator sees.
      def storage_total_bytes
        m = storage_metrics
        m[:ai_output_bytes] + m[:ai_prompt_bytes] + m[:learnings_column_bytes]
      end

      # configuration override -> SiteSetting global -> documented DEFAULT.
      # An explicit 0 (or negative) ⇒ no cap, matching max_tokens / max_cost.
      #
      # MEMOISED. #storage_summary asks for the bound three times (limit_bytes,
      # limit_exceeded?, usage_pct) and the SiteSetting leg is a real SELECT — so
      # an unmemoised read would fire three settings queries per loop rendered,
      # which on a list page is exactly the N+1 shape this increment is about.
      def storage_limit_bytes
        return @storage_limit_bytes unless @storage_limit_bytes.nil?

        @storage_limit_bytes = resolve_storage_limit_bytes
      end

      def storage_limit_exceeded?
        limit = storage_limit_bytes
        return false if limit <= NO_CAP

        storage_total_bytes > limit
      end

      # Percentage of the bound consumed; nil when there is no cap (a percentage
      # of "unlimited" is not a number, and rendering 0 there would read as healthy).
      def storage_usage_pct
        limit = storage_limit_bytes
        return nil if limit <= NO_CAP

        (storage_total_bytes.to_f / limit * 100).round(1)
      end

      # The operator-facing payload. Carried on #loop_summary (and therefore
      # #loop_details), and aggregated by RalphLoopTool#get_statistics.
      def storage_summary
        storage_metrics.merge(
          total_bytes: storage_total_bytes,
          limit_bytes: storage_limit_bytes,
          limit_exceeded: storage_limit_exceeded?,
          usage_pct: storage_usage_pct
        )
      end

      private

      def resolve_storage_limit_bytes
        configured = coerce_storage_limit(configuration&.dig(STORAGE_LIMIT_CONFIG_KEY), source: "configuration")
        return configured unless configured.nil?

        global = coerce_storage_limit(SiteSetting.get(STORAGE_LIMIT_SETTING), source: "SiteSetting")
        return global unless global.nil?

        DEFAULT_STORAGE_LIMIT_BYTES
      rescue StandardError => e
        Rails.logger.warn("[RalphLoop] storage bound unreadable (#{e.class}); using the documented default")
        DEFAULT_STORAGE_LIMIT_BYTES
      end

      # A GARBLED BOUND MUST NOT SILENTLY UNCAP THE LOOP. `.to_i` on "abc" is 0,
      # and 0 means "no cap" here — so a typo'd setting would disable the very
      # alarm this increment exists to raise, silently, which is the original
      # defect wearing a different hat. Only a value that actually parses as a
      # number is honoured; anything else is logged and falls through to the next
      # source. SiteSetting.get returns a String unless setting_type is
      # "integer", so the String branch is the common path, not the exotic one.
      #
      # nil means "not configured at this level" — it is NOT the same as 0, which
      # is a deliberate no-cap and returns as an Integer.
      def coerce_storage_limit(value, source:)
        return nil if value.nil?
        return nil if value.is_a?(String) && value.strip.empty?

        parsed =
          case value
          when Integer then value
          when Float   then value.to_i
          when String  then Integer(value, exception: false) || Float(value, exception: false)&.to_i
          end

        if parsed.nil?
          Rails.logger.warn(
            "[RalphLoop] ignoring non-numeric #{source} storage bound; falling back to the documented default"
          )
          return nil
        end

        [ parsed, NO_CAP ].max
      end
    end
  end
end
