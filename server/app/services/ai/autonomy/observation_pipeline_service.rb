# frozen_string_literal: true

module Ai
  module Autonomy
    class ObservationPipelineService
      # Default sensor classes to run
      DEFAULT_SENSORS = %w[
        Ai::Autonomy::Sensors::KnowledgeHealthSensor
        Ai::Autonomy::Sensors::PlatformHealthSensor
        Ai::Autonomy::Sensors::RecommendationSensor
      ].freeze

      attr_reader :account, :agent

      def initialize(account:, agent:)
        @account = account
        @agent = agent
      end

      # Run all configured sensors for the agent and create observations.
      #
      # @param sensor_config [Hash] which sensors to run (from duty_cycle_config)
      # @return [Array<Ai::AgentObservation>] created observations
      def run(sensor_config: nil)
        sensors = resolve_sensors(sensor_config)
        created = []

        sensors.each do |sensor_class|
          observations = safe_collect(sensor_class)
          observations.each do |attrs|
            obs = Ai::AgentObservation.create!(attrs)
            created << obs
          rescue ActiveRecord::RecordInvalid => e
            Rails.logger.warn "[ObservationPipeline] Failed to create observation: #{e.message}"
          end
        end

        created
      end

      # Run sensors for all agents with autonomous loops in the account.
      #
      # @return [Hash] { agents_processed: Integer, observations_created: Integer }
      def self.run_for_account(account)
        agents_processed = 0
        observations_created = 0

        # Find agents with active autonomous ralph loops
        autonomous_agents = account.ai_agents
          .joins(:ralph_loops)
          .where(ai_ralph_loops: { scheduling_mode: "autonomous", schedule_paused: false })
          .where(ai_ralph_loops: { status: %w[pending running paused] })
          .distinct

        autonomous_agents.find_each do |agent|
          loop_config = agent.ralph_loops
            .find_by(scheduling_mode: "autonomous")
            &.duty_cycle_config

          pipeline = new(account: account, agent: agent)
          results = pipeline.run(sensor_config: loop_config&.dig("sensor_config"))
          observations_created += results.size
          agents_processed += 1
        rescue StandardError => e
          Rails.logger.error "[ObservationPipeline] Error for agent #{agent.id}: #{e.message}"
        end

        { agents_processed: agents_processed, observations_created: observations_created }
      end

      private

      def resolve_sensors(config)
        sensor_map = {
          "knowledge_health" => "Ai::Autonomy::Sensors::KnowledgeHealthSensor",
          "platform_health" => "Ai::Autonomy::Sensors::PlatformHealthSensor",
          "recommendations" => "Ai::Autonomy::Sensors::RecommendationSensor",
          "peer_agents" => "Ai::Autonomy::Sensors::PeerAgentSensor",
          "workspace" => "Ai::Autonomy::Sensors::WorkspaceActivitySensor",
          "code_changes" => "Ai::Autonomy::Sensors::CodeChangeSensor",
          "budget" => "Ai::Autonomy::Sensors::BudgetSensor"
        }

        if config.is_a?(Hash) && config.any?
          enabled = config.select { |_, v| v == true }.keys
          enabled.filter_map { |key| sensor_map[key]&.safe_constantize }
        else
          DEFAULT_SENSORS.filter_map(&:safe_constantize)
        end
      end

      def safe_collect(sensor_class)
        sensor = sensor_class.new(account: account, agent: agent)
        sensor.collect
      rescue StandardError => e
        Rails.logger.error "[ObservationPipeline] Sensor #{sensor_class.name} failed: #{e.message}"
        []
      end
    end
  end
end
