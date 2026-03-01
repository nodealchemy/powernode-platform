# frozen_string_literal: true

module Api
  module V1
    module Internal
      module Ai
        class WorktreeSessionsController < InternalBaseController
          before_action :set_session, except: [:check_timeouts]

          # GET /api/v1/internal/ai/worktree_sessions/:id
          # Returns session data including worktrees and configuration
          def show
            render_success(
              session: @session.session_summary,
              worktrees: @session.worktrees.map(&:worktree_summary),
              merge_operations: @session.merge_operations.by_order.map(&:operation_summary),
              configuration: @session.configuration,
              merge_config: @session.merge_config,
              metadata: @session.metadata
            )
          end

          # POST /api/v1/internal/ai/worktree_sessions/:id/start
          # Transitions session from pending to provisioning
          def start
            @session.start!
            render_success(session: @session.reload.session_summary)
          rescue ActiveRecord::RecordInvalid => e
            render_error(e.message, status: :unprocessable_entity)
          end

          # POST /api/v1/internal/ai/worktree_sessions/:id/activate
          # Transitions session from provisioning to active
          def activate
            @session.activate!
            render_success(session: @session.reload.session_summary)
          rescue ActiveRecord::RecordInvalid => e
            render_error(e.message, status: :unprocessable_entity)
          end

          # POST /api/v1/internal/ai/worktree_sessions/:id/fail_session
          # Marks session as failed with error details
          def fail_session
            @session.fail!(
              error_message: params[:error_message],
              error_code: params[:error_code],
              error_details: params[:error_details]&.to_unsafe_h || {}
            )
            render_success(session: @session.reload.session_summary)
          end

          # POST /api/v1/internal/ai/worktree_sessions/:id/worktrees/:worktree_id/provision
          # Runs the worktree provisioning logic for a single worktree
          def provision_worktree
            worktree = @session.worktrees.find(params[:worktree_id])

            worktree.mark_creating!
            worktree.lock!(reason: "provisioning")

            manager = ::Ai::Git::WorktreeManager.new(repository_path: @session.repository_path)

            result = manager.create_worktree(
              session_id: @session.id,
              branch_suffix: worktree.branch_name.split("/").last,
              base_branch: @session.base_branch,
              base_commit: worktree.base_commit_sha
            )

            worktree.update!(
              worktree_path: result[:worktree_path],
              branch_name: result[:branch_name],
              base_commit_sha: result[:base_commit_sha],
              head_commit_sha: result[:base_commit_sha],
              copied_config_files: result[:copied_config_files]
            )

            worktree.unlock!
            worktree.mark_ready!

            # Run health check
            health = manager.health_check(worktree_path: result[:worktree_path])
            worktree.update!(healthy: health[:healthy], health_message: health[:health_message]) unless health[:healthy]

            # Launch container if configured
            launch_container_if_configured(worktree)

            render_success(
              worktree: worktree.reload.worktree_summary,
              health: health
            )
          rescue ActiveRecord::RecordNotFound
            render_error("Worktree not found", status: :not_found)
          rescue ::Ai::Git::WorktreeManager::WorktreeError => e
            Rails.logger.error "[WorktreeProvisioning] WorktreeManager error: #{e.message}"
            worktree&.unlock! if worktree&.locked?
            worktree&.fail!(error_message: e.message, error_code: "PROVISIONING_FAILED")
            render_error(e.message, status: :unprocessable_entity)
          rescue StandardError => e
            Rails.logger.error "[WorktreeProvisioning] Failed to provision worktree: #{e.message}"
            worktree&.unlock! if worktree&.locked?
            worktree&.fail!(error_message: e.message, error_code: "PROVISIONING_FAILED")
            render_error("Provisioning failed: #{e.message}", status: :unprocessable_entity)
          end

          # POST /api/v1/internal/ai/worktree_sessions/:id/cleanup
          # Releases file locks, removes worktrees, prunes stale references
          def cleanup
            # Release all file locks for this session
            @session.file_locks.delete_all

            manager = ::Ai::Git::WorktreeManager.new(repository_path: @session.repository_path)
            cleaned = 0
            errors = []

            @session.worktrees.where.not(status: "cleaned_up").find_each do |worktree|
              delete_branch = @session.merge_config&.dig("delete_on_merge") != false

              manager.remove_worktree(
                worktree_path: worktree.worktree_path,
                branch_name: delete_branch ? worktree.branch_name : nil,
                force: true
              )

              worktree.mark_cleaned_up!
              cleaned += 1
            rescue StandardError => e
              Rails.logger.warn "[WorktreeCleanup] Failed to clean #{worktree.branch_name}: #{e.message}"
              errors << { worktree_id: worktree.id, error: e.message }
            end

            # Prune stale worktree references
            manager.prune

            Rails.logger.info "[WorktreeCleanup] Cleanup completed for session #{@session.id}: #{cleaned} cleaned, #{errors.size} errors"

            render_success(cleaned: cleaned, errors: errors)
          rescue StandardError => e
            Rails.logger.error "[WorktreeCleanup] Cleanup failed for session #{@session.id}: #{e.message}"
            render_error("Cleanup failed: #{e.message}", status: :unprocessable_entity)
          end

          # POST /api/v1/internal/ai/worktree_sessions/:id/push_and_pr
          # Pushes branches and creates a pull request on Gitea
          def push_and_pr
            config = @session.configuration || {}
            repository_path = config["repository_path"] || @session.repository_path
            gitea_repository = config["gitea_repository"]

            unless gitea_repository.present?
              return render_error("No gitea_repository configured for session", status: :unprocessable_entity)
            end

            service = ::Ai::Git::GiteaIntegrationService.new(
              repository_path: repository_path,
              gitea_repository: gitea_repository
            )

            title = params[:title] || "AI Session: #{@session.description || @session.id}"
            body = params[:body]

            result = service.finalize_session_with_pr(
              session: @session,
              title: title,
              body: body
            )

            if result[:success]
              @session.update(
                metadata: (@session.metadata || {}).merge(
                  "pr_number" => result[:pr_number],
                  "pr_url" => result[:pr_url],
                  "pr_created_at" => Time.current.iso8601
                )
              )

              render_success(
                pr_number: result[:pr_number],
                pr_url: result[:pr_url],
                session: @session.reload.session_summary
              )
            else
              render_error("PR creation failed: #{result[:error]}", status: :unprocessable_entity)
            end
          rescue StandardError => e
            Rails.logger.error "[WorktreePushAndPr] Failed for session #{@session.id}: #{e.message}"
            render_error("Push and PR failed: #{e.message}", status: :unprocessable_entity)
          end

          # POST /api/v1/internal/ai/worktree_sessions/:id/execute_merge
          # Runs the merge strategy for the session
          def execute_merge
            unless @session.status == "merging"
              return render_error("Session must be in merging status", status: :unprocessable_entity)
            end

            merge_service = ::Ai::Git::MergeService.new(session: @session)
            result = merge_service.execute

            if result[:success]
              @session.complete!

              render_success(
                result: result,
                auto_pr: @session.configuration&.dig("auto_create_pr") != false &&
                         @session.configuration&.dig("gitea_repository").present?,
                auto_cleanup: @session.auto_cleanup,
                session: @session.reload.session_summary
              )
            else
              @session.fail!(
                error_message: result[:error] || "Merge failed",
                error_code: "MERGE_FAILED",
                error_details: { results: result[:results] }
              )

              render_error(
                result[:error] || "Merge failed",
                status: :unprocessable_entity
              )
            end
          rescue StandardError => e
            Rails.logger.error "[MergeExecution] Failed for session #{@session.id}: #{e.message}"
            @session.fail!(error_message: e.message, error_code: "MERGE_JOB_FAILED")
            render_error("Merge execution failed: #{e.message}", status: :unprocessable_entity)
          end

          # POST /api/v1/internal/ai/worktree_sessions/:id/detect_conflicts
          # Runs conflict detection between active worktrees
          def detect_conflicts
            return render_error("Session is terminal", status: :unprocessable_entity) if @session.terminal?

            service = ::Ai::Git::ConflictDetectionService.new(session: @session)
            result = service.detect

            render_success(result)
          rescue StandardError => e
            Rails.logger.error "[ConflictDetection] Failed for session #{@session.id}: #{e.message}"
            render_error("Conflict detection failed: #{e.message}", status: :unprocessable_entity)
          end

          # POST /api/v1/internal/ai/worktree_sessions/check_timeouts
          # Checks all active sessions for timed-out worktrees
          def check_timeouts
            timed_out_count = 0

            ::Ai::WorktreeSession.active_sessions.find_each do |session|
              session.worktrees.active.where("timeout_at IS NOT NULL AND timeout_at < ?", Time.current).find_each do |worktree|
                worktree.fail!(error_message: "Worktree timed out", error_code: "TIMEOUT")
                timed_out_count += 1
                Rails.logger.warn "[WorktreeTimeout] Timed out worktree #{worktree.id} in session #{session.id}"
              end

              # Check session-level timeout
              if session.max_duration_seconds.present? && session.started_at.present?
                deadline = session.started_at + session.max_duration_seconds.seconds
                if Time.current > deadline
                  session.fail!(error_message: "Session timed out", error_code: "SESSION_TIMEOUT")
                  Rails.logger.warn "[WorktreeTimeout] Timed out session #{session.id}"
                end
              end
            end

            render_success(timed_out_worktrees: timed_out_count)
          end

          # GET /api/v1/internal/ai/worktree_sessions/:id/dispatch_status
          # Returns dispatch status for runner poll job
          def dispatch_status
            dispatches = @session.runner_dispatches.includes(:worktree)

            render_success(
              dispatches: dispatches.map(&:dispatch_summary),
              active_count: dispatches.active.count,
              completed_count: dispatches.completed.count,
              failed_count: dispatches.failed.count,
              all_worktrees_completed: @session.all_worktrees_completed?,
              session_status: @session.status
            )
          end

          # POST /api/v1/internal/ai/worktree_sessions/:id/timeout_dispatches
          # Times out active dispatches that have exceeded their deadline
          def timeout_dispatches
            timeout_cutoff = (params[:timeout_minutes] || 60).to_i.minutes.ago
            timed_out = []

            @session.runner_dispatches.active.where("dispatched_at < ?", timeout_cutoff).find_each do |dispatch|
              dispatch.update!(
                status: "failed",
                completed_at: Time.current,
                output_result: (dispatch.output_result || {}).merge("error" => "Dispatch timed out")
              )

              # Release the runner if assigned
              if dispatch.git_runner_id.present?
                runner = ::Devops::GitRunner.find_by(id: dispatch.git_runner_id)
                runner&.update!(status: "idle") if runner&.status == "busy"
              end

              # Fail the associated worktree
              dispatch.worktree&.fail!(error_message: "Runner dispatch timed out", error_code: "DISPATCH_TIMEOUT")

              timed_out << dispatch.id
              Rails.logger.warn "[DispatchTimeout] Timed out dispatch #{dispatch.id} for session #{@session.id}"
            end

            render_success(timed_out_dispatches: timed_out, count: timed_out.size)
          rescue StandardError => e
            Rails.logger.error "[DispatchTimeout] Failed for session #{@session.id}: #{e.message}"
            render_error("Dispatch timeout failed: #{e.message}", status: :unprocessable_entity)
          end

          private

          def set_session
            @session = ::Ai::WorktreeSession.find(params[:id])
          rescue ActiveRecord::RecordNotFound
            render_error("Session not found", status: :not_found)
          end

          def launch_container_if_configured(worktree)
            template_id = worktree.container_template_id
            return unless template_id

            template = ::Devops::ContainerTemplate.find_by(id: template_id)
            return unless template

            orchestration = ::Devops::ContainerOrchestrationService.new(
              account: @session.account,
              user: @session.initiated_by || @session.account.users.first
            )

            instance = orchestration.execute(
              template: template,
              input_parameters: {
                worktree_session_id: @session.id,
                worktree_id: worktree.id,
                working_directory: worktree.worktree_path,
                branch_name: worktree.branch_name,
                metadata: worktree.metadata
              },
              timeout_seconds: template.timeout_seconds
            )

            worktree.track_container_instance!(instance.id)
            worktree.mark_in_use!
          rescue StandardError => e
            Rails.logger.error "[WorktreeProvisioning] Container launch failed for #{worktree.branch_name}: #{e.message}"
            # Don't fail the worktree — container execution is optional
          end
        end
      end
    end
  end
end
