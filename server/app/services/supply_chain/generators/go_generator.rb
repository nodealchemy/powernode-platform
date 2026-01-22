# frozen_string_literal: true

module SupplyChain
  module Generators
    class GoGenerator < BaseGenerator
      def generate(lockfile_content: nil)
        # Placeholder for Go ecosystem support
        raise NotImplementedError, "Go support not yet implemented"
      end

      private

      def parse_go_mod(content)
        # Parse go.mod format
        []
      end

      def parse_go_sum(content)
        # Parse go.sum format
        []
      end
    end
  end
end
