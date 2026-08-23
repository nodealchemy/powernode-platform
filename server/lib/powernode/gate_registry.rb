# frozen_string_literal: true

module Powernode
  # Registry of the platform's human-approval GATE MECHANISMS, each declaring
  # its SPECIES (readiness map 2026-08-12 §6.4, IMP-bc4cae11fe19).
  #
  # Two species of gate read alike at a call site and mean different things:
  #
  #   :policy   — "may this CLASS of action run at all". The verdict comes from
  #               operator-tunable policy (Ai::InterventionPolicy resolution,
  #               capability matrix) keyed by an action category, and applies
  #               to every instance of that class of action.
  #   :workflow — "checkpoint inside ONE operation". A specific run (a mission
  #               phase, a campaign land, a storage-migration cutover) parks at
  #               a named checkpoint until a human resolves THAT instance,
  #               regardless of any category policy.
  #
  # The registry RECORDS the distinction; it deliberately does not unify the
  # mechanisms (System::AdaptationGate showed the right instinct by reusing
  # FleetAutonomyService#gate_action! rather than minting a new mechanism).
  # What it buys: one authoritative list an operator queue view can iterate,
  # and a surface the coherence guard
  # (spec/lib/powernode/gate_registry_coherence_spec.rb) can hold every gate
  # site to — a gating seam that touches the platform's gating primitives
  # without declaring itself here is a spec failure, not silent drift.
  #
  # CORE/EXTENSION SEAM — core owns the registry and the species vocabulary
  # and registers only its own mechanisms below. Extensions DECLARE their gate
  # mechanisms from their Engine's `config.to_prepare` — NOT after_initialize:
  # IMP-8d444c6437a3 (powernode_system engine) is the recorded lesson that
  # after_initialize registration into reloadable state is wiped by every
  # dev-mode reload. register! replaces-by-name, so to_prepare's repeated runs
  # are safe. (Belt and braces: this file is also required explicitly from
  # config/application.rb, like the extension registry, so the module itself is
  # not Zeitwerk-managed and registrations survive reloads either way.)
  # E.g. the system extension owns System::Fleet::FleetAutonomyService#
  # gate_action!, System::AdaptationGate, and the System::StorageMigration
  # approve/cutover checkpoints. Core never names an extension mechanism here.
  module GateRegistry
    SPECIES = %i[policy workflow].freeze

    Entry = Struct.new(:mechanism, :species, :owner, :entry_points, :delegates_to,
                       :description, keyword_init: true) do
      def policy?   = species == :policy
      def workflow? = species == :workflow
    end

    # Core's own gate mechanisms. `mechanism` is the fully-qualified class (or
    # concern module) name; `entry_points` are the methods a call site invokes
    # to cross the gate; `delegates_to` records a surface that fronts another
    # registered mechanism rather than touching the gating primitives itself.
    CORE_MECHANISMS = [
      # ---- :policy — "may this CLASS of action run at all" ------------------
      {
        mechanism: "Ai::AutonomyGate", species: :policy, owner: "core",
        entry_points: %w[evaluate],
        description: "Central choke point for gated mutations: resolves Ai::InterventionPolicy " \
                     "per action_category, writes an Ai::DeferredOperation, mints the " \
                     "ApprovalRequest on require_approval."
      },
      {
        mechanism: "Ai::GatedActions", species: :policy, owner: "core",
        entry_points: %w[gate! gate_create! gate_update!],
        delegates_to: "Ai::AutonomyGate",
        description: "Controller surface over Ai::AutonomyGate — renders the " \
                     "proceed/pending/blocked branches; touches no primitive itself."
      },
      {
        mechanism: "Ai::Autonomy::ExecutionGateService", species: :policy, owner: "core",
        entry_points: %w[check],
        description: "Pre-execution class-of-action gate: suspension, capability matrix, " \
                     "intervention policy, budget, conformance, anomaly, trust freshness. " \
                     "Returns a decision; mints no obligation of its own."
      },
      {
        mechanism: "Ai::SkillRecipeRunner", species: :policy, owner: "core",
        entry_points: %w[requires_approval? enforce_policy_block!],
        description: "Per-step policy resolution under 'ai.recipe.<tool>' categories; a " \
                     "require_approval verdict (or the recipe author's own require_approval " \
                     "flag) pauses the run at that step. Policy species: the verdict source " \
                     "is category-keyed Ai::InterventionPolicy, even though the pending " \
                     "artifact is a paused run rather than a DeferredOperation."
      },

      # ---- :workflow — "checkpoint inside ONE operation" --------------------
      {
        mechanism: "Ai::Approvals::Gateway", species: :workflow, owner: "core",
        entry_points: %w[request! resolve!],
        description: "Canonical facade for human-approval checkpoints on a single operation " \
                     "(mission plan_review/handoff, agent proposals, improvement " \
                     "recommendations). Core-mode auto-proceeds."
      },
      {
        mechanism: "Ai::Autonomy::ApprovalWorkflowService", species: :workflow, owner: "core",
        entry_points: %w[request_approval approve reject expire_overdue!],
        description: "Chain-workflow wrapper: mints agent-sourced approval requests and " \
                     "resolves/expires open ones through the multi-step chain machinery."
      },
      {
        mechanism: "Ai::Land::ApprovalBinding", species: :workflow, owner: "core",
        entry_points: %w[request_land_approval],
        description: "Land checkpoint for a completed change-set: security gate + scope " \
                     "guardrail, then auto-approve or park the CampaignLand pending a human."
      },
      {
        mechanism: "Ai::GovernanceService", species: :workflow, owner: "core",
        entry_points: %w[request_approval],
        description: "Generic chain-backed checkpoint minting for the governance API surface " \
                     "(caller supplies the chain)."
      }
    ].freeze

    class << self
      # Declare a gate mechanism. Extensions call this from their engine's
      # `config.to_prepare` (see the seam note above); idempotent per mechanism
      # name (re-registration replaces, so a re-run block cannot duplicate).
      #
      # @param mechanism [String] fully-qualified class/module name
      # @param species [Symbol] one of SPECIES
      # @param owner [String] "core" or the extension slug
      # @param entry_points [Array<String>] method names call sites invoke
      # @param delegates_to [String, nil] mechanism this one fronts, if any
      # @param description [String, nil]
      def register!(mechanism:, species:, owner:, entry_points:, delegates_to: nil, description: nil)
        name = mechanism.to_s
        raise ArgumentError, "mechanism name required" if name.strip.empty?

        sp = species.to_sym
        unless SPECIES.include?(sp)
          raise ArgumentError, "unknown gate species #{species.inspect} — declare one of #{SPECIES.inspect}"
        end

        points = Array(entry_points).map(&:to_s)
        raise ArgumentError, "entry_points required for #{name}" if points.empty?

        entry = Entry.new(
          mechanism: name, species: sp, owner: owner.to_s, entry_points: points.freeze,
          delegates_to: delegates_to&.to_s, description: description
        ).freeze
        @mutex.synchronize { mechanisms[name] = entry }
        entry
      end

      def entries
        mechanisms.values
      end

      def registered?(mechanism)
        mechanisms.key?(mechanism.to_s)
      end

      def entry_for(mechanism)
        mechanisms[mechanism.to_s]
      end

      def species_of(mechanism)
        mechanisms[mechanism.to_s]&.species
      end

      def for_species(species)
        entries.select { |e| e.species == species.to_sym }
      end

      def core_entries
        entries.select { |e| e.owner == "core" }
      end

      private

      attr_reader :mechanisms
    end

    # Eager, at module body — a lazy `||=` in a reader would race register!
    # (a first unsynchronized read could rebuild a core-only hash over a
    # just-registered extension entry) and would reopen the ordering question
    # of registration-before-first-read. Core entries go through register!
    # itself so there is exactly one validation/normalization path (frozen
    # entry_points included).
    @mechanisms = {}
    @mutex = Mutex.new
    CORE_MECHANISMS.each { |attrs| register!(**attrs) }
  end
end
