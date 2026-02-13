# frozen_string_literal: true

class AiGuardrailEvaluationJob < BaseJob
  include AiJobsConcern

  sidekiq_options queue: "ai_agents", retry: 1

  EVAL_TIMEOUT = 10 # seconds

  def execute(params = {})
    validate_required_params(params, "content", "rail_type", "mode", "account_id")

    content = params["content"]
    rail_type = params["rail_type"]
    mode = params["mode"]
    account_id = params["account_id"]
    conversation_id = params["conversation_id"]

    log_info("Starting guardrail evaluation",
             rail_type: rail_type, mode: mode, account_id: account_id,
             content_length: content.length)

    verdict = evaluate_via_backend(
      content: content,
      rail_type: rail_type,
      account_id: account_id
    )

    case mode
    when "blocking"
      handle_blocking_verdict(verdict, account_id: account_id, conversation_id: conversation_id)
    when "shadow"
      handle_shadow_verdict(verdict, account_id: account_id, rail_type: rail_type)
    else
      log_warn("Unknown guardrail evaluation mode: #{mode}")
    end

    verdict
  end

  private

  def evaluate_via_backend(content:, rail_type:, account_id:)
    with_ai_provider_circuit_breaker("guardrail_eval") do
      response = backend_api_client.post(
        "/api/v1/internal/ai/guardrails/evaluate",
        {
          content: content,
          rail_type: rail_type,
          account_id: account_id,
          timeout: EVAL_TIMEOUT
        }
      )

      if response.success?
        body = JSON.parse(response.body)
        log_info("Guardrail evaluation complete",
                 rail_type: rail_type, verdict: body["verdict"], confidence: body["confidence"])
        body
      else
        log_error("Guardrail evaluation API failed: #{response.status}")
        { "verdict" => "error", "confidence" => 0.0, "error" => "API returned #{response.status}" }
      end
    end
  rescue CircuitBreaker::CircuitOpenError => e
    log_warn("Circuit breaker open for guardrail evaluation: #{e.message}")
    { "verdict" => "error", "confidence" => 0.0, "error" => "circuit_breaker_open" }
  end

  def handle_blocking_verdict(verdict, account_id:, conversation_id:)
    log_info("Blocking verdict",
             verdict: verdict["verdict"], conversation_id: conversation_id)

    return unless conversation_id

    # Broadcast verdict to waiting frontend via backend API → ActionCable
    with_backend_api_circuit_breaker do
      backend_api_client.post(
        "/api/v1/internal/ai/guardrails/broadcast_verdict",
        {
          account_id: account_id,
          conversation_id: conversation_id,
          verdict: verdict
        }
      )
    end
  rescue StandardError => e
    log_error("Failed to broadcast blocking verdict: #{e.message}")
  end

  def handle_shadow_verdict(verdict, account_id:, rail_type:)
    log_info("Shadow verdict (audit only)",
             verdict: verdict["verdict"], rail_type: rail_type)

    # Store result in audit log without blocking
    with_backend_api_circuit_breaker do
      backend_api_client.post(
        "/api/v1/internal/ai/guardrails/audit_log",
        {
          account_id: account_id,
          rail_type: rail_type,
          verdict: verdict,
          mode: "shadow"
        }
      )
    end
  rescue StandardError => e
    log_error("Failed to record shadow verdict audit: #{e.message}")
  end
end
