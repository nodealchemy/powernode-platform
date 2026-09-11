# frozen_string_literal: true

module Platform
  module Status
    # ROLLUP, IMPACT AND ROOT CAUSE (design §4.1, §4.6) — everything that turns
    # a pile of component rows into one answer.
    #
    # ── THE DUAL RULE ───────────────────────────────────────────────────────
    # A rollup is computed TWICE: the OPERATIONAL verdict is the worst rank
    # over children excluding those held by operator intent, and the held count
    # travels beside it. A planned drain must never turn a header amber — if it
    # did, operators would learn to ignore amber, which costs more than the
    # drain ever saves. Held components are not hidden; they are counted and
    # rendered, just not summed into "something is wrong".
    #
    # INTENT IS READ FROM THE CONDITION, NOT THE DERIVED VERDICT (A1 review
    # L2). Both halves used to key on the verdict being `held`, and `held`
    # ranks just above `ok` — so a cordoned node that was also `down` reported
    # `down`, raised the headline AND was excluded from the held count. The
    # header went red for a planned drain and the caption explaining it said
    # zero. `held_count` and `counts_by_verdict` therefore DISAGREE on purpose:
    # a held-and-down component is one of the held, and also one of the `down`
    # in the per-verdict breakdown, because its own verdict is still `down`.
    #
    # ── EVERYTHING HERE IS PURE OVER IN-MEMORY ROWS ─────────────────────────
    # `impact` and `root_cause_candidates` walk a PRELOADED edge set. Walking
    # the graph with a query per hop would make a four-deep walk on a
    # 150-component fleet a few hundred queries on a 60-second cadence. The
    # callers that already hold the rows pass them in; the convenience path
    # loads them with exactly one query.
    module Rollup
      DEFAULT_DEPTH = 4

      module_function

      # @param scope [ActiveRecord::Relation, Enumerable<ComponentStatus>]
      # @return [Hash] {verdict:, held_count:, counts_by_verdict:, total:}
      def rollup(scope)
        rows = materialize(scope)
        counts = ComponentStatus::VERDICTS.index_with { 0 }
        rows.each { |row| counts[row.verdict] = counts.fetch(row.verdict, 0) + 1 }

        {
          verdict: ComponentStatus.worst_operational(rows),
          held_count: rows.count(&:held_by_intent?),
          counts_by_verdict: counts,
          total: rows.size
        }
      end

      # SHARED ROWS ARE SPLIT OUT, never summed in (design §4.4, ruling
      # 2026-09-10). A NULL-account row describes process-wide infrastructure
      # that belongs to no tenant; folding it into a per-account verdict would
      # turn one shared breaker into every tenant's outage. `rollup` does no
      # tenancy filtering of its own, so every door that shows an account a
      # verdict splits through HERE: one predicate, not a hand copy per door
      # (E7 review low 3 found three).
      #
      # @return [Array(Array<ComponentStatus>, Array<ComponentStatus>)]
      #   [account_rows, shared_rows]
      def partition_shared(scope)
        materialize(scope).partition { |row| row.account_id.present? }
      end

      # The account verdict and the shared verdict, side by side.
      #
      # @return [Hash] {rollup:, shared:}, each shaped like #rollup
      def split(scope)
        account_rows, shared_rows = partition_shared(scope)
        { rollup: rollup(account_rows), shared: rollup(shared_rows) }
      end

      # Who breaks if this component stays broken. Reverse-walks the
      # dependency edges (row.dependencies lists what a row DEPENDS ON, so the
      # dependents are the rows pointing AT this one), to `depth` hops.
      #
      # Cycle-safe by visited set — the shape NodeModule#all_dependencies
      # already uses. A dependency cycle is a data defect, not a reason for an
      # infinite walk.
      #
      # @return [Hash] {count:, worst_verdict:, components: [ComponentStatus]}
      def impact(component, rows: nil, depth: DEFAULT_DEPTH)
        rows = materialize(rows || neighbourhood_for(component))
        dependents_by_key = reverse_index(rows)

        found = walk(start: key_of(component), depth: depth) { |key| dependents_by_key[key] || [] }
        found.delete(key_of(component))
        components = found.values

        {
          count: components.size,
          worst_verdict: ComponentStatus.worst(components.map(&:verdict)),
          components: components
        }
      end

      # The upstream-most unhealthy components this one's failure could be
      # explained by. A HEURISTIC, and labelled as one on the page: it ranks
      # correlation, it does not prove causation.
      #
      # Walks UPSTREAM (this component's own dependencies, transitively),
      # keeping only unhealthy components — that connected unhealthy subgraph
      # is the candidate pool. "Upstream-most" means a candidate with no
      # unhealthy dependency of its own: the end of the chain, where the
      # trouble starts. Ranked by how many unhealthy components depend on it
      # (a shared cause explains more) and then by the earliest transition (it
      # broke first).
      #
      # @return [Array<ComponentStatus>]
      def root_cause_candidates(component, rows: nil, depth: DEFAULT_DEPTH)
        rows = materialize(rows || neighbourhood_for(component))
        by_key = rows.index_by { |row| key_of(row) }
        dependents_by_key = reverse_index(rows)

        upstream = walk(start: key_of(component), depth: depth) do |key|
          Array(by_key[key]&.dependencies).filter_map do |edge|
            candidate = by_key[edge_key(edge)]
            candidate if candidate&.unhealthy?
          end
        end
        # The component itself belongs to the subgraph: when nothing upstream
        # is broken, IT is the upstream-most unhealthy thing, and answering
        # "no candidates" for a component that is plainly down would be a
        # worse answer than the obvious one.
        self_row = by_key[key_of(component)] || component
        unhealthy = ([ self_row ] + upstream.values).uniq { |row| key_of(row) }.select(&:unhealthy?)
        return [] if unhealthy.empty?

        unhealthy_keys = unhealthy.map { |row| key_of(row) }.to_set
        roots = unhealthy.reject do |row|
          Array(row.dependencies).any? { |edge| unhealthy_keys.include?(edge_key(edge)) }
        end
        # A cycle of unhealthy components has no upstream-most member; ranking
        # the whole cycle beats returning nothing.
        roots = unhealthy if roots.empty?

        # Ranked by how many unhealthy components depend on it, then by which
        # broke FIRST. A row with no transition timestamp at all — the
        # not_measured case, "we have no idea when this broke" — sorts LAST
        # rather than first (A1 review L3): falling back to the epoch ranked
        # total ignorance ahead of a demonstrated four-hour-old failure.
        roots.sort_by do |row|
          unhealthy_dependents = (dependents_by_key[key_of(row)] || []).count(&:unhealthy?)
          transitioned_at = row.last_transition_at
          [ -unhealthy_dependents, transitioned_at.nil? ? 1 : 0, transitioned_at || Time.zone.at(0) ]
        end
      end

      # ── internals ─────────────────────────────────────────────────────────

      def materialize(scope)
        return [] if scope.nil?
        return scope.to_a if scope.respond_to?(:to_a)

        Array(scope)
      end

      # ONE query: the component's own tenant plus the shared rows, which is
      # the whole set an edge can legally point into.
      def neighbourhood_for(component)
        ComponentStatus.where(account_id: [ component.account_id, nil ].uniq)
      end

      def key_of(row)
        [ row.component_kind.to_s, row.component_ref.to_s ]
      end

      def edge_key(edge)
        return [ nil, nil ] unless edge.is_a?(Hash)

        [ (edge["kind"] || edge[:kind]).to_s, (edge["ref"] || edge[:ref]).to_s ]
      end

      # rows whose `dependencies` point at a key => the rows that depend on it.
      def reverse_index(rows)
        rows.each_with_object({}) do |row, index|
          Array(row.dependencies).each do |edge|
            (index[edge_key(edge)] ||= []) << row
          end
        end
      end

      # Breadth-first, bounded, cycle-safe. The block returns the next hop's
      # rows for a key. Returns {key => row} including the start when it
      # resolves to a row.
      def walk(start:, depth:)
        found = {}
        visited = Set.new([ start ])
        frontier = [ start ]

        depth.times do
          next_frontier = []
          frontier.each do |key|
            yield(key).each do |row|
              row_key = key_of(row)
              next if visited.include?(row_key)

              visited << row_key
              found[row_key] = row
              next_frontier << row_key
            end
          end
          break if next_frontier.empty?

          frontier = next_frontier
        end

        found
      end
    end
  end
end
