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
        # The worker's report is NOT taken at its word on the one question that
        # matters. The server recorded which remotes it dispatched the merge to;
        # the outcome is succeeded only when the worker says so AND every one of
        # those remotes is reported pushed or already up to date. A push that
        # reached only some remotes is failed, whatever the summary says. The
        # attestation and refs come from the approved operation, never from the
        # report.
        #
        # Recorded once. A second report for the same operation (a retried
        # request) answers already_recorded and writes nothing.
        class DevMergesController < InternalBaseController
          include Api::V1::Internal::WorkerTenancy

          REMOTE_OK = %w[pushed up_to_date].freeze
          ERROR_MAX = 2000

          before_action :set_operation

          # POST /api/v1/internal/ai/dev_merges/:id/report
          def report
            dispatched = dispatched_result
            unless dispatched["dispatched"] == true
              return render_error("Operation was not dispatched as a merge", status: :conflict)
            end

            result = @operation.result.is_a?(Hash) ? @operation.result : {}
            if result["merge_outcome"].present?
              return render_success(already_recorded: true, outcome: result.dig("merge_outcome", "status"))
            end

            outcome = build_outcome(dispatched)
            ::ActiveRecord::Base.transaction do
              @operation.update!(result: result.merge("merge_outcome" => outcome))
              ::AuditLog.log_action(
                action: "dev_merge.#{outcome['status']}", resource: @operation, account: @operation.account,
                user: @operation.requested_by, source: "system",
                severity: "high", risk_level: "high",
                metadata: audit_metadata(outcome)
              )
            end

            render_success(outcome: outcome["status"])
          end

          private

          def set_operation
            @operation = ::Ai::DeferredOperation.where(account_id: worker_account_id,
                                                       action_category: ::Ai::Tools::DevMergeTool::ACTION_CATEGORY)
                                                .find(params[:id])
          rescue ActiveRecord::RecordNotFound
            render_error("Merge operation not found", status: :not_found)
          end

          # What the approved replay returned when it dispatched: the tool's own
          # envelope, stored on the operation by #execute_now!.
          def dispatched_result
            result = @operation.result.is_a?(Hash) ? @operation.result : {}
            data = result["data"]
            data.is_a?(Hash) ? data : {}
          end

          def build_outcome(dispatched)
            remotes = reported_remotes(:remotes)
            pointer_remotes = reported_remotes(:pointer_remotes)
            merge_ok = all_reached?(dispatched["remotes"], remotes)
            pointer_ok = dispatched["pointer_remotes"].blank? || all_reached?(dispatched["pointer_remotes"], pointer_remotes)
            succeeded = params[:status].to_s == "succeeded" && merge_ok && pointer_ok

            {
              "status" => succeeded ? "succeeded" : "failed",
              "worker_status" => params[:status].to_s,
              "stage" => params[:stage].to_s.presence,
              "merged_sha" => params[:merged_sha].to_s.presence,
              "pointer_commit_sha" => params[:pointer_commit_sha].to_s.presence,
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
            call = @operation.params.is_a?(Hash) ? @operation.params : {}
            tool_params = call["tool_params"].is_a?(Hash) ? call["tool_params"] : {}
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
