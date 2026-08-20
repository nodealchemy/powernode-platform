# frozen_string_literal: true

module Shared
  # THE storage-size declaration order, in one place (IMP-b439270dab0d).
  #
  # Four surfaces read "how much disk did this step declare?" — the composing
  # executor, the cost estimator, the plan snapshot's labels and the composer's
  # stamping. They were spelled four times with three different answers, and the
  # class of bug that produces is not hypothetical: IMP-f85254148755 lost a whole
  # volume declaration to an unread alias, and IMP-051509357291 removed a
  # quote/actuator key disagreement of exactly this shape.
  #
  # THE ORDER: the advertised key first, the tolerated alias second, and the
  # first PRESENT value wins.
  #
  #   * `with_storage_gb` is the only ADVERTISED input — the key
  #     PlanComposerService stamps and the kwarg the executors consume.
  #   * `storage_gb` is a compatibility read for hand-authored plan_data and
  #     MissionComposer output, never a descriptor entry.
  #   * present?, NOT truthiness. A blank-but-non-nil `with_storage_gb: ""` must
  #     fall through to a real alias rather than winning and reading 0 — a
  #     truthiness reader quotes and labels no volume for a step that provisions
  #     one.
  #   * An explicit `0` is PRESENT, so it wins and means "no storage" — a
  #     legitimate answer (IMP-33fa6c51f05d), not an absent one.
  #
  # NOT AN ALIAS: `size_gb`. Every occurrence in the tree is
  # System::ProviderVolume#size_gb, the volume model's own column — a different
  # noun that no producer emits as a step input. One display path read it, which
  # honoured a key nothing writes while the executor and estimator ignored it.
  #
  # WHY THIS LIVES IN CORE rather than on the extension's published reader,
  # which is where the task pointed: three of the four surfaces
  # (CostEstimatorService, PlanSnapshotService, PlanComposerService) are core,
  # and core must not depend on an extension — the invariant aside, core mode
  # runs with no system extension loaded at all, so a core caller reaching for
  # System::Ai::Skills::ProvisionFullStackExecutor would be a NameError on every
  # install without it. The extension's reader keeps its name and its callers
  # and delegates here, so there is still exactly one order — the same shape
  # Shared::SdwanNetworkResolution already uses for the fabric declaration.
  module StorageSizeResolution
    # The advertised input key.
    ADVERTISED_KEY = "with_storage_gb"
    # Tolerated on the way IN only; every surface EMITS the advertised key.
    ALIAS_KEY = "storage_gb"
    KEYS = [ ADVERTISED_KEY, ALIAS_KEY ].freeze

    class << self
      # First present of an ordered value list — the shape a caller that already
      # holds the two values (an executor's kwargs) needs.
      def resolve(*values)
        values.find(&:present?)
      end

      # First present value across KEYS in an inputs hash, tolerating string and
      # symbol keys (jsonb round-trips strings; in-memory writers use symbols).
      # Returns nil when nothing is declared — callers decide what absence means,
      # because they legitimately differ: the estimator quotes no line, the
      # composer falls back to the brief, the label says "Attach storage".
      def from_inputs(inputs)
        return nil unless inputs.respond_to?(:[])

        KEYS.lazy.flat_map { |key| [ inputs[key], inputs[key.to_sym] ] }.find(&:present?)
      end
    end
  end
end
