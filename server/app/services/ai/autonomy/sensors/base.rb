# frozen_string_literal: true

module Ai
  module Autonomy
    module Sensors
      class Base
        attr_reader :account, :agent

        def initialize(account:, agent:)
          @account = account
          @agent = agent
        end

        # Collect observations from this sensor.
        # @return [Array<Hash>] observation attributes to create
        def collect
          raise NotImplementedError, "#{self.class.name} must implement #collect"
        end

        # Sensor type identifier (matches Ai::AgentObservation::SENSOR_TYPES)
        def sensor_type
          raise NotImplementedError, "#{self.class.name} must implement #sensor_type"
        end

        protected

        # Build an observation hash ready for AgentObservation.create!
        def build_observation(title:, observation_type:, severity: "info", data: {}, requires_action: false, expires_in: nil)
          fingerprint = Digest::SHA256.hexdigest("#{sensor_type}:#{title}:#{data.to_json}")

          # Skip if duplicate within dedup window
          return nil if Ai::AgentObservation.duplicate_exists?(
            agent_id: agent.id,
            sensor_type: sensor_type,
            data_fingerprint: fingerprint
          )

          {
            account_id: account.id,
            ai_agent_id: agent.id,
            sensor_type: sensor_type,
            observation_type: observation_type,
            severity: severity,
            title: title,
            data: data.merge("fingerprint" => fingerprint),
            requires_action: requires_action,
            expires_at: expires_in ? Time.current + expires_in : nil
          }
        end
      end
    end
  end
end
