# frozen_string_literal: true

module Ai
  module Deploy
    # Outcome of a deploy Method invocation (or an Orchestrator phase). A dry-run
    # result carries the commands/actions the method WOULD have taken without
    # performing them, so an operator can review exactly what a real deploy does.
    class Result
      STATUSES = %i[succeeded failed dry_run rolled_back skipped].freeze

      attr_reader :status, :detail, :commands, :metadata

      def initialize(status:, detail: nil, commands: [], metadata: {})
        @status = status.to_sym
        raise ArgumentError, "unknown deploy result status #{status}" unless STATUSES.include?(@status)

        @detail = detail
        @commands = Array(commands)
        @metadata = metadata || {}
      end

      def succeeded? = status == :succeeded
      def failed? = status == :failed
      def dry_run? = status == :dry_run
      def rolled_back? = status == :rolled_back
      def skipped? = status == :skipped

      def to_h
        { status: status, detail: detail, commands: commands, metadata: metadata }
      end

      def self.ok(detail = nil, commands: [], **metadata)
        new(status: :succeeded, detail: detail, commands: commands, metadata: metadata)
      end

      def self.failure(detail, **metadata)
        new(status: :failed, detail: detail, metadata: metadata)
      end

      def self.dry(commands:, detail: nil, **metadata)
        new(status: :dry_run, detail: detail, commands: Array(commands), metadata: metadata)
      end

      def self.skip(detail, **metadata)
        new(status: :skipped, detail: detail, metadata: metadata)
      end
    end
  end
end
