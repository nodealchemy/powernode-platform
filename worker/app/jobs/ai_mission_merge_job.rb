# frozen_string_literal: true

class AiMissionMergeJob < BaseJob
  include AiJobsConcern

  sidekiq_options queue: 'ai_execution', retry: 3

  def execute(params)
    validate_required_params(params, 'mission_id', 'account_id')

    mission_id = params['mission_id']
    log_info("Starting mission merge (PR creation)", mission_id: mission_id)

    mission_response = backend_api_get("/api/v1/ai/missions/#{mission_id}")
    unless mission_response['success']
      report_failure(mission_id, "Could not fetch mission details")
      return
    end

    mission = mission_response.dig('data', 'mission')

    # Guard: abort if mission has moved past the merging phase (stale retry)
    unless mission['current_phase'] == 'merging'
      log_warn("Stale job: mission phase is #{mission['current_phase']}, expected merging", mission_id: mission_id)
      return
    end

    # Create PR via backend service
    pr_result = backend_api_post("/api/v1/ai/missions/#{mission_id}/create_pr", {
      head: mission['branch_name'],
      base: mission['base_branch'] || 'main',
      title: "Mission: #{mission['name']}",
      body: build_pr_body(mission)
    })

    if pr_result['success']
      log_info("PR created for mission", mission_id: mission_id,
               pr_number: pr_result.dig('data', 'pr_number'))

      backend_api_post("/api/v1/ai/missions/#{mission_id}/advance", {
        result: {
          pr_number: pr_result.dig('data', 'pr_number'),
          pr_url: pr_result.dig('data', 'pr_url')
        },
        expected_phase: 'merging'
      })
    else
      error_msg = pr_result['error'] || 'PR creation failed'
      log_error("PR creation failed", error: error_msg)
      report_failure(mission_id, error_msg)
    end
  rescue StandardError => e
    log_error("Mission merge job failed", exception: e, mission_id: params['mission_id'])
    report_failure(params['mission_id'], e.message) if params['mission_id']
    raise
  end

  private

  def build_pr_body(mission)
    parts = []
    parts << "## Mission: #{mission['name']}"
    parts << mission['description'] if mission['description'].present?
    parts << "\n### Objective\n#{mission['objective']}" if mission['objective'].present?

    selected = mission['selected_feature'] || {}
    if selected['title']
      parts << "\n### Feature\n**#{selected['title']}**: #{selected['description']}"
    end

    parts << "\n---\n_Created by Powernode Missions_"
    parts.join("\n")
  end

  def report_failure(mission_id, error_message)
    backend_api_patch("/api/v1/ai/missions/#{mission_id}", {
      mission: { status: "failed", error_message: error_message }
    })
  rescue StandardError => e
    log_warn("Failed to report mission failure", error: e.message)
  end
end
