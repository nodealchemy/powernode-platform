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
      # Return value for #run. Subclasses Array so every existing caller
      # (results.size, iteration) is unchanged, while carrying the rejection
      # accounting a caller now needs to tell a DEAD sensor from a quiet one.
      class RunResult < Array
        # sensor class name => count of rows that failed validation
        attr_accessor :rejected_by_sensor

        def rejected_count
          (rejected_by_sensor || {}).values.sum
        end
      end

      def run(sensor_config: nil)
        sensors = resolve_sensors(sensor_config)
        created = RunResult.new
        rejected_by_sensor = Hash.new(0)

        sensors.each do |sensor_class|
          observations = safe_collect(sensor_class)
          # Sensor::Base#build_observation returns nil on a dedup hit, and the
          # "drop the nils" step lives in each sensor's own #collect — which
          # means it is a convention ten sensors must each remember, and three
          # of them did not. Compacting HERE makes the omission harmless for
          # every sensor, present and future, instead of relying on ten call
          # sites to agree.
          #
          # What this actually costs when it is missing: create!(nil) raises
          # RecordInvalid (measured — not ArgumentError), so the rescue below
          # does catch it and the agent's remaining observations still persist.
          # The damage is a wasted INSERT per dedup hit plus a "Failed to
          # create observation" warning that is indistinguishable from a real
          # validation failure. Since the dedup window equals this pipeline's
          # cron period, that noise is routine.
          accepted = 0
          rejected = 0

          Array(observations).compact.each do |attrs|
            obs = Ai::AgentObservation.create!(attrs)
            created << obs
            accepted += 1
          rescue ActiveRecord::RecordInvalid => e
            rejected += 1
            Rails.logger.warn "[ObservationPipeline] Failed to create observation: #{e.message}"
          end

          rejected_by_sensor[sensor_class.name] += rejected if rejected.positive?

          # A sensor that produced ONLY rejections is indistinguishable, from
          # the outside, from a sensor that had nothing to report — both
          # contribute zero observations, and the per-row warning above reads
          # exactly like a routine dedup rejection. That is precisely how
          # CodeChangeSensor stayed dead from the day it was written: it
          # rejected 100% of its output for its entire life and nothing said
          # so; it was found by reading code, not by any signal.
          #
          # Escalated to error and stated as a rate, because "some rows were
          # invalid" is a different condition from "this sensor cannot produce
          # a valid row at all", and only the second is a wiring bug.
          if rejected.positive? && accepted.zero?
            Rails.logger.error(
              "[ObservationPipeline] sensor #{sensor_class.name} produced #{rejected} observation(s) " \
              "and ALL were rejected by validation — it is contributing nothing to this agent's " \
              "observations and is likely miswired (check its sensor_type against " \
              "Ai::AgentObservation::SENSOR_TYPES)"
            )
          end
        end

        created.rejected_by_sensor = rejected_by_sensor
        created
      end

      # Run sensors for all agents with autonomous loops in the account.
      #
      # @return [Hash] { agents_processed:, observations_created:, observations_rejected: }
      #
      # observations_rejected is carried through because this is what the cron
      # calls: a count that stops at #run is a count nothing an operator reads
      # will ever show.
      def self.run_for_account(account)
        agents_processed = 0
        observations_created = 0
        observations_rejected = 0

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
          observations_rejected += results.rejected_count if results.respond_to?(:rejected_count)
          agents_processed += 1
        rescue StandardError => e
          Rails.logger.error "[ObservationPipeline] Error for agent #{agent.id}: #{e.message}"
        end

        { agents_processed: agents_processed,
          observations_created: observations_created,
          observations_rejected: observations_rejected }
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
          "budget" => "Ai::Autonomy::Sensors::BudgetSensor",
          "goal_progress" => "Ai::Autonomy::Sensors::GoalProgressSensor",
          "stigmergic_signal" => "Ai::Autonomy::Sensors::StigmergicSignalSensor",
          "governance" => "Ai::Autonomy::Sensors::GovernanceSensor"
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
