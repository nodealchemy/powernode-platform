# frozen_string_literal: true

module Ai
  module Provisioning
    # Raised when a provisioning service can resolve NO model id for an
    # account's LLM call.
    #
    # E3 removed the hardcoded `|| "gpt-4"` fallbacks from these services: the
    # model has to match the provider the worker will actually call, so a
    # literal is wrong for every provider but one and 404s against the rest.
    # E3 replaced them with `nil`, which was not an improvement — it was the
    # same failure moved downstream and made harder to read.
    # `WorkerLlmClient#build_payload` ends in `params.compact`, so a nil model
    # is DROPPED from the request; the worker then applies its own
    # `model ||= config["model"]` and otherwise posts `model: null` to the
    # provider. Both call sites rescued the resulting upstream failure into a
    # warn and a nil, one of them under a bare `rescue StandardError`. Nothing
    # anywhere said "this account has no model configured", which is the one
    # thing an operator could act on.
    #
    # A named error makes that state unrepresentable at the boundary. It is
    # raised where the resolution fails and caught where the service has
    # somewhere honest to put it — the brief result for IntentCaptureService,
    # a recorded decline for AdaptationProposerService — never swallowed into a
    # log line.
    class NoModelConfiguredError < StandardError
      REASON = "no_model_configured"

      attr_reader :account_id

      def initialize(account_id: nil, service: nil)
        @account_id = account_id
        super(
          "no model configured for account=#{account_id || 'unknown'}" \
          "#{" (#{service})" if service}: neither the conversation agent nor the " \
          "account's first active credential's provider names one. Set the agent's " \
          "model, or give that provider a default_model / a non-empty supported_models."
        )
      end
    end
  end
end
