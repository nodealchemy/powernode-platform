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

    # @param on_blocked [#call, nil] receives the Result when the gate returns
    #   :blocked. Defaults to the generic 422. #gate_update! supplies one so an
    #   executor's ActiveRecord::RecordInvalid keeps its field-level errors
    #   instead of arriving as "Gate evaluation failed" (IMP-1836bb0021b1).
    def gate!(action_category:, executor_class:, params:, source_type: nil, source_id: nil,
              description: nil, on_proceed: nil, on_blocked: nil)
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
        if on_blocked
          on_blocked.call(result)
        else
          render_error(result.error || "Action blocked by policy",
                       status: :unprocessable_content)
        end
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
    # Two consequences of this being a method call rather than an inline block,
    # neither observable for the callers migrated onto it but both worth
    # knowing before adopting:
    #
    #   * every argument is evaluated BEFORE the validation runs, so a
    #     `description:` interpolating an attribute that a `before_validation`
    #     would normalise reads the pre-normalised value;
    #   * `scope:` is likewise bound up front, so it cannot be derived from
    #     state the executor produces (`scope: @parent.reload.widgets` reloads
    #     before the executor runs, not after).
    #
    # @param candidate [#valid?] unsaved record, never written by this helper —
    #   the executor's create stays the sole authority.
    # @param scope [#find] relation or model the executor's row is re-found
    #   through — anything answering `#find`.
    # @param result_key [Symbol] key under `result.result[:data]` holding its
    #   id. A mismatch here surfaces as `RecordNotFound` — a 404 over an
    #   operation that actually SUCCEEDED — so it is worth a spec.
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

    # Gated UPDATE — the sibling of #gate_create!, and the same ordering
    # invariant read from the other end (IMP-1836bb0021b1).
    #
    #   gate_update!(
    #     record:       @network,
    #     attributes:   attrs,
    #     response_key: :network,
    #     serializer:   ->(n) { serialize_network_full(n) },
    #     action_category: "sdwan.network_update",
    #     executor_class:  "Sdwan::Executors::UpdateNetwork",
    #     params:          { network_id: @network.id, attributes: attrs },
    #     source_type: "Sdwan::Network", source_id: @network.id,
    #     description: "Update SDWAN network '#{attrs['name'] || @network.name}'"
    #   )
    #
    # THE SEQUENCE, which was hand-inlined at three SDWAN call sites and about
    # to be copied to more:
    #
    #   1. assign the incoming attributes to the record IN MEMORY and validate.
    #      An unsaveable payload keeps its field-level 422 and opens no audit
    #      row for an operation that could never run — the same reason
    #      #gate_create! validates its candidate first, argued at length there.
    #   2. RELOAD, discarding those in-memory changes. Nothing may reach the row
    #      except through the executor; step 1 is a dry run, not a write. Miss
    #      this and an un-gated change rides along on any later save of the
    #      instance — including the serializer's, on the :proceed branch.
    #   3. gate!, whose executor performs the only real write.
    #
    # A VALIDATION FAILURE IS NOT A POLICY BLOCK. Ai::AutonomyGate#evaluate
    # rescues StandardError and returns :blocked, so an executor raising
    # RecordInvalid — a race against step 1, or a DB constraint no model
    # validation mirrors — used to reach the client as a generic
    # "Gate evaluation failed" 422 with no details.errors, strictly less than
    # the plain inline update it replaced. The :blocked branch now re-renders
    # that case as field errors, off the RecordInvalid's OWN record so the
    # messages are the ones the write actually produced.
    #
    # DOUBLE VALIDATION IS ACCEPTED, deliberately. Step 1 and the executor's
    # update! run the same uniqueness/format SELECTs, and on the :pending path
    # step 1's work is thrown away and redone at approval time. The alternative
    # — telling the executor to skip validation because the controller already
    # checked — makes the executor stop being the sole authority over its own
    # write and depends on a check that ran, on the deferred path, hours
    # earlier against a row that may since have changed. The redundant SELECTs
    # are the price of validating before opening an audit row, which is the
    # invariant this helper exists to hold.
    #
    # `description:` stays a CALLER argument rather than being derived here:
    # IMP-4a5094b22df0 owns approval-card derivation, and #gate_create! records
    # the same boundary. Callers building one for a rename must read the
    # INCOMING attributes — every argument is evaluated before step 1, so an
    # interpolation of `record.name` is the pre-change value.
    #
    # @param record [ActiveRecord::Base] the persisted row being updated. Never
    #   saved here; assigned, validated, and reloaded.
    # @param attributes [Hash] the permitted incoming attributes.
    # @param response_key [Symbol] key the serialized row renders under.
    # @param serializer [#call] receives the reloaded record, returns the body.
    def gate_update!(record:, attributes:, response_key:, serializer:,
                     action_category:, executor_class:, params:,
                     source_type: nil, source_id: nil, description: nil)
      record.assign_attributes(attributes)
      return render_validation_error(record) unless record.valid?

      record.reload

      gate!(
        action_category: action_category,
        executor_class: executor_class,
        params: params,
        source_type: source_type,
        source_id: source_id,
        description: description,
        on_proceed: ->(_result) { render_success(response_key => serializer.call(record.reload)) },
        on_blocked: lambda { |result|
          invalid = result.exception
          if invalid.is_a?(::ActiveRecord::RecordInvalid)
            render_validation_error(invalid.record)
          else
            render_error(result.error || "Action blocked by policy",
                         status: :unprocessable_content)
          end
        }
      )
    end
  end
end
