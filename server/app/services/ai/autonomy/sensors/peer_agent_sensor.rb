# frozen_string_literal: true

module Ai
  module Autonomy
    module Sensors
      class PeerAgentSensor < Base
        def sensor_type
          "peer_agent"
        end

        def collect
          observations = []

          # Check for failed peer executions that might need help
          failed_peers = recent_failed_peer_executions
          failed_peers.each do |peer|
            obs = build_observation(
              title: "Peer agent #{peer[:agent_name]} has #{peer[:failure_count]} recent failures",
              observation_type: "alert",
              severity: peer[:failure_count] > 5 ? "warning" : "info",
              data: peer,
              requires_action: false,
              expires_in: 2.hours
            )
            observations << obs if obs
          end

          # Check for pending A2A tasks waiting for this agent
          pending_tasks = pending_a2a_tasks
          pending_tasks.each do |task|
            obs = build_observation(
              title: "Pending A2A task from #{task[:from_agent_name]}: #{task[:description]}",
              observation_type: "request",
              severity: "info",
              data: task,
              requires_action: true,
              expires_in: 4.hours
            )
            observations << obs if obs
          end

          observations.compact
        end

        private

        def recent_failed_peer_executions
          account.ai_agents
            .where.not(id: agent.id)
            .where(status: "active")
            .filter_map do |peer|
              failure_count = Ai::AgentExecution
                .where(ai_agent_id: peer.id, status: "failed")
                .where("created_at >= ?", 1.hour.ago)
                .count

              next if failure_count < 3

              { agent_id: peer.id, agent_name: peer.name, failure_count: failure_count }
            end
        rescue StandardError
          []
        end

        def pending_a2a_tasks
          Ai::A2aTask
            .where(account_id: account.id, target_agent_id: agent.id, status: "pending")
            .where("created_at >= ?", 24.hours.ago)
            .limit(5)
            .map do |task|
              {
                task_id: task.id,
                from_agent_id: task.source_agent_id,
                from_agent_name: task.source_agent&.name,
                description: task.description&.truncate(200)
              }
            end
        rescue StandardError
          []
        end
      end
    end
  end
end
