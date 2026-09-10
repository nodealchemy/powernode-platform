# frozen_string_literal: true

module Ai
  module Tools
    # SCHEDULES, READ-ONLY (audit remedy 18).
    #
    # The audit found ZERO of 634 actions matching `schedule` or `cron`. An
    # operations agent asked "what runs on a timer here, and did the last run
    # fail" had no way to answer.
    #
    # ── WHICH SCHEDULE FAMILY, AND WHY ONLY ONE ─────────────────────────────
    #
    # The platform has four schedule-shaped surfaces and they are not
    # interchangeable. This tool covers exactly one — `Devops::Schedule`, the
    # pipeline scheduler — because it is the only one that is a first-class CRUD
    # surface with its own controller, guarded by a single unambiguous
    # permission pair (`devops.schedules.read` / `.write`), whose columns carry
    # no secret material.
    #
    # The other three are deliberately NOT here, each for its own reason:
    #
    #   Devops::GitPipelineSchedule  repo-scoped and provider-coupled; its
    #                                token lives on a credential row one hop
    #                                away, so a careless serializer reaches it
    #   ScheduledTask (maintenance)  not a model surface but a filtered view,
    #                                behind a six-way permission OR that a
    #                                single-name tool gate cannot express; its
    #                                `parameters` jsonb is unvalidated
    #   Ai::ScheduledMessage         has NO permission check at all — authority
    #                                is conversation ownership — and its columns
    #                                are arbitrary user prose
    #
    # Each of those needs its own gate decision. Shipping one verb that quietly
    # unions all four would have inherited the weakest of the four gates, which
    # is how a read surface becomes a leak.
    class ScheduleReadTool < BaseTool
      REQUIRED_PERMISSION = "devops.schedules.read"

      ACTION_PERMISSIONS = {
        "list_schedules" => "devops.schedules.read",
        "get_schedule" => "devops.schedules.read"
      }.freeze

      declare_action "list_schedules", mutating: false
      declare_action "get_schedule", mutating: false

      def self.definition
        {
          name: "schedule_read",
          description: "Read-only view of the account's pipeline schedules: cron expression, timezone, " \
                       "whether they are active, and when each last ran and next runs.",
          parameters: { type: "object", properties: {} }
        }
      end

      def self.action_definitions
        {
          "list_schedules" => {
            description: "List this account's pipeline schedules with their cron expression, timezone, " \
                         "active flag, last run and next due time. Covers Devops::Schedule only — the " \
                         "git-pipeline, maintenance and scheduled-message families are separate surfaces " \
                         "with separate gates. Requires devops.schedules.read.",
            parameters: {
              pipeline_id: { type: "string", required: false, description: "Filter to one pipeline" },
              active_only: { type: "boolean", required: false, description: "Only schedules with is_active true" },
              **PAGINATION_PARAMETERS
            }
          },
          "get_schedule" => {
            description: "One schedule with its pipeline and its declared inputs. Requires devops.schedules.read.",
            parameters: {
              id: { type: "string", required: true, description: "Schedule id (must belong to this account's pipelines)" }
            }
          }
        }
      end

      def call(params)
        action = params[:action].to_s
        return error_result("permission denied: #{required_perm_for(action)} required") unless action_permitted?(action)

        case action
        when "list_schedules" then list_schedules(params)
        when "get_schedule"   then get_schedule(params)
        else error_result("Unknown action: #{action}")
        end
      end

      private

      def required_perm_for(action)
        ACTION_PERMISSIONS[action] || REQUIRED_PERMISSION
      end

      def action_permitted?(action)
        return true if internal?
        return true if instance_authorized?
        return false unless user.respond_to?(:has_permission?)

        user.has_permission?(required_perm_for(action)) == true
      end

      # `devops_schedules` carries NO account_id — tenancy comes from the
      # pipeline it belongs to. Scoping on the schedule row alone would have
      # returned every account's schedules, so this mirrors the REST
      # controller's join exactly (schedules_controller.rb:16-18).
      def schedules
        ::Devops::Schedule.joins(:pipeline)
                          .where(devops_pipelines: { account_id: account.id })
                          .includes(:pipeline)
      end

      def list_schedules(params)
        scope = schedules
        scope = scope.where(devops_pipeline_id: params[:pipeline_id].to_s) if params[:pipeline_id].present?
        scope = scope.where(is_active: true) if truthy?(params[:active_only])

        paginated_result(:schedules, scope, params, sort: :id, direction: :asc) { |row| serialize_schedule(row) }
      end

      def get_schedule(params)
        row = schedules.find_by(id: params[:id].to_s)
        return error_result("schedule not found in this account") unless row

        success_result(
          schedule: serialize_schedule(row).merge(
            # The pipeline's declared inputs for this schedule. Free-form and
            # caller-authored, so it is on the DETAIL verb only — a list of 200
            # schedules should not spray whatever anyone pasted into an input.
            inputs: row.inputs,
            created_at: iso(row.created_at),
            updated_at: iso(row.updated_at)
          )
        )
      end

      def serialize_schedule(row)
        {
          id: row.id,
          name: row.name,
          cron_expression: row.cron_expression,
          timezone: row.timezone,
          is_active: row.is_active,
          last_run_at: iso(row.last_run_at),
          next_run_at: iso(row.next_run_at),
          pipeline: row.pipeline && { id: row.pipeline.id, name: row.pipeline.name }
        }
      end

      def truthy?(value)
        value == true || value.to_s == "true"
      end

      def iso(value)
        value.respond_to?(:iso8601) ? value.iso8601 : value
      end
    end
  end
end
