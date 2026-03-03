# frozen_string_literal: true

module Devops
  # Registry for extension-provided pipeline step handlers.
  # Core step types are defined in PipelineStep::STEP_TYPES and resolved
  # by PipelineStep#handler_class directly. This registry allows extensions
  # (e.g., enterprise) to register additional step types at boot time.
  class StepHandlerRegistry
    class << self
      def register(step_type, handler_class)
        registry[step_type.to_s] = handler_class
      end

      def handler_for(step_type)
        registry[step_type.to_s]
      end

      def all_types
        registry.keys
      end

      def reset!
        @registry = {}
      end

      private

      def registry
        @registry ||= {}
      end
    end
  end
end
