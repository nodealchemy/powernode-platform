# frozen_string_literal: true

# TeamExecutionChannel - Real-time team execution monitoring
#
# Subscribes to execution updates for a specific agent team.
# Events: execution_started, execution_progress, member_completed,
#         execution_completed, execution_failed
#
class TeamExecutionChannel < ApplicationCable::Channel
  def subscribed
    return reject unless current_user
    return reject unless params[:team_id]

    team_id = params[:team_id]
    @team = Ai::AgentTeam.find_by(id: team_id, account_id: current_user.account_id)

    return reject unless @team

    stream_from "team_execution:#{team_id}"

    transmit({
      type: "subscription.confirmed",
      channel: "team_execution",
      team_id: team_id,
      timestamp: Time.current.iso8601
    })
  end

  def unsubscribed
    Rails.logger.info "[TeamExecutionChannel] User #{current_user&.id} unsubscribed"
  end

  # Handle upstream commands from clients (pause, resume, cancel, redirect)
  def receive(data)
    command = data["action"]
    execution_id = data["execution_id"]

    return unless command.present? && execution_id.present?

    execution = @team.team_executions.find_by(id: execution_id)
    return transmit_error("Execution not found") unless execution
    return transmit_error("Execution is not active") unless execution.active?

    case command
    when "pause"
      execution.update!(control_signal: "pause")
    when "resume"
      execution.update!(control_signal: nil) if execution.control_signal == "pause"
    when "cancel"
      execution.update!(control_signal: "cancel")
    when "redirect"
      instructions = data["instructions"] || {}
      execution.update!(control_signal: "redirect", redirect_instructions: instructions)
    else
      return transmit_error("Unknown command: #{command}")
    end

    transmit({
      type: "command_acknowledged",
      command: command,
      execution_id: execution_id,
      timestamp: Time.current.iso8601
    })
  rescue StandardError => e
    Rails.logger.warn "[TeamExecutionChannel] Command failed: #{e.message}"
    transmit_error(e.message)
  end

  private

  def transmit_error(message)
    transmit({
      type: "command_error",
      error: message,
      timestamp: Time.current.iso8601
    })
  end

  class << self
    def broadcast_to_team(team_id, event_type, payload = {})
      ActionCable.server.broadcast(
        "team_execution:#{team_id}",
        {
          type: event_type,
          team_id: team_id,
          **payload,
          timestamp: Time.current.iso8601
        }
      )
    end
  end
end
