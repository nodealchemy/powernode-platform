# frozen_string_literal: true

module Powernode
  # Core-side extension point for polymorphic file "attachable" targets.
  #
  # Core owns only the generic `Page` attachable. Extensions register their own
  # attachable types (e.g. the supply-chain extension's SBOM/attestation/
  # container-image/vendor records) here at boot; core never names an extension
  # namespace. When no extension registers a type, `resolve` returns nil and the
  # caller treats the attachable as not found.
  #
  # A resolver is a callable taking (account, id) and returning the record (or nil):
  #   Powernode::AttachableRegistry.register("Some::Type") do |account, id|
  #     account.some_association.find_by(id: id)
  #   end
  module AttachableRegistry
    class << self
      # Register (or replace) the resolver for a polymorphic attachable type.
      # @param type [String] the attachable_type token (e.g. an extension's model name)
      # @param resolver [#call] a callable taking (account, id) => record or nil
      def register(type, resolver = nil, &block)
        callable = resolver || block
        raise ArgumentError, "a resolver or block is required" unless callable.respond_to?(:call)

        resolvers[type.to_s] = callable
        callable
      end

      # @return [#call, nil] the resolver for the type, or nil if none registered.
      def resolve(type)
        resolvers[type.to_s]
      end

      def registered_types
        resolvers.keys
      end

      # Test/boot helper.
      def reset!
        @resolvers = {}
      end

      private

      def resolvers
        @resolvers ||= {}
      end
    end
  end
end
