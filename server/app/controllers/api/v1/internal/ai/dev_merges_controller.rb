# frozen_string_literal: true

module Api
  module V1
    module Internal
      module Ai
        # Where Git::DevMergeIncrementJob reports the outcome of a merge that
        # dev_merge_increment (Ai::Tools::DevMergeTool) handed it. Writes the
        # audit row that closes the merge: repository, refs, SHAs, the result
        # per remote, and the caller's gate attestation.
        #
        # THE DISPATCH MARKER is the dev_merge.dispatched audit row, which the
        # tool writes BEFORE it enqueues the job. It is not the operation's
        # `result`: that is written by DeferredOperation#execute_now! only
        # after the enqueue returns, so a fast worker could report first, and
        # a failure after the enqueue would leave no result at all. The audit
        # row exists before the worker can run and is never rewritten. (The
        # worker also retries its report, so a transient failure here is not
        # the end of it.)
        #
        # The worker's report is NOT taken at its word:
        #   * succeeded needs the worker's own status AND every remote named in
        #     the marker reported pushed or up_to_date (a partial push is
        #     failed), the merged SHA equal to the approved expected SHA, and a
        #     pointer commit SHA whenever a pointer bump was dispatched;
        #   * refs, SHAs and the attestation in the audit row come from the
        #     approved operation, never from the report.
        #
        # Recorded once, under a row lock on the operation: a second report
        # answers already_recorded and writes nothing. "Once" is read from the
        # outcome audit rows, which nothing rewrites, rather than from the
        # operation's result, which #execute_now! may overwrite.
        class DevMergesController < InternalBaseController
          include Api::V1::Internal::WorkerTenancy

          REMOTE_OK = %w[pushed up_to_date].freeze
          ERROR_MAX = 2000
          OUTCOME_ACTIONS = %w[dev_merge.succeeded dev_merge.failed].freeze

          before_action :set_operation

          # POST /api/v1/internal/ai/dev_merges/:id/report
          def report
            @operation.with_lock do
              marker = dispatch_marker
              return render_error("Operation was not dispatched as a merge", status: :conflict) if marker.nil?

              recorded = outcome_rows.order(:created_at).first
              if recorded
                return render_success(already_recorded: true, outcome: recorded.action.delete_prefix("dev_merge."))
              end

              outcome = build_outcome(marker.metadata)
              result = @operation.result.is_a?(Hash) ? @operation.result : {}
              @operation.update!(result: result.merge("merge_outcome" => outcome))
              ::AuditLog.log_action(
                action: "dev_merge.#{outcome['status']}", resource: @operation, account: @operation.account,
                user: @operation.requested_by, source: "system",
                severity: "high", risk_level: "high",
                metadata: audit_metadata(outcome)
              )
              render_success(outcome: outcome["status"])
            end
          end

          private

          def set_operation
            @operation = ::Ai::DeferredOperation.where(account_id: worker_account_id,
                                                       action_category: ::Ai::Tools::DevMergeTool::ACTION_CATEGORY)
                                                .find(params[:id])
          rescue ActiveRecord::RecordNotFound
            render_error("Merge operation not found", status: :not_found)
          end

          def audit_scope
            ::AuditLog.where(resource_type: @operation.class.name, resource_id: @operation.id,
                             account_id: @operation.account_id)
          end

          def dispatch_marker
            audit_scope.where(action: "dev_merge.dispatched").order(:created_at).first
          end

          def outcome_rows
            audit_scope.where(action: OUTCOME_ACTIONS)
          end

          def tool_params
            call = @operation.params.is_a?(Hash) ? @operation.params : {}
            call["tool_params"].is_a?(Hash) ? call["tool_params"] : {}
          end

          def build_outcome(marker)
            marker = marker.is_a?(Hash) ? marker : {}
            dispatched_pointer = marker.dig("pointer_bump", "remotes")
            remotes = reported_remotes(:remotes)
            pointer_remotes = reported_remotes(:pointer_remotes)
            merged_sha = params[:merged_sha].to_s.downcase.presence
            pointer_sha = params[:pointer_commit_sha].to_s.downcase.presence

            succeeded = params[:status].to_s == "succeeded" &&
                        all_reached?(marker["remotes"], remotes) &&
                        merged_sha == tool_params["expected_source_sha"].to_s.downcase &&
                        (dispatched_pointer.blank? ||
                          (all_reached?(dispatched_pointer, pointer_remotes) && pointer_sha.to_s.match?(/\A\h{40}\z/)))

            {
              "status" => succeeded ? "succeeded" : "failed",
              "worker_status" => params[:status].to_s,
              "stage" => params[:stage].to_s.presence,
              "merged_sha" => merged_sha,
              "pointer_commit_sha" => pointer_sha,
              "remotes" => remotes,
              "pointer_remotes" => pointer_remotes.presence,
              "error" => params[:error].to_s.presence&.truncate(ERROR_MAX)
            }.compact
          end

          def reported_remotes(key)
            Array(params[key]).filter_map do |remote|
              entry = remote.respond_to?(:permit) ? remote.permit(:repository_id, :full_name, :status, :error).to_h : remote
              next unless entry.is_a?(Hash)

              entry = entry.stringify_keys.slice("repository_id", "full_name", "status", "error")
              entry["error"] = entry["error"].to_s.truncate(ERROR_MAX) if entry["error"].present?
              entry
            end
          end

          # Every remote the server dispatched to is reported as reached.
          def all_reached?(dispatched_remotes, reported)
            expected = Array(dispatched_remotes).map { |r| r.is_a?(Hash) ? r["repository_id"].to_s : nil }.compact
            return false if expected.empty?

            reached = reported.select { |r| REMOTE_OK.include?(r["status"].to_s) }.map { |r| r["repository_id"].to_s }
            (expected - reached).empty?
          end

          # Refs, SHAs and the attestation come from the APPROVED operation.
          def audit_metadata(outcome)
            bump = tool_params["pointer_bump"].is_a?(Hash) ? tool_params["pointer_bump"] : nil

            {
              "repository" => tool_params["repository"],
              "source_ref" => tool_params["source_ref"],
              "target_branch" => tool_params["target_branch"],
              "expected_source_sha" => tool_params["expected_source_sha"],
              "pointer_bump" => bump&.slice("parent_repository", "submodule_path"),
              "gate_attestation" => tool_params["gate_attestation"],
              "outcome" => outcome
            }.compact
          end
        end
      end
    end
  end
end
