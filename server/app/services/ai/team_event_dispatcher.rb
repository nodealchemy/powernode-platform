# frozen_string_literal: true

module Ai
  # Iterates all active teams in the signal's account and dispatches each
  # team that has opted in to the signal's key via its
  # activation_rules.on_event subscription list.
  #
  # Invoked by Ai::StigmergicSignal#trigger_subscribed_teams (after_create
  # _commit). Failures in one team's dispatch never block other teams or
  # propagate up — each is wrapped in a rescue with structured logging.
  class TeamEventDispatcher
    def self.dispatch(signal)
      new(signal).dispatch
    end

    def initialize(signal)
      @signal = signal
    end

    def dispatch
      return [] unless @signal&.account_id.present? && @signal.signal_key.present?

      teams = ::Ai::AgentTeam.where(account_id: @signal.account_id, status: "active")
      dispatched = []

      teams.find_each do |team|
        next unless team.responsive_to_signal?(@signal)

        begin
          exec = team.dispatch_for_event!(@signal)
          dispatched << { team_id: team.id, team_name: team.name, execution_id: exec.respond_to?(:execution_id) ? exec.execution_id : exec&.id }
          Rails.logger.info(
            "[TeamEventDispatcher] signal=#{@signal.signal_key} strength=#{@signal.strength.round(3)} " \
            "→ team=#{team.name} execution=#{exec.respond_to?(:execution_id) ? exec.execution_id : exec&.id}"
          )
        rescue StandardError => e
          Rails.logger.error(
            "[TeamEventDispatcher] dispatch failed signal=#{@signal.signal_key} team=#{team.name}: #{e.class}: #{e.message}"
          )
        end
      end

      dispatched
    end
  end
end
