# frozen_string_literal: true

module Ai
  # Core helper concern for controllers that delegate mutating actions through
  # `Ai::AutonomyGate`. Reduces boilerplate at the call site to a single
  # `gate!(...)` invocation that handles all three branches (proceed/pending/
  # blocked) and renders the right response.
  #
  # Lives in core (server/app/controllers/concerns/ai/) so any extension or
  # core controller can `include ::Ai::GatedActions`. The original
  # `System::GatedActions` is a thin alias retained for the system extension's
  # SDWAN controllers.
  #
  # Usage:
  #
  #   def destroy
  #     gate!(
  #       action_category: "sdwan.network_delete",
  #       executor_class: "Sdwan::Executors::DeleteNetwork",
  #       params: { network_id: @network.id },
  #       source_type: "Sdwan::Network",
  #       source_id: @network.id,
  #       description: "Delete SDWAN network #{@network.name}",
  #       on_proceed: ->(result) { render_success(deleted: true, id: @network.id) }
  #     )
  #   end
  module GatedActions
    extend ActiveSupport::Concern

    def gate!(action_category:, executor_class:, params:, source_type: nil, source_id: nil,
              description: nil, on_proceed: nil)
      result = ::Ai::AutonomyGate.evaluate(
        action_category: action_category,
        executor_class: executor_class,
        params: params,
        account: current_account,
        requested_by: current_user,
        source_type: source_type,
        source_id: source_id,
        description: description
      )

      case result.decision
      when :proceed
        if on_proceed
          on_proceed.call(result)
        else
          render_success(data: result.result&.dig(:data) || {})
        end
      when :pending
        render_pending_approval(result.deferred_operation,
                                message: "Approval required: #{action_category}")
      when :blocked
        render_error(result.error || "Action blocked by policy",
                     status: :unprocessable_content)
      end
    end
  end
end
