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

    # Gated CREATE. Wraps `gate!` with the sequence every gated create needs:
    # validate the caller's unsaved candidate, gate, then — on :proceed only —
    # re-find the row the EXECUTOR wrote and render it at 201.
    #
    #   gate_create!(
    #     candidate:     candidate,          # unsaved, built by the caller
    #     scope:         @parent.widgets,    # where the executor's row lands
    #     result_key:    :widget_id,         # key the executor returns it under
    #     response_key:  :widget,            # key the 201 body renders it under
    #     serializer:    ->(w) { serialize_full(w) },
    #     action_category: "widgets.create",
    #     executor_class:  "Widgets::Executors::Create",
    #     params:          { parent_id: @parent.id, attributes: attrs },
    #     source_type: "Widget::Parent", source_id: @parent.id,
    #     description: "Add widget #{candidate.name}"
    #   )
    #
    # ORDERING INVARIANT — validation runs BEFORE the gate, and `gate!` is
    # reached only for a candidate that could actually be written. An invalid
    # payload therefore keeps its field-level 422 and opens NO
    # Ai::DeferredOperation (nor the approval request that would hang off it)
    # for an operation that could never have run.
    #
    # Do NOT move the validation into `on_proceed`: `gate!` does not call
    # `on_proceed` on :pending, so an invalid payload would be parked in a
    # deferred operation and fail at approval time, in front of an approver,
    # instead of failing in front of the caller who could fix it. Both
    # orderings answer identically on every VALID request, so the guards are
    # necessarily row-level — spec/controllers/concerns/ai/gated_actions_create_spec.rb
    # here, plus each adopter's "opens no gate row for an invalid payload"
    # request example.
    #
    # The caller keeps what is genuinely per-resource: how the candidate is
    # built (tenancy merge, any pre-validation ceremony the executor mirrors)
    # and what `params:` the gate replays. `description:` is a caller param by
    # operator direction — IMP-4a5094b22df0 owns any derivation of it.
    #
    # @param candidate [#valid?] unsaved record, never written by this helper —
    #   the executor's create stays the sole authority.
    # @param scope [#find] relation the executor's row is re-found through.
    # @param result_key [Symbol] key under `result.result[:data]` holding its id.
    # @param response_key [Symbol] key the serialized row renders under.
    # @param serializer [#call] receives the re-found record, returns the body.
    def gate_create!(candidate:, scope:, result_key:, response_key:, serializer:,
                     action_category:, executor_class:, params:,
                     source_type: nil, source_id: nil, description: nil)
      return render_validation_error(candidate) unless candidate.valid?

      gate!(
        action_category: action_category,
        executor_class: executor_class,
        params: params,
        source_type: source_type,
        source_id: source_id,
        description: description,
        on_proceed: lambda { |result|
          created = scope.find(result.result&.dig(:data, result_key))
          render_success({ response_key => serializer.call(created) }, status: :created)
        }
      )
    end
  end
end
