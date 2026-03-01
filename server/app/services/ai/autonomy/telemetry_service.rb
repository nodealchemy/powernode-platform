# frozen_string_literal: true

module Ai
  module Autonomy
    class TelemetryService
      attr_reader :account

      def initialize(account:)
        @account = account
      end

      # Record a telemetry event
      # @param agent [Ai::Agent] The agent
      # @param category [String] Event category (action, trust, budget, etc.)
      # @param event_type [String] Specific event type
      # @param data [Hash] Event data
      # @param correlation_id [String] Correlation ID for linking related events
      # @param parent_event_id [String] Parent event ID for causal chains
      # @param outcome [String] Event outcome (success, failure, etc.)
      # @return [Ai::TelemetryEvent]
      def record_event(agent:, category:, event_type:, data: {}, correlation_id: nil, parent_event_id: nil, outcome: nil)
        correlation_id ||= SecureRandom.uuid
        seq = next_sequence(agent, correlation_id)

        Ai::TelemetryEvent.create!(
          account: account,
          agent: agent,
          event_category: category,
          event_type: event_type,
          sequence_number: seq,
          parent_event_id: parent_event_id,
          correlation_id: correlation_id,
          event_data: data,
          outcome: outcome
        )
      end

      # Query events with filters
      # @param agent_id [String] Optional agent filter
      # @param category [String] Optional category filter
      # @param limit [Integer] Max results
      # @return [ActiveRecord::Relation]
      def query_events(agent_id: nil, category: nil, limit: 100)
        scope = Ai::TelemetryEvent.where(account_id: account.id).recent.limit(limit)
        scope = scope.for_agent(agent_id) if agent_id.present?
        scope = scope.by_category(category) if category.present?
        scope.includes(:agent)
      end

      # Build a causal chain from an event
      # @param event [Ai::TelemetryEvent] Starting event
      # @return [Array<Ai::TelemetryEvent>] Ordered chain
      def build_causal_chain(event)
        # Walk up to find root
        root = event
        seen = Set.new([event.id])
        while root.parent_event_id.present?
          parent = Ai::TelemetryEvent.where(account_id: account.id).find_by(id: root.parent_event_id)
          break unless parent
          break if seen.include?(parent.id)

          seen.add(parent.id)
          root = parent
        end

        # Collect entire tree from root downward
        chain = [root]
        visited = Set.new([root.id])
        collect_children(root, chain, visited)
        chain.sort_by(&:sequence_number)
      end

      # List events for a specific agent
      def for_agent(agent, limit: 100)
        Ai::TelemetryEvent.for_agent(agent.id)
          .where(account_id: account.id)
          .recent
          .limit(limit)
      end

      private

      def next_sequence(agent, correlation_id)
        last = Ai::TelemetryEvent
          .where(agent_id: agent.id, correlation_id: correlation_id)
          .maximum(:sequence_number)

        (last || -1) + 1
      end

      def collect_children(event, chain, visited)
        children = Ai::TelemetryEvent.where(account_id: account.id, parent_event_id: event.id).ordered
        children.each do |child|
          next if visited.include?(child.id)

          visited.add(child.id)
          chain << child
          collect_children(child, chain, visited)
        end
      end
    end
  end
end
