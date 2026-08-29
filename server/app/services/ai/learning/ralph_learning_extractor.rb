# frozen_string_literal: true

module Ai
  module Learning
    # Tier-2(c): promotes ralph-loop iteration learnings (IMP-7f415874c14a: the
    # entries RalphLoop#learning_entries derives from ai_ralph_iterations — this
    # read used to index the now-retired ralph_loop.learnings jsonb column) into
    # durable CompoundLearning records so
    # effective_importance / decay can measure them over time. This wires up the
    # gap recon identified: loop learnings were appended to JSON but never reached
    # the compounding-learning store.
    #
    # Reuses CompoundLearningService#store_learning for embedding generation and
    # near-duplicate dedup (so re-harvesting is idempotent), and scopes each to the
    # loop's git_repository when resolvable (Tier-2(d) FK).
    #
    # Inc7 (learning feed-forward): loop learnings used to land as write-only rows —
    # null title, a blanket 0.3 importance, and a lone "ralph_loop" tag — so nothing
    # could rank or retrieve them (see the null-title/0.3 signature in query_learnings).
    # The seam now DERIVES a bounded title, class/topic tags (workload, campaign,
    # task-key domain, changed-file subsystem, plus explicit caller tags), and a
    # category-calibrated importance from the learning text + loop/campaign context,
    # so loop learnings become consumable. Explicit caller-supplied category /
    # importance / tags always override the derived values.
    class RalphLearningExtractor
      INITIAL_CONFIDENCE = 0.5
      TITLE_MAX = 120
      MAX_TAGS = 10

      # Calibrated importance floor by category — durable-rule categories seed a bit
      # higher than raw discoveries, but all stay modest so learnings still earn their
      # ranking through reuse outcomes (effective_importance). Campaign/operator-directed
      # loops add CAMPAIGN_BOOST. Documented heuristic — not a blanket 0.3.
      BASE_IMPORTANCE = {
        "best_practice" => 0.5,
        "pattern" => 0.45,
        "anti_pattern" => 0.45,
        "failure_mode" => 0.45,
        "performance_insight" => 0.4,
        "review_finding" => 0.4,
        "reflexion" => 0.35,
        "discovery" => 0.35,
        "fact" => 0.3
      }.freeze
      DEFAULT_IMPORTANCE = 0.35
      CAMPAIGN_BOOST = 0.15
      IMPORTANCE_MIN = 0.1
      IMPORTANCE_MAX = 0.75

      # Leading marker words the loop prompt instructs executors to emit ("Mark
      # discoveries with `Discovery:`, patterns with `Pattern:` ..."). When present
      # they drive the category (hence importance) and are stripped from the title.
      MARKER_CATEGORY = {
        "discovery" => "discovery",
        "pattern" => "pattern",
        "anti-pattern" => "anti_pattern",
        "antipattern" => "anti_pattern",
        "best practice" => "best_practice",
        "failure" => "failure_mode",
        "failure mode" => "failure_mode",
        "performance" => "performance_insight"
      }.freeze

      def initialize(account:)
        @account = account
        @service = Ai::Learning::CompoundLearningService.new(account: account)
      end

      # Harvest all of a loop's accumulated learnings. Idempotent. Returns the
      # number of new CompoundLearning records created.
      #
      # IMP-7f415874c14a: the source is the loop's DERIVED learning entries
      # (ai_ralph_iterations), not the retired `learnings` jsonb column. `entries:`
      # is how RalphLoop#extract_compound_learnings supplies its own list — the
      # derived entries UNIONED with anything still stranded in the dormant column
      # (a loop reset before this change). Re-deriving here would drop that union.
      def extract(ralph_loop, entries: nil)
        entries = ralph_loop.learning_entries if entries.nil?
        repo_id = repository_id_for(ralph_loop)
        Array(entries).sum do |entry|
          store(entry_text(entry), repo_id: repo_id, loop: ralph_loop, context: entry_context(entry)) ? 1 : 0
        end
      rescue StandardError => e
        Rails.logger.warn("[RalphLearningExtractor] extract failed for loop #{ralph_loop&.id}: #{e.message}")
        0
      end

      # Harvest a single learning string (per-iteration callers). `context` may carry
      # :task_key, :files, :category, :importance, and explicit :tags. Returns true
      # when a new record was created.
      def extract_learning(ralph_loop, text, context: {})
        store(text, repo_id: repository_id_for(ralph_loop), loop: ralph_loop, context: context || {})
      rescue StandardError => e
        Rails.logger.warn("[RalphLearningExtractor] extract_learning failed: #{e.message}")
        false
      end

      private

      def store(text, repo_id:, loop:, context:)
        return false if text.blank?

        category = derive_category(text, context)
        # store_learning takes a positional Hash (not kwargs) — pass it explicitly.
        @service.store_learning({
          title: derive_title(text),
          content: text,
          category: category,
          importance: derive_importance(category: category, loop: loop, context: context),
          confidence: INITIAL_CONFIDENCE,
          extraction_method: "ralph_loop",
          git_repository_id: repo_id,
          tags: derive_tags(loop: loop, context: context)
        })
      end

      # ---- Derivation -------------------------------------------------------

      # First sentence/clause, marker-stripped, bounded. NEVER blank when the
      # learning text is present — the regression guard that the old write-only
      # null-title shape can no longer be produced through this seam.
      def derive_title(text)
        body = strip_marker(text.to_s.strip)
        first = body[/\A.*?[.!?](?=\s|\z)/] || body[/\A[^;\n]+/] || body
        first = first.to_s.strip.sub(/[.;,:\s]+\z/, "")
        first = body.strip if first.blank?
        first.length > TITLE_MAX ? "#{first[0, TITLE_MAX - 1].rstrip}…" : first
      end

      def derive_category(text, context)
        explicit = context[:category].to_s
        return explicit if Ai::CompoundLearning::CATEGORIES.include?(explicit)

        marker = text.to_s.strip[/\A([A-Za-z][A-Za-z -]*?):/, 1]
        MARKER_CATEGORY[marker.to_s.strip.downcase] || "discovery"
      end

      def derive_importance(category:, loop:, context:)
        override = context[:importance]
        return override.to_f.clamp(0.0, 1.0) if override

        base = BASE_IMPORTANCE.fetch(category, DEFAULT_IMPORTANCE)
        base += CAMPAIGN_BOOST if campaign_directed?(loop, context)
        base.clamp(IMPORTANCE_MIN, IMPORTANCE_MAX).round(4)
      end

      # Explicit caller tags rank first so they survive the MAX_TAGS cap, then the
      # highest-signal derived tags (campaign, task domain), then workload/name/subsystem.
      def derive_tags(loop:, context:)
        tags = ["ralph_loop"]
        tags.concat(Array(context[:tags]).map { |t| t.to_s.strip.presence })
        tags << "campaign" if campaign_directed?(loop, context)
        tags << task_domain_tag(context[:task_key])
        tags << loop_workload(loop)
        tags << loop&.name.to_s.parameterize.presence
        tags.concat(subsystem_tags(context[:files]))
        tags.compact.uniq.first(MAX_TAGS)
      end

      def campaign_directed?(loop, context)
        return true if context[:campaign] == true

        loop.respond_to?(:campaign_id) && loop.campaign_id.present?
      end

      def loop_workload(loop)
        wl = loop&.configuration.is_a?(Hash) ? loop.configuration["workload"] : nil
        wl.to_s.parameterize.presence
      end

      # Alpha prefix of the task_key ("IMP-abc" -> "task:imp", "AUDIT-S1" -> "task:audit").
      def task_domain_tag(task_key)
        return nil if task_key.blank?

        domain = task_key.to_s[/\A[A-Za-z]+/]
        domain.present? ? "task:#{domain.downcase}" : nil
      end

      # Coarse subsystem tags from changed file paths (server/frontend/worker/ext plus
      # the ai/ service namespace). Bounded; final dedup happens in derive_tags.
      def subsystem_tags(files)
        Array(files).flat_map { |f| subsystems_for(f.to_s) }.compact.uniq.first(4)
      end

      def subsystems_for(path)
        out = []
        case path
        when %r{\A(?:\./)?server/} then out << "subsystem:server"
        when %r{\A(?:\./)?frontend/} then out << "subsystem:frontend"
        when %r{\A(?:\./)?worker/} then out << "subsystem:worker"
        when %r{\A(?:\./)?extensions/} then out << "subsystem:extensions"
        end
        out << "subsystem:ai" if path.match?(%r{/ai/})
        out
      end

      # Strip a recognized leading marker ("Discovery: ...") only; leave non-marker
      # colons (e.g. "N+1: ...") intact.
      def strip_marker(text)
        marker = text[/\A([A-Za-z][A-Za-z -]*?):\s*/, 1]
        return text if marker.nil? || !MARKER_CATEGORY.key?(marker.strip.downcase)

        text.sub(/\A[A-Za-z][A-Za-z -]*?:\s*/, "")
      end

      def entry_text(entry)
        entry.is_a?(Hash) ? entry["text"] : entry.to_s
      end

      def entry_context(entry)
        ctx = entry.is_a?(Hash) ? entry["context"] : nil
        return {} unless ctx.is_a?(Hash)

        { task_key: ctx["task_key"] || ctx[:task_key], files: ctx["files"] || ctx[:files] }
      end

      # Resolve the loop's repository_url to a GitRepository in this account.
      # Returns nil when there's no URL or no match (learning stays account-global).
      def repository_id_for(ralph_loop)
        url = ralph_loop.respond_to?(:repository_url) ? ralph_loop.repository_url : nil
        return nil if url.blank?

        Devops::GitRepository.where(account_id: @account.id)
                             .where("clone_url = :u OR web_url = :u OR ssh_url = :u OR full_name = :u", u: url)
                             .first&.id
      end
    end
  end
end
