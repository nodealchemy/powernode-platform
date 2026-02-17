# frozen_string_literal: true

class AiCodeFactoryTaskGenJob < BaseJob
  include AiJobsConcern

  sidekiq_options queue: 'ai_execution', retry: 3

  def execute(task_gen_params)
    validate_required_params(task_gen_params, 'ralph_loop_id')

    ralph_loop_id = task_gen_params['ralph_loop_id']
    account_id = task_gen_params['account_id']
    prd_json = task_gen_params['prd_json'] || {}

    log_info("Starting Code Factory task generation", ralph_loop_id: ralph_loop_id)

    # Fetch ralph loop with PRD
    loop_response = backend_api_get("/api/v1/ai/ralph_loops/#{ralph_loop_id}")
    unless loop_response['success']
      log_error("Could not fetch ralph loop", ralph_loop_id: ralph_loop_id)
      return
    end

    loop_data = loop_response.dig('data', 'ralph_loop')
    prd = prd_json.present? ? prd_json : (loop_data['prd_json'] || {})

    if prd.empty?
      log_warn("No PRD data available for task generation", ralph_loop_id: ralph_loop_id)
      return
    end

    # Fetch risk contract if in code_factory_mode
    risk_metadata = {}
    if loop_data['code_factory_mode'] && loop_data['risk_contract_id']
      contract_response = backend_api_get("/api/v1/ai/code_factory/contracts/#{loop_data['risk_contract_id']}")
      if contract_response['success']
        contract = contract_response.dig('data', 'contract')
        risk_metadata = build_risk_metadata(contract)
      end
    end

    # Decompose PRD into structured tasks
    tasks = decompose_prd_to_tasks(prd, risk_metadata)

    # Create tasks via RALPH API
    tasks.each_with_index do |task, index|
      task_payload = {
        name: task[:name],
        description: task[:description],
        priority: task[:priority] || index + 1,
        status: 'pending',
        metadata: task[:metadata] || {}
      }

      result = backend_api_post("/api/v1/ai/ralph_loops/#{ralph_loop_id}/tasks", {
        ralph_task: task_payload
      })

      if result['success']
        log_info("Task created", task_name: task[:name], index: index + 1)
      else
        log_warn("Task creation failed", task_name: task[:name],
          error: result.dig('error', 'message'))
      end
    end

    log_info("Task generation completed",
      ralph_loop_id: ralph_loop_id, tasks_created: tasks.size)
  rescue StandardError => e
    log_error("Code Factory task generation failed", error: e.message)
    raise
  end

  private

  def build_risk_metadata(contract)
    tiers = contract['risk_tiers'] || []
    {
      risk_contract_id: contract['id'],
      risk_contract_name: contract['name'],
      tiers: tiers.map { |t| { tier: t['tier'], patterns: t['patterns'] } }
    }
  end

  def decompose_prd_to_tasks(prd, risk_metadata)
    sections = prd['sections'] || prd['requirements'] || []
    tasks = []

    sections.each do |section|
      requirements = section['requirements'] || [section]

      requirements.each do |req|
        task = {
          name: req['title'] || req['name'] || "Task #{tasks.size + 1}",
          description: req['description'] || req['content'] || '',
          priority: req['priority'],
          metadata: {
            prd_section: section['title'] || section['name'],
            acceptance_criteria: req['acceptance_criteria'] || [],
            risk_tier: determine_risk_tier(req, risk_metadata),
            evidence_required: req['evidence_required'] || false
          }
        }

        # Add dependencies if specified
        if req['depends_on'].present?
          task[:metadata][:depends_on] = req['depends_on']
        end

        tasks << task
      end
    end

    tasks
  end

  def determine_risk_tier(requirement, risk_metadata)
    return 'standard' if risk_metadata.empty?

    files = requirement['files'] || requirement['affected_files'] || []
    return 'standard' if files.empty?

    tiers = risk_metadata[:tiers] || []
    highest_tier = 'low'
    tier_priority = { 'low' => 0, 'standard' => 1, 'high' => 2, 'critical' => 3 }

    files.each do |file|
      tiers.each do |tier|
        patterns = tier[:patterns] || []
        patterns.each do |pattern|
          if File.fnmatch(pattern, file, File::FNM_PATHNAME | File::FNM_DOTMATCH)
            if (tier_priority[tier[:tier]] || 0) > (tier_priority[highest_tier] || 0)
              highest_tier = tier[:tier]
            end
          end
        end
      end
    end

    highest_tier
  end
end
