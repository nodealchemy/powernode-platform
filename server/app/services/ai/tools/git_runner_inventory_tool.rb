# frozen_string_literal: true

module Ai
  module Tools
    # GitRunner inventory over MCP (IMP-5df6d59aaa5c): enumerate the account's
    # Devops::GitRunner rows and prune the stale fleet-builder backlog — the
    # capability gap hit on 2026-08-07 when 51 phantom "offline" runners could
    # not be listed or cleared over MCP and cleanup fell back to a hand-run
    # rails-runner script.
    #
    # Pruning delegates to Devops::RunnerPruneService, which derives staleness
    # from LOCAL signals only (never an upstream listing — see the revert
    # be18ecebc) and refuses anything a live lease or dispatch still touches.
    # Dry-run is the default: a caller sees the count + sample first and must
    # re-invoke with apply: true to delete (bulk-op confirmation shape).
    #
    # Permissions: class-level git.runners.read gates both actions; the apply
    # path additionally requires git.runners.manage on the calling user, or an
    # explicit internal: caller. A nil-user non-internal caller (instance
    # principal shape) is refused — and "prune_stale_git_runners" also matches
    # the Mcp::Principal destructive-name overlay, so instance principals are
    # denied by name regardless of grants.
    class GitRunnerInventoryTool < BaseTool
      REQUIRED_PERMISSION = "git.runners.read"

      SAMPLE_LIMIT = 4

      def self.definition
        {
          name: "git_runner_inventory",
          description: "List Devops::GitRunner inventory and prune stale fleet-builder rows",
          parameters: {
            action: { type: "string", required: true,
                      description: "list_git_runners | prune_stale_git_runners" },
            status: { type: "string", required: false,
                      description: "list filter: online | offline | busy" },
            search: { type: "string", required: false,
                      description: "list filter: name substring (ILIKE)" },
            limit:  { type: "integer", required: false,
                      description: "list page size (default 50, max 200)" },
            apply:  { type: "boolean", required: false,
                      description: "prune only: actually delete (default false = dry run). " \
                                   "Requires git.runners.manage." },
            reason: { type: "string", required: false,
                      description: "prune only: optional operator note recorded in the log line" }
          }
        }
      end

      def self.action_definitions
        base = definition
        {
          "list_git_runners" => {
            description: "List the account's Devops::GitRunner rows (inventory: name, status, " \
                         "scope, last_seen_at, job counts) with status totals. Read-only.",
            parameters: base[:parameters].slice(:status, :search, :limit)
          },
          "prune_stale_git_runners" => {
            description: "Prune stale fleet-* GitRunner rows from LOCAL signals only (never an " \
                         "upstream listing). Excludes runners held by a non-terminal lease, " \
                         "referenced by a non-terminal dispatch, or lease-referenced by id. " \
                         "Dry-run by default — returns the count + sample; re-invoke with " \
                         "apply: true (git.runners.manage) to delete.",
            parameters: base[:parameters].slice(:apply, :reason)
          }
        }
      end

      def call(params)
        case params[:action].to_s
        when "list_git_runners"        then list_runners(params)
        when "prune_stale_git_runners" then prune_runners(params)
        else
          error_result("Unknown action: #{params[:action].inspect}")
        end
      end

      private

      def list_runners(params)
        runners = Devops::GitRunner.where(account: @account)
        runners = runners.where(status: params[:status]) if params[:status].present?
        if params[:search].present?
          runners = runners.where("name ILIKE ?", "%#{ActiveRecord::Base.sanitize_sql_like(params[:search])}%")
        end
        limit = (params[:limit] || 50).to_i.clamp(1, 200)

        all = Devops::GitRunner.where(account: @account)
        success_result(
          runners: runners.order(created_at: :desc).limit(limit).map { |r| serialize_runner(r) },
          stats: {
            total: all.count,
            online: all.online.count,
            offline: all.offline.count,
            busy: all.busy.count
          }
        )
      end

      def prune_runners(params)
        apply = ActiveModel::Type::Boolean.new.cast(params[:apply])
        service = Devops::RunnerPruneService.new(account: @account)

        unless apply
          preview = service.preview
          return success_result(prune_payload(preview).merge(
            dry_run: true,
            message: "DRY RUN — re-invoke with apply: true to delete these #{preview.candidates.size} row(s)."
          ))
        end

        # Destructive half: per-action escalation beyond the class-level read
        # permission. Fails closed for a nil-user caller unless explicitly
        # internal (IMP-9030413bc292 posture — nil user never implies trusted).
        unless @internal || @user&.has_permission?("git.runners.manage")
          return error_result("prune apply requires git.runners.manage")
        end

        result = service.apply!
        Rails.logger.info(
          "[GitRunnerInventoryTool] pruned #{result.deleted_count} stale runner row(s) " \
          "(cleared #{result.cleared_dispatch_pointers} dispatch pointer(s))" \
          "#{params[:reason].present? ? " reason=#{params[:reason]}" : ''}"
        )
        success_result(prune_payload(result).merge(
          dry_run: false,
          deleted_count: result.deleted_count,
          cleared_dispatch_pointers: result.cleared_dispatch_pointers
        ))
      end

      def prune_payload(result)
        names = result.candidates.map(&:name)
        {
          total: result.total,
          fleet_total: result.fleet_total,
          candidate_count: result.candidates.size,
          sample: (names.first(SAMPLE_LIMIT - 1) + (names.size >= SAMPLE_LIMIT ? names.last(1) : [])).uniq,
          retained: {
            live_lease_names: result.retained[:live_lease_names],
            active_dispatch_runner_count: result.retained[:active_dispatch_runner_ids].size,
            lease_referenced_runner_count: result.retained[:lease_referenced_runner_ids].size
          }
        }
      end

      def serialize_runner(runner)
        {
          id: runner.id,
          name: runner.name,
          status: runner.status,
          busy: runner.busy,
          runner_scope: runner.runner_scope,
          labels: runner.labels,
          last_seen_at: runner.last_seen_at,
          total_jobs_run: runner.total_jobs_run,
          created_at: runner.created_at
        }
      end
    end
  end
end
