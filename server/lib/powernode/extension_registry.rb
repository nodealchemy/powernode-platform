# frozen_string_literal: true

module Powernode
  module ExtensionRegistry
    class << self
      def register(slug:, engine:, version: nil, features_module: nil)
        extensions[slug.to_s] = { engine: engine, version: version, features_module: features_module }
      end

      def loaded?(slug)
        extensions.key?(slug.to_s)
      end

      def engine_for(slug)
        extensions.dig(slug.to_s, :engine)
      end

      def slugs
        extensions.keys
      end

      def all
        extensions.dup
      end

      def each(&block)
        extensions.each(&block)
      end

      def feature_available?(feature, account: nil)
        extensions.each_value do |ext|
          mod = ext[:features_module]
          next unless mod&.respond_to?(:available?)

          result = mod.available?(feature, account: account)
          return result unless result.nil?
        end
        false
      end

      # True if any loaded extension declares (owns) this feature, regardless of
      # whether it is currently available. Lets core distinguish a core feature
      # from an extension feature without naming any specific extension.
      def feature_owned?(feature)
        extensions.each_value do |ext|
          mod = ext[:features_module]
          next unless mod&.respond_to?(:available?)

          return true unless mod.available?(feature, account: nil).nil?
        end
        false
      end

      private

      def extensions
        @extensions ||= {}
      end
    end
  end
end
