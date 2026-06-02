# frozen_string_literal: true

# Shared mission-reporting helpers for AI mission-phase jobs (plan, analyze,
# execute, test, deploy, merge, review). Every phase job patches the mission
# record on /api/v1/ai/missions/:id; report_failure was duplicated verbatim
# across all seven. report_mission_status generalises it so a phase job can
# report any status (not only failure) through one place.
#
# Depends on AiJobsConcern/BaseJob#backend_api_patch and #log_warn, so include
# it in mission-phase jobs that also include AiJobsConcern.
module MissionReportingConcern
  extend ActiveSupport::Concern

  private

  # Patch the mission's status, with an optional error_message (omitted when nil).
  def report_mission_status(mission_id, status, error_message: nil)
    backend_api_patch("/api/v1/ai/missions/#{mission_id}", {
      mission: { status: status, error_message: error_message }.compact
    })
  rescue StandardError => e
    log_warn("Failed to report mission status", mission_id: mission_id, status: status, error: e.message)
  end

  # Convenience: mark the mission failed with an error message.
  def report_failure(mission_id, error_message)
    report_mission_status(mission_id, 'failed', error_message: error_message)
  end
end
