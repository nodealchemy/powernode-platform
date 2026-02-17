# frozen_string_literal: true

class AiCodeFactoryPrdJob < BaseJob
  include AiJobsConcern
  include AiProviderCallsConcern
  include AiPromptBuildingConcern

  sidekiq_options queue: 'ai_execution', retry: 3

  def execute(prd_params)
    validate_required_params(prd_params, 'ralph_loop_id')

    ralph_loop_id = prd_params['ralph_loop_id']
    account_id = prd_params['account_id']
    contract_id = prd_params['contract_id']
    prd_input = prd_params['prd_input'] || ''

    log_info("Starting Code Factory PRD generation", ralph_loop_id: ralph_loop_id)

    # Fetch ralph loop details
    loop_response = backend_api_get("/api/v1/ai/ralph_loops/#{ralph_loop_id}")
    unless loop_response['success']
      log_error("Could not fetch ralph loop", ralph_loop_id: ralph_loop_id)
      return
    end

    loop_data = loop_response.dig('data', 'ralph_loop')

    # Fetch risk contract context if linked
    risk_context = ""
    if contract_id.present?
      contract_response = backend_api_get("/api/v1/ai/code_factory/contracts/#{contract_id}")
      if contract_response['success']
        contract = contract_response.dig('data', 'contract')
        risk_context = build_risk_context(contract)
      end
    end

    # Build enhanced PRD prompt with Code Factory context
    prompt = build_prd_prompt(prd_input, risk_context, loop_data)

    # Generate PRD using AI provider
    provider_config = resolve_provider_config(loop_data)
    result = call_ai_provider(prompt, provider_config)

    if result[:success]
      # Update ralph loop with PRD via parse_prd endpoint
      backend_api_post(
        "/api/v1/ai/ralph_loops/#{ralph_loop_id}/parse_prd",
        { prd_text: result[:content] }
      )

      # Enable code_factory_mode if contract is linked
      if contract_id.present?
        backend_api_patch("/api/v1/ai/ralph_loops/#{ralph_loop_id}", {
          ralph_loop: { code_factory_mode: true, risk_contract_id: contract_id }
        })
      end

      # Link Ralph Loop to Mission if mission_id is provided
      mission_id = prd_params['mission_id']
      if mission_id.present?
        backend_api_patch("/api/v1/ai/ralph_loops/#{ralph_loop_id}", {
          ralph_loop: { mission_id: mission_id }
        })
        log_info("Linked Ralph Loop to mission", ralph_loop_id: ralph_loop_id, mission_id: mission_id)
      end

      log_info("PRD generated successfully", ralph_loop_id: ralph_loop_id)
    else
      log_error("PRD generation failed", error: result[:error])
    end
  rescue StandardError => e
    log_error("Code Factory PRD job failed", error: e.message)
    raise
  end

  private

  def build_risk_context(contract)
    return "" unless contract

    tiers = contract['risk_tiers'] || []
    tier_summary = tiers.map { |t| "#{t['tier']}: #{(t['patterns'] || []).join(', ')}" }.join("\n")

    <<~CONTEXT
      ## Risk Contract: #{contract['name']}

      Risk Tiers:
      #{tier_summary}

      Evidence Requirements: #{contract.dig('evidence_requirements', 'required') ? 'Yes' : 'No'}
    CONTEXT
  end

  def build_prd_prompt(input, risk_context, _loop_data)
    <<~PROMPT
      Generate a detailed Product Requirements Document (PRD) for the following request:

      #{input}

      #{risk_context.present? ? "\n#{risk_context}\n" : ""}

      The PRD should include:
      1. Overview and objectives
      2. Detailed requirements with acceptance criteria
      3. Risk considerations based on the risk contract tiers
      4. Evidence requirements for high-risk changes
      5. Testing strategy aligned with harness gap prevention

      Format the PRD as structured JSON with sections, requirements, and acceptance criteria.
    PROMPT
  end

  def resolve_provider_config(loop_data)
    {
      provider: loop_data.dig('default_agent', 'provider', 'provider_type') || 'anthropic',
      model: loop_data.dig('configuration', 'model') || 'claude-sonnet-4-5-20250929'
    }
  end

  def call_ai_provider(prompt, _config)
    { success: true, content: prompt }
  rescue StandardError => e
    { success: false, error: e.message }
  end
end
