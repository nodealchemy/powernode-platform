# frozen_string_literal: true

class AiMissionPlanJob < BaseJob
  include AiJobsConcern

  sidekiq_options queue: 'ai_execution', retry: 3

  def execute(params)
    validate_required_params(params, 'mission_id', 'account_id')

    mission_id = params['mission_id']
    log_info("Starting mission planning", mission_id: mission_id)

    # Fetch mission
    mission_response = backend_api_get("/api/v1/ai/missions/#{mission_id}")
    unless mission_response['success']
      report_failure(mission_id, "Could not fetch mission details")
      return
    end

    mission = mission_response.dig('data', 'mission')

    # Guard: abort if mission has moved past the planning phase (stale retry)
    unless mission['current_phase'] == 'planning'
      log_warn("Stale job: mission phase is #{mission['current_phase']}, expected planning", mission_id: mission_id)
      return
    end

    selected_feature = mission['selected_feature'] || {}
    objective = mission['objective'] || selected_feature['description'] || ''

    # Create branch for the mission
    branch_name = "mission/#{mission_id[0..7]}-#{selected_feature['title']&.parameterize&.truncate(30, omission: '') || 'feature'}"
    base_branch = mission['base_branch'] || 'main'

    branch_result = backend_api_post("/api/v1/ai/missions/#{mission_id}/create_branch", {
      branch_name: branch_name,
      base_branch: base_branch
    })

    unless branch_result['success']
      log_warn("Branch creation failed, continuing", error: branch_result['error'])
    end

    # Generate PRD by triggering the code factory PRD job flow
    prd_input = build_prd_input(mission, selected_feature, objective)

    prd_result = backend_api_post("/api/v1/ai/missions/#{mission_id}/generate_prd", {
      prd_input: prd_input,
      branch_name: branch_name
    })

    if prd_result['success']
      # Verify ralph_loop was actually created
      verify = backend_api_get("/api/v1/ai/missions/#{mission_id}")
      ralph_loop_id = verify.dig('data', 'mission', 'ralph_loop_id') if verify['success']

      unless ralph_loop_id
        report_failure(mission_id, "PRD generated but failed to create execution loop")
        return
      end

      log_info("Mission planning completed", mission_id: mission_id, ralph_loop_id: ralph_loop_id)
    else
      error_msg = prd_result['error'] || 'Planning failed'
      log_error("Mission planning failed", error: error_msg)
      report_failure(mission_id, error_msg)
    end
  rescue StandardError => e
    log_error("Mission plan job failed", exception: e, mission_id: params['mission_id'])
    report_failure(params['mission_id'], e.message) if params['mission_id']
    raise
  end

  private

  def build_prd_input(mission, selected_feature, objective)
    parts = []
    parts << "## Objective\n#{objective}" if objective.present?
    parts << "## Feature: #{selected_feature['title']}\n#{selected_feature['description']}" if selected_feature['title']
    parts << "## Repository Analysis\n#{(mission['analysis_result'] || {}).to_json}" if mission['analysis_result'].present?
    parts.join("\n\n")
  end

  def report_failure(mission_id, error_message)
    backend_api_patch("/api/v1/ai/missions/#{mission_id}", {
      mission: { status: "failed", error_message: error_message }
    })
  rescue StandardError => e
    log_warn("Failed to report mission failure", error: e.message)
  end
end
