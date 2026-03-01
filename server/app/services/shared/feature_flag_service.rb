# frozen_string_literal: true

module Shared
  class FeatureFlagService
    class << self
      def enabled?(flag, actor = nil)
        if actor
          Flipper.enabled?(flag, actor)
        else
          Flipper.enabled?(flag)
        end
      rescue => e
        Rails.logger.error "[FeatureFlag] Error checking flag '#{flag}': #{e.message}"
        false
      end

      def enable!(flag, actor = nil)
        if actor
          Flipper.enable(flag, actor)
        else
          Flipper.enable(flag)
        end
      end

      def disable!(flag, actor = nil)
        if actor
          Flipper.disable(flag, actor)
        else
          Flipper.disable(flag)
        end
      end

      def enable_percentage!(flag, percentage)
        Flipper.enable_percentage_of_actors(flag, percentage)
      end

      def all_flags
        Flipper.features.map do |feature|
          {
            name: feature.name,
            enabled: feature.enabled?,
            gate_values: feature.gate_values.to_h
          }
        end
      rescue => e
        Rails.logger.error "[FeatureFlag] Error listing flags: #{e.message}"
        []
      end
    end
  end
end
