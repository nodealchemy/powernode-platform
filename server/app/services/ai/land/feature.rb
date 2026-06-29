# frozen_string_literal: true

module Ai
  module Land
    # Flag gate for the canonical (polymorphic) land path that lands Missions
    # through Ai::Land alongside Campaigns. Default OFF: when this returns false,
    # a mission's merging phase keeps dispatching the legacy AiMissionMergeJob and
    # nothing about campaign landing changes. Activated via the
    # AI_MISSION_CANONICAL_LANDING env var (global) or a Flipper feature flag
    # (:mission_canonical_landing, optionally per-account). Fails closed (OFF) on
    # any error so an activation-system hiccup can never change default behavior.
    module Feature
      module_function

      def mission_landing_enabled?(account: nil)
        return true if ENV["AI_MISSION_CANONICAL_LANDING"] == "true"
        return false unless defined?(::Flipper)

        if account
          ::Flipper.enabled?(:mission_canonical_landing, account)
        else
          ::Flipper.enabled?(:mission_canonical_landing)
        end
      rescue StandardError
        false
      end
    end
  end
end
