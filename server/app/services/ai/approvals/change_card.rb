# frozen_string_literal: true

module Ai
  module Approvals
    # The structured "what exactly am I approving" block on a parked tool-call
    # request's card: the exact tool and action, the target, the NEW value and,
    # where the tool can show it to this viewer, the CURRENT value. Read from the
    # request's REDACTED request_data (Ai::SensitiveParams), never from the
    # operation's own params and never rendered into the free-text description,
    # which is where a value would escape the redaction.
    #
    # The tool answers for itself (Ai::Tools::BaseTool.approval_change_card,
    # nil by default), so this names no tool. The class it resolves is bounded to
    # the chokepoint's own hierarchy, as Ai::Executors::DeferredToolCall bounds
    # its replay: a name off a JSONB column is looked up, never called.
    module ChangeCard
      module_function

      # nil for anything that is not a pending parked tool call whose tool offers a card.
      def for(request, viewer:)
        return nil unless request.pending?
        return nil unless request.request_data.to_h.with_indifferent_access[:executor_class].to_s == ::Ai::Executors::DeferredToolCall.name

        params = ::Ai::SensitiveParams.filter(request.request_data.to_h).with_indifferent_access[:params]
        return nil unless params.is_a?(Hash)

        klass = params[:tool_class].to_s.safe_constantize
        return nil unless klass.is_a?(Class) && klass < ::Ai::Tools::BaseTool

        klass.approval_change_card(action: params[:action].to_s, tool_params: params[:tool_params], viewer: viewer)
      end
    end
  end
end
