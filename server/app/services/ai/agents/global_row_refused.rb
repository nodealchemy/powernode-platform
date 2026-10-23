# frozen_string_literal: true

module Ai
  module Agents
    # A runtime writer was handed a GLOBAL canonical agent row.
    class GlobalRowRefused < StandardError
      attr_reader :reason, :details

      def initialize(message, reason:, details: {})
        super(message)
        @reason = reason
        @details = details
      end
    end
  end
end
