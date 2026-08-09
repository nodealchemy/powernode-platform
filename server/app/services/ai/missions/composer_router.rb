# frozen_string_literal: true

module Ai
  module Missions
    # Single source of truth for HYBRID COMPOSER ROUTING. Decides — via a
    # SIDE-EFFECT-FREE predicate — which composer builds a mission's plan:
    #
    #   * ::Ai::Provisioning::PlanComposerService — the constrained PROVISIONING
    #     composer (every step in ALLOWED_EXECUTORS; persists on success). Chosen
    #     for a RECOGNIZED provisioning scenario.
    #   * ::Ai::Missions::MissionComposer — the general LLM composer (any
    #     agent-bound skill). Chosen for novel/general intents.
    #
    # Both composers stamp the SAME mission.configuration["plan"]["plan_id"], so
    # #execute and SkillCompositionRunner are unchanged downstream.
    #
    # Reused by EVERY compose entry point so routing is identical everywhere:
    #   - the worker-job phase pipeline (Api::V1::Internal::Ai::ProvisioningController#compose_plan),
    #   - the concierge chat flow (Ai::Tools::ProvisioningTool#compose_plan), and
    #   - the public deep-link REST endpoint (Api::V1::Ai::MissionsController#compose_plan).
    #
    # The predicate runs BEFORE composing — never try-then-discard — because
    # PlanComposerService persists on success, so a discarded probe would leak a
    # real plan into the database.
    class ComposerRouter
      # Pull the Project Brief out of a mission's configuration. Returns {} when
      # the mission has no brief yet (routes to the general composer with intent
      # "", letting compose! surface the empty-intent error upstream). Never raises.
      def self.extract_brief(mission)
        cfg = mission&.configuration
        return {} unless cfg.is_a?(Hash)

        brief = cfg["brief"] || cfg[:brief]
        brief.is_a?(Hash) ? brief : {}
      end

      def initialize(account:, mission:)
        @account = account
        @mission = mission
      end

      # Returns an UN-invoked composer instance (no compose, no persistence).
      # Defaults to the mission's stored brief when none is passed.
      def select(brief: nil)
        brief = self.class.extract_brief(@mission) if brief.nil?

        if deterministic_provisioning?(brief)
          log_choice("PlanComposerService", "recognized provisioning scenario")
          ::Ai::Provisioning::PlanComposerService.new(account: @account, mission: @mission)
        else
          log_choice("MissionComposer", "novel/general intent, no recognized provisioning scenario")
          ::Ai::Missions::MissionComposer.new(
            account: @account, mission: @mission, intent: brief["intent"].to_s
          )
        end
      end

      # True when the brief matches a RECOGNIZED provisioning scenario, grounded
      # entirely in PlanComposerService's existing signal maps — no hardcoded
      # use_case enum. Provisioning-shaped when EITHER its use_case maps to a known
      # role module (ROLE_MODULE_FOR_USE_CASE), OR it carries provisioning fields:
      # a non-empty regions list, a preferred_provider, a runtime_hint that maps
      # to a known runtime module (RUNTIME_HINT_TO_MODULE), or scale.initial > 0.
      #
      # Class-level because it is pure on the brief, and PlanComposerService gates
      # its deterministic synthesis on the SAME predicate that routed the brief
      # there — one source of truth for "recognized provisioning scenario".
      def self.deterministic_provisioning?(brief)
        return false unless brief.is_a?(Hash)

        recognized_use_case?(brief) || provisioning_shaped_fields?(brief)
      end

      def deterministic_provisioning?(brief)
        self.class.deterministic_provisioning?(brief)
      end

      def self.recognized_use_case?(brief)
        use_case = brief["use_case"].to_s.strip.downcase
        return false if use_case.empty?

        ::Ai::Provisioning::PlanComposerService::ROLE_MODULE_FOR_USE_CASE.key?(use_case)
      end
      private_class_method :recognized_use_case?

      def self.provisioning_shaped_fields?(brief)
        return true if Array(brief["regions"]).reject { |r| r.to_s.strip.empty? }.any?
        return true if brief["preferred_provider"].to_s.strip.present?
        return true if known_runtime_hint?(brief)

        positive_scale_initial?(brief)
      end
      private_class_method :provisioning_shaped_fields?

      def self.known_runtime_hint?(brief)
        hint = brief["runtime_hint"].to_s.strip.downcase
        return false if hint.empty?

        map = ::Ai::Provisioning::PlanComposerService::RUNTIME_HINT_TO_MODULE
        # A hint is provisioning-shaped only when it names a runtime that actually
        # maps to a module — a hint of "none" (maps to nil) is not a provision signal.
        map.key?(hint) && map[hint].present?
      end
      private_class_method :known_runtime_hint?

      def self.positive_scale_initial?(brief)
        scale = brief["scale"]
        return false unless scale.is_a?(Hash)

        Integer(scale["initial"]).positive?
      rescue ArgumentError, TypeError
        false
      end
      private_class_method :positive_scale_initial?

      private

      def log_choice(composer, reason)
        Rails.logger.info(
          "[ComposerRouter] mission=#{@mission&.id} routing to #{composer} (#{reason})"
        )
      end
    end
  end
end
