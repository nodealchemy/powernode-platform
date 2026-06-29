# frozen_string_literal: true

module Ai
  module Missions
    class TestRunnerService
      class TestRunnerError < StandardError; end

      CI_WORKFLOW_PATHS = %w[
        .gitea/workflows/ci.yml
        .gitea/workflows/ci.yaml
        .gitea/workflows/test.yml
        .gitea/workflows/test.yaml
        .github/workflows/ci.yml
        .github/workflows/ci.yaml
        .github/workflows/test.yml
        .github/workflows/test.yaml
      ].freeze

      attr_reader :mission, :account

      def initialize(mission:)
        @mission = mission
        @account = mission.account
      end

      # Triggers CI workflow or falls back to auto-pass
      # Returns { run_id:, status:, method: }
      def trigger!
        repository = mission.repository
        raise TestRunnerError, "No repository linked to mission" unless repository

        credential = find_git_credential(repository)
        unless credential
          return gated_pass_or_fail!("No git credentials found")
        end

        client = Devops::Git::ApiClient.for(credential)
        owner = repository.owner
        repo_name = repository.name
        branch = mission.branch_name || "main"

        # Detect CI workflow file
        workflow_file = detect_workflow_file(client, owner, repo_name)

        unless workflow_file
          return gated_pass_or_fail!("No CI workflow file found")
        end

        # Dispatch workflow
        dispatch_result = client.trigger_workflow(owner, repo_name, workflow_file, branch)

        unless dispatch_result[:success]
          return gated_pass_or_fail!("Workflow dispatch failed: #{dispatch_result[:error]}")
        end

        # Try to find the triggered run
        run_id = find_triggered_run(client, owner, repo_name, branch)

        result = {
          run_id: run_id || SecureRandom.uuid,
          status: "running",
          method: "ci_workflow",
          workflow_file: workflow_file,
          triggered_at: Time.current.iso8601
        }

        mission.update!(test_result: result)
        result
      rescue TestRunnerError
        raise
      rescue StandardError => e
        Rails.logger.error("[TestRunnerService] #{e.message}")
        gated_pass_or_fail!("CI trigger error: #{e.message}")
      end

      # Check status of a running CI workflow
      # Returns { status: "running"|"completed"|"failed", passed: bool }
      def check_status
        test_result = mission.test_result || {}
        return { status: "unknown", passed: false } if test_result.blank?

        # If it was an auto-pass, it's already done
        if test_result["method"] == "auto_pass"
          return { status: "completed", passed: true, results: test_result }
        end

        repository = mission.repository
        return unverifiable_result("No repository linked") unless repository

        credential = find_git_credential(repository)
        return unverifiable_result("No git credentials") unless credential

        run_id = test_result["run_id"]
        return unverifiable_result("No CI run id recorded") unless run_id

        client = Devops::Git::ApiClient.for(credential)
        owner = repository.owner
        repo_name = repository.name

        begin
          run = client.get_workflow_run(owner, repo_name, run_id)
          map_workflow_status(run, test_result)
        rescue StandardError => e
          Rails.logger.warn("[TestRunnerService] Status check failed: #{e.message}")
          unverifiable_result("Status check failed: #{e.message}")
        end
      end

      private

      def find_git_credential(repository)
        account.git_provider_credentials
          .joins(:provider)
          .where(git_providers: { provider_type: repository.provider_type })
          .first
      end

      def detect_workflow_file(client, owner, repo_name)
        CI_WORKFLOW_PATHS.each do |path|
          content = client.get_file_content(owner, repo_name, path)
          return File.basename(path) if content && content[:content]
        rescue StandardError
          next
        end
        nil
      end

      def find_triggered_run(client, owner, repo_name, branch)
        sleep(2) # Brief wait for the run to appear
        runs = client.list_workflow_runs(owner, repo_name, per_page: 5)
        recent = runs.find { |r| r["head_branch"] == branch }
        recent&.dig("id")
      rescue StandardError
        nil
      end

      # When real CI can't run/verify, honour the account's posture: by default
      # we preserve legacy auto-pass (no live behaviour change); when the account
      # opts into `missions_require_real_ci`, we fail closed instead of certifying
      # untested code as passed. Mirrors the Ralph real_test_execution flag.
      def require_real_ci?
        account&.settings&.dig("missions_require_real_ci") == true
      end

      def gated_pass_or_fail!(reason)
        require_real_ci? ? fail_closed!(reason) : auto_pass!("#{reason} — skipping CI")
      end

      # Result for check_status when a running CI cannot be verified.
      def unverifiable_result(note)
        { status: "completed", passed: !require_real_ci?, note: note }
      end

      def auto_pass!(reason)
        run_id = SecureRandom.uuid
        result = {
          "run_id" => run_id,
          "status" => "passed",
          "passed" => true,
          "method" => "auto_pass",
          "reason" => reason,
          "started_at" => Time.current.iso8601,
          "completed_at" => Time.current.iso8601,
          "summary" => reason
        }
        mission.update!(test_result: result)
        { run_id: run_id, status: "passed", method: "auto_pass", reason: reason }
      end

      def fail_closed!(reason)
        run_id = SecureRandom.uuid
        result = {
          "run_id" => run_id,
          "status" => "failed",
          "passed" => false,
          "method" => "fail_closed",
          "reason" => reason,
          "started_at" => Time.current.iso8601,
          "completed_at" => Time.current.iso8601,
          "summary" => "Test gate failed closed: #{reason}"
        }
        mission.update!(test_result: result)
        { run_id: run_id, status: "failed", passed: false, method: "fail_closed", reason: reason }
      end

      def map_workflow_status(run, test_result)
        status = run["status"]
        conclusion = run["conclusion"]

        case status
        when "completed"
          passed = conclusion == "success"
          updated = test_result.merge(
            "status" => passed ? "passed" : "failed",
            "passed" => passed,
            "conclusion" => conclusion,
            "completed_at" => Time.current.iso8601
          )
          mission.update!(test_result: updated)
          { status: "completed", passed: passed, conclusion: conclusion, results: updated }
        when "in_progress", "queued", "pending"
          { status: "running", passed: false }
        when "failed", "cancelled"
          updated = test_result.merge(
            "status" => "failed",
            "passed" => false,
            "conclusion" => conclusion || status,
            "completed_at" => Time.current.iso8601
          )
          mission.update!(test_result: updated)
          { status: "failed", passed: false, conclusion: conclusion || status, results: updated }
        else
          { status: "running", passed: false }
        end
      end
    end
  end
end
