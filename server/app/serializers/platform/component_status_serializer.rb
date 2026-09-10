# frozen_string_literal: true

module Platform
  # The ONE wire shape for a component status row, shared by the REST door
  # (Api::V1::Platform::ComponentStatusesController) and the MCP tool
  # (Ai::Tools::PlatformStatusTool). Two hand-rolled shapes for the same row is
  # how a page and an agent end up disagreeing about whether something is down.
  #
  # ── `not_measured` IS THE WIRE NAME (design §4.1) ───────────────────────────
  #
  # The absent-measurement verdict travels as `not_measured` end to end. The
  # `unknown` alias the platform-health REST route emits today is a different
  # producer and is retired with HealthPanel (C4). Nothing in this file, and
  # nothing downstream of it, may rename the verdict on the way out: a UI that
  # sees `unknown` cannot tell "we did not look" from "the value is unknown to
  # you", and a spec greps the rendered JSON for the literal.
  #
  # ── TWO SHAPES ─────────────────────────────────────────────────────────────
  #
  # `summary` is what a list renders: the verdict, the identity, the
  # presentation the page draws a card from, and a condition COUNT. `detail`
  # adds the payloads a drawer needs — the conditions themselves, dependency
  # edges, remediation, links and actions.
  class ComponentStatusSerializer
    # The two buckets a row can render in. `shared` rows carry a NULL account
    # and belong to no tenant's operational verdict (design §4.4).
    SCOPE_SHARED  = "shared"
    SCOPE_ACCOUNT = "account"

    def initialize(row, plane: nil)
      @row = row
      @plane = plane
    end

    def self.summary(row, plane: nil)
      new(row, plane: plane).summary
    end

    def self.detail(row, plane: nil)
      new(row, plane: plane).detail
    end

    def self.summary_collection(rows, plane: nil)
      Array(rows).map { |row| summary(row, plane: plane) }
    end

    # The compact row. Small on purpose: an MCP client listing 150 components
    # pays for every key, and a drawer's payloads are one `get` away.
    def summary
      {
        id: @row.id,
        component_kind: @row.component_kind,
        component_ref: @row.component_ref,
        display_name: @row.display_name,
        verdict: @row.verdict,
        # TWO different questions, and the page needs both. `held` is the
        # derived verdict being exactly `held` — nothing else is wrong with
        # it. `held_by_intent` is whether the operator has cordoned, paused or
        # drained it, WHATEVER its verdict; that is the half the dual rollup
        # counts and excludes (design §4.1, L2 ruling). A cordoned node that
        # is also down reads verdict `down`, `held` false, `held_by_intent`
        # true — collapsing the two would hide either the drain or the outage.
        held: @row.held?,
        held_by_intent: @row.held_by_intent?,
        unhealthy: @row.unhealthy?,
        shared: @row.account_id.nil?,
        # "shared" | "account" — the bucket this row renders in (ruling
        # 2026-09-10, from the A3 review). A NULL-account row is written by a
        # process-wide contributor, is readable by any holder of
        # platform.status.read, and NEVER enters a per-account operational
        # verdict. The contributor is the one responsible for sanitizing it;
        # this label is what lets the page put it in the right section rather
        # than inferring tenancy from a null.
        scope: @row.account_id.nil? ? SCOPE_SHARED : SCOPE_ACCOUNT,
        environment_id: @row.environment_id,
        plane: plane_label,
        presentation: @row.presentation,
        condition_count: Array(@row.conditions).size,
        # The reason of the worst false condition, so a list row can say WHY
        # without carrying every condition. Nil when nothing is false.
        reason: failing_reason,
        remediation_state: remediation_state,
        observed_at: iso(@row.observed_at),
        last_seen_sweep_at: iso(@row.last_seen_sweep_at),
        last_transition_at: iso(@row.last_transition_at)
      }
    end

    # Everything the drawer needs. Conditions and dependencies pass through as
    # the contributor wrote them (design §4.2) — core does not reshape a
    # kind's evidence.
    def detail
      summary.merge(
        conditions: Array(@row.conditions),
        dependencies: Array(@row.dependencies),
        remediation: @row.remediation.presence || {},
        links: Array(@row.links),
        # Each entry names its OWN permission; the page hides a button the
        # viewer cannot use and the door that action names checks it again.
        # Holding platform.status.read is not authority to run any of them.
        actions: Array(@row.actions),
        observed_generation: @row.observed_generation,
        last_notified_at: iso(@row.last_notified_at)
      )
    end

    private

    def plane_label
      @plane || ::Platform::Status::Query.plane_label(@row)
    end

    def remediation_state
      state = @row.remediation.is_a?(Hash) ? (@row.remediation["state"] || @row.remediation[:state]) : nil
      state.presence || ::Platform::ComponentStatus::REMEDIATION_NONE
    end

    # The reason token of the worst-ranked failing condition. Reasons are
    # CamelCase tokens (design §4.2) and are never passed to a status-variant
    # lookup, which lowercases.
    def failing_reason
      failing = Array(@row.conditions).select do |condition|
        next false unless condition.is_a?(Hash)

        status = condition["status"].nil? ? condition[:status] : condition["status"]
        status == false || status == "unknown"
      end
      return nil if failing.empty?

      worst = failing.max_by { |c| ::Platform::ComponentStatus.rank_of(::Platform::Status::Condition.verdict_for(c)) }
      worst["reason"] || worst[:reason]
    end

    def iso(value)
      return nil if value.blank?

      value.respond_to?(:iso8601) ? value.iso8601 : value.to_s
    end
  end
end
