# frozen_string_literal: true

module Platform
  module Status
    # The CONTRIBUTOR CONTRACT (design §4.4) — the generic seam through which
    # anything at all becomes a component with a status.
    #
    # Core registers a handful of kinds; the system extension registers a dozen
    # more; a future extension registers its own without core learning its
    # name. Everything kind-specific lives in ONE method, `conditions_for`.
    #
    # This class is a DUCK-TYPE BASE, not a required superclass: the registry
    # accepts anything answering these messages, so a contributor may be a
    # plain object, a module, or a subclass of this. Subclassing buys the
    # documented defaults and nothing else.
    #
    #   class MyContributor < Platform::Status::Contributor
    #     def kind = "my_thing"
    #     def each_component(account) = MyThing.for(account).find_each { |r| yield r }
    #     def ref_for(record) = record.id
    #     def conditions_for(record) = [ Condition.build(type: "Reachable", status: record.up?, reason: ...) ]
    #   end
    #
    # ── SCOPE IS THE CONTRIBUTOR'S JOB ──────────────────────────────────────
    # `each_component` yields only LIVE records. Terminated, archived and
    # soft-deleted rows are excluded BY THE CONTRIBUTOR, and each kind's doc
    # states its scope. Core cannot know which of a kind's states mean "gone",
    # and a terminated instance that keeps a row would show a permanent `down`
    # nobody can clear. The reap arm (SweepService) then removes the row a
    # contributor stopped yielding.
    #
    # ── HOW `held` AND `progressing` ARE REACHED ────────────────────────────
    # ONLY through a condition typed `Held` or `Progressing` with status
    # true. There is deliberately NO `verdict_override` hook. A second channel
    # for setting a verdict would be a verdict with no evidence attached: the
    # operator would see "held" with no reason, no message and no transition
    # time, and no spec could assert WHY. Keeping the derivation a pure
    # function of the conditions means every verdict on the screen can be
    # traced to a row of evidence.
    #
    #   Condition.build(type: "Held", status: true, reason: "Cordoned",
    #                   message: "cordoned by alice 4m ago")
    #
    # Note the ladder: `held` ranks just above `ok`, so a component that is
    # BOTH held and failing reports the failure. Operator intent hides a
    # planned drain, never a real outage. Rollup carries the held count beside
    # the operational verdict (Platform::Status::Rollup).
    class Contributor
      # The registry key. Snake_case, stable, and the suffix of the drawer slot
      # id `platform.status.drawer.<kind>`.
      def kind
        raise NotImplementedError, "#{self.class}#kind must return the registry key"
      end

      # Yields each LIVE record for this account. See "SCOPE IS THE
      # CONTRIBUTOR'S JOB" above.
      def each_component(_account)
        raise NotImplementedError, "#{self.class}#each_component must yield records"
      end

      # False for process-wide kinds — a Redis connection, a disk image
      # registry, anything with no tenant. Their rows carry a NULL account,
      # render in a "shared infrastructure" section, and never enter a
      # per-account rollup.
      def account_scoped?
        true
      end

      # Stable identity within the kind. Must not change between sweeps for
      # the same component, or the reap arm will churn rows.
      def ref_for(record)
        record.try(:id).to_s
      end

      def display_name_for(record)
        record.try(:name).presence || record.try(:slug).presence || ref_for(record)
      end

      # Which environment/plane this component sits in, or nil. Most core
      # kinds carry none, which is why the environment filter is three-valued.
      def environment_id_for(_record)
        nil
      end

      # [{label:, path:}] — where the operator goes to see the real thing.
      def links_for(_record)
        []
      end

      # {icon: "<Lucide icon name>", label:, group_order:}. The icon is a
      # STRING, matching the convention the feature-settings surface already
      # uses, so no extension ever imports a core icon component.
      def presentation
        { "icon" => "Circle", "label" => kind.to_s.humanize, "group_order" => 100 }
      end

      # THE ONLY PLACE KIND-SPECIFIC LOGIC LIVES. Returns an array of
      # Platform::Status::Condition hashes.
      def conditions_for(_record)
        raise NotImplementedError, "#{self.class}#conditions_for must return conditions"
      end

      # [{kind:, ref:, relation: requires|serves|hosts|backs|routes}] — the
      # components THIS one depends on. Rollup#impact reverse-walks these.
      def dependencies_for(_record)
        []
      end

      # [{key:, label:, method:, path:, permission:, destructive:,
      #   confirm: {prompt:, requires_reason:}}]
      # The page renders buttons from this data and issues the request itself;
      # core learns nothing about the kind. The `permission` MUST be the one
      # the REST door actually checks — a button that renders and then 403s is
      # worse than no button.
      def actions_for(_record)
        []
      end

      # The generation/version the observation was made against, when the
      # source has one (a counter, a sha, a module version id).
      def observed_generation_for(_record)
        nil
      end

      # When the underlying measurement was taken, if the source knows better
      # than "now" — a cached snapshot's `captured_at`, say. Freshness honesty
      # depends on this being the SOURCE's time, not the sweep's.
      def observed_at_for(_record)
        nil
      end

      # Maps a FleetEvent/SignalState to this component (by node_instance_id,
      # payload.instance_id, certificate_id, ...). A5 consumes it; nil means
      # "signals never bind to this kind".
      def signal_resolver
        nil
      end

      # Drawer and investigation defaults. Optional.
      def runbook_key
        nil
      end

      def owner_agent_slug
        nil
      end
    end
  end
end
