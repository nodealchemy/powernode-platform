# frozen_string_literal: true

class ChangeAiAgentVersionToString < ActiveRecord::Migration[8.0]
  def up
    # Convert existing integer versions to semantic version strings
    AiAgent.find_each do |agent|
      semantic_version = "1.0.#{agent.version}"
      agent.update_column(:version, semantic_version)
    rescue StandardError => e
      Rails.logger.warn "Failed to convert version for agent #{agent.id}: #{e.message}"
    end

    # Change column type to string with appropriate constraints
    change_column :ai_agents, :version, :string, limit: 20, null: false, default: '1.0.0'
  end

  def down
    # Convert semantic versions back to integers (extract patch version)
    AiAgent.find_each do |agent|
      integer_version = agent.version.to_s.split('.').last.to_i
      agent.update_column(:version, integer_version)
    rescue StandardError => e
      Rails.logger.warn "Failed to convert version for agent #{agent.id}: #{e.message}"
    end

    # Change column type back to integer
    change_column :ai_agents, :version, :integer, null: false, default: 1
  end
end
