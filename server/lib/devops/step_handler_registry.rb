# frozen_string_literal: true

module Devops
  module StepHandlerRegistry
    class << self
      def register(type_key, handler_class, extension: nil)
        handlers[type_key.to_s] = { handler_class: handler_class, extension: extension }
      end

      def handler_for(type_key)
        entry = handlers[type_key.to_s]
        return nil unless entry

        entry[:handler_class].constantize
      rescue NameError
        Rails.logger.warn "[StepHandlerRegistry] Handler class #{entry[:handler_class]} not found for step type '#{type_key}'"
        nil
      end

      def all_types
        handlers.keys
      end

      def registered?(type_key)
        handlers.key?(type_key.to_s)
      end

      private

      def handlers
        @handlers ||= {}
      end
    end
  end
end
