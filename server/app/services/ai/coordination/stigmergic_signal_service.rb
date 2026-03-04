# frozen_string_literal: true

module Ai
  module Coordination
    class StigmergicSignalService
      def initialize(account:)
        @account = account
      end

      def emit!(signal_type:, signal_key:, agent:, strength: 1.0, decay_rate: 0.05, payload: {}, ttl: nil)
        signal = Ai::StigmergicSignal.create!(
          account: @account,
          emitter_agent: agent,
          signal_type: signal_type,
          signal_key: signal_key,
          strength: strength,
          decay_rate: decay_rate,
          payload: payload,
          expires_at: ttl ? ttl.from_now : nil
        )

        broadcast_signal(signal)

        signal
      end

      def perceive(agent:, signal_types: nil, limit: 20)
        scope = Ai::StigmergicSignal.active.for_account(@account.id).strongest
        scope = scope.by_type(signal_types) if signal_types.present?
        signals = scope.limit(limit)

        signals.each { |s| s.perceive!(agent_id: agent.id) }
        signals
      end

      def reinforce!(signal_id:, agent:, strength_delta: 0.1)
        signal = Ai::StigmergicSignal.find_by(id: signal_id, account: @account)
        return nil unless signal

        signal.reinforce!(agent_id: agent.id, strength_delta: strength_delta)
        signal
      end

      def aggregate(signal_type:, artifact_ref: nil)
        scope = Ai::StigmergicSignal.active.for_account(@account.id).by_type(signal_type)
        scope = scope.by_key(artifact_ref) if artifact_ref.present?

        {
          total_strength: scope.sum(:strength).round(4),
          signal_count: scope.count,
          avg_strength: scope.average(:strength)&.round(4) || 0.0,
          strongest: scope.strongest.first&.as_json(only: [:id, :signal_key, :strength, :payload])
        }
      end

      def trail(artifact_ref:)
        Ai::StigmergicSignal.where(account: @account, signal_key: artifact_ref)
          .order(created_at: :asc)
          .map do |s|
            {
              id: s.id,
              type: s.signal_type,
              strength: s.strength,
              emitter_agent_id: s.emitter_agent_id,
              reinforcements: s.reinforce_count,
              perceive_count: s.perceive_count,
              created_at: s.created_at.iso8601,
              active: s.active?
            }
          end
      end

      def decay_all!
        decayed = 0
        Ai::StigmergicSignal.active.for_account(@account.id).find_each do |signal|
          signal.decay!
          decayed += 1
        end
        decayed
      end

      private

      def broadcast_signal(signal)
        McpChannel.broadcast_to_account(
          @account.id,
          {
            type: "stigmergic_signal",
            signal_id: signal.id,
            signal_type: signal.signal_type,
            signal_key: signal.signal_key,
            strength: signal.strength,
            emitter_agent_id: signal.emitter_agent_id,
            timestamp: Time.current.iso8601
          }
        )
      rescue StandardError => e
        Rails.logger.warn("[StigmergicSignal] Broadcast failed: #{e.message}")
      end
    end
  end
end
