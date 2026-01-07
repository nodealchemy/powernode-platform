# frozen_string_literal: true

module CiCd
  # Orchestrates complete pipeline execution
  # Queue: ci_cd_high
  # Retry: 2
  class PipelineExecutionJob < BaseJob
    sidekiq_options queue: "ci_cd_high", retry: 2

    # Execute a pipeline run
    # @param pipeline_run_id [String] The pipeline run ID
    # @param options [Hash] Execution options
    #   - simulate: true for simulated execution (default: true)
    #   - step_delay: delay between steps in seconds (default: 3)
    #   - fail_step: step position to fail at (optional)
    def execute(pipeline_run_id, options = {})
      options = options.transform_keys(&:to_sym)
      simulate = options.fetch(:simulate, true)
      step_delay = options.fetch(:step_delay, 3).to_i
      fail_step = options[:fail_step]&.to_i

      log_info "Starting pipeline execution", pipeline_run_id: pipeline_run_id, simulate: simulate

      # Fetch pipeline run and steps from backend API
      run_data = fetch_pipeline_run(pipeline_run_id)
      steps = run_data["steps"] || []

      # Update status to running
      update_run_status(pipeline_run_id, "running", started_at: Time.current.iso8601)

      # Execute each step
      total_steps = steps.count { |s| s["is_active"] }
      completed_steps = 0
      failed = false

      steps.sort_by { |s| s["position"] }.each do |step|
        next unless step["is_active"]

        step_position = step["position"]
        step_name = step["name"]
        step_type = step["step_type"]

        log_info "Executing step", step_name: step_name, step_type: step_type, position: step_position

        # Create step execution record
        execution_id = create_step_execution(pipeline_run_id, step["id"])

        # Update to running
        update_step_execution(execution_id, status: "running", started_at: Time.current.iso8601)

        # Progress is calculated dynamically from step execution counts
        log_info "Step progress", completed: completed_steps, total: total_steps

        # Simulate step execution with delay
        sleep(step_delay) if simulate && step_delay > 0

        # Check if this step should fail
        should_fail = fail_step && step_position == fail_step

        if should_fail
          failure_output = generate_step_failure(step)
          update_step_execution(
            execution_id,
            status: "failed",
            completed_at: Time.current.iso8601,
            error_message: failure_output[:error],
            logs: failure_output[:logs],
            outputs: failure_output[:outputs]
          )
          failed = true
          log_warn "Step failed", step_name: step_name

          # Stop unless continue_on_error is set
          unless step["continue_on_error"]
            break
          end
        else
          step_output = generate_step_output(step, run_data)
          update_step_execution(
            execution_id,
            status: "success",
            completed_at: Time.current.iso8601,
            logs: step_output[:logs],
            outputs: step_output[:outputs]
          )
          completed_steps += 1
        end
      end

      # Complete the pipeline run
      final_status = failed ? "failed" : "success"
      update_run_status(
        pipeline_run_id,
        final_status,
        completed_at: Time.current.iso8601
      )

      log_info "Pipeline execution completed", pipeline_run_id: pipeline_run_id, status: final_status
    rescue StandardError => e
      log_error "Pipeline execution failed", e, pipeline_run_id: pipeline_run_id
      update_run_status(pipeline_run_id, "failed", error_message: e.message, completed_at: Time.current.iso8601)
      raise
    end

    private

    def fetch_pipeline_run(pipeline_run_id)
      response = api_client.get("/api/v1/internal/ci_cd/pipeline_runs/#{pipeline_run_id}")
      response.dig("data", "pipeline_run")
    end

    def update_run_status(pipeline_run_id, status, **attributes)
      api_client.patch("/api/v1/internal/ci_cd/pipeline_runs/#{pipeline_run_id}", {
        pipeline_run: { status: status }.merge(attributes)
      })
    end

    def create_step_execution(pipeline_run_id, step_id)
      response = api_client.post("/api/v1/internal/ci_cd/step_executions", {
        step_execution: {
          pipeline_run_id: pipeline_run_id,
          pipeline_step_id: step_id,
          status: "pending"
        }
      })
      response.dig("data", "step_execution", "id")
    end

    def update_step_execution(execution_id, **attributes)
      api_client.patch("/api/v1/internal/ci_cd/step_executions/#{execution_id}", {
        step_execution: attributes
      })
    end

    # Generate realistic output based on step type
    def generate_step_output(step, run_data)
      step_type = step["step_type"]
      step_name = step["name"]
      config = step["configuration"] || {}
      pipeline_name = run_data["pipeline_name"] || "Pipeline"

      case step_type
      when "checkout"
        generate_checkout_output(config, run_data)
      when "run_tests"
        generate_test_output(config, step_name)
      when "deploy"
        generate_deploy_output(config, step_name)
      when "notify"
        generate_notify_output(config, step_name, pipeline_name)
      when "claude_execute"
        generate_ai_output(config, step_name)
      when "post_comment"
        generate_comment_output(config, step_name)
      when "create_pr"
        generate_pr_output(config, step_name)
      when "create_branch"
        generate_branch_output(config, step_name)
      when "upload_artifact"
        generate_upload_output(config, step_name)
      when "download_artifact"
        generate_download_output(config, step_name)
      when "custom"
        generate_custom_output(config, step_name)
      else
        { logs: "Step #{step_name} completed successfully", outputs: {} }
      end
    end

    def generate_checkout_output(config, run_data)
      branch = run_data["branch"] || config["branch"] || "develop"
      repo = "powernode/powernode-platform"
      commit = SecureRandom.hex(20)
      short_commit = commit[0..6]

      logs = <<~LOGS
        Cloning repository #{repo}...
        Cloning into '/workspace'...
        remote: Enumerating objects: 1542, done.
        remote: Counting objects: 100% (1542/1542), done.
        remote: Compressing objects: 100% (892/892), done.
        Receiving objects: 100% (1542/1542), 2.84 MiB | 12.5 MiB/s, done.
        Resolving deltas: 100% (743/743), done.
        Switched to branch '#{branch}'
        HEAD is now at #{short_commit} Latest commit on #{branch}
        Checkout completed successfully.
      LOGS

      {
        logs: logs.strip,
        outputs: {
          "repository" => repo,
          "branch" => branch,
          "commit_sha" => commit,
          "short_sha" => short_commit,
          "ref" => "refs/heads/#{branch}"
        }
      }
    end

    def generate_test_output(config, step_name)
      framework = config["framework"] || "rspec"
      total_tests = rand(50..200)
      passed = total_tests - rand(0..3)
      failed = total_tests - passed
      duration = rand(5.0..45.0).round(2)
      coverage = rand(75.0..98.0).round(1)

      logs = case framework
             when "jest"
               generate_jest_logs(total_tests, passed, failed, duration, coverage)
             when "pytest"
               generate_pytest_logs(total_tests, passed, failed, duration, coverage)
             else
               generate_rspec_logs(total_tests, passed, failed, duration, coverage)
             end

      {
        logs: logs,
        outputs: {
          "passed" => failed == 0,
          "total_tests" => total_tests,
          "passed_count" => passed,
          "failed_count" => failed,
          "duration_seconds" => duration,
          "coverage_percentage" => coverage,
          "framework" => framework
        }
      }
    end

    def generate_rspec_logs(total, passed, failed, duration, coverage)
      dots = "." * passed + "F" * failed
      <<~LOGS
        Running RSpec test suite...
        #{dots}

        Finished in #{duration} seconds (files took 1.23 seconds to load)
        #{total} examples, #{failed} failures

        Coverage report generated: #{coverage}% covered
        All files (#{rand(20..50)} files) #{coverage}% covered.

        #{failed == 0 ? 'All tests passed!' : "#{failed} test(s) failed"}
      LOGS
    end

    def generate_jest_logs(total, passed, failed, duration, coverage)
      <<~LOGS
        PASS src/components/__tests__/Button.test.tsx
        PASS src/hooks/__tests__/useAuth.test.ts
        PASS src/services/__tests__/api.test.ts

        Test Suites: #{failed == 0 ? total : "#{failed} failed, #{passed} passed"}, #{total} total
        Tests:       #{failed == 0 ? "#{passed} passed" : "#{failed} failed, #{passed} passed"}, #{total} total
        Snapshots:   0 total
        Time:        #{duration}s
        Coverage:    #{coverage}% Statements

        #{failed == 0 ? '✓ All tests passed!' : "✗ #{failed} test(s) failed"}
      LOGS
    end

    def generate_pytest_logs(total, passed, failed, duration, coverage)
      <<~LOGS
        ========================= test session starts ==========================
        platform linux -- Python 3.11.0, pytest-7.4.0
        collected #{total} items

        tests/test_api.py #{failed == 0 ? '.' * [total / 3, 1].max : '.' * (total / 3 - 1) + 'F'}
        tests/test_models.py #{'.' * [total / 3, 1].max}
        tests/test_services.py #{'.' * [total / 3, 1].max}

        #{failed == 0 ? "#{passed} passed" : "#{failed} failed, #{passed} passed"} in #{duration}s
        Coverage: #{coverage}%

        ========================= #{failed == 0 ? 'all tests passed' : "#{failed} failed"} ==========================
      LOGS
    end

    def generate_deploy_output(config, step_name)
      environment = config["environment"] || "staging"
      strategy = config["strategy"] || "rolling"
      version = "v#{rand(1..5)}.#{rand(0..12)}.#{rand(0..99)}"
      deploy_id = SecureRandom.hex(8)

      logs = <<~LOGS
        Starting deployment to #{environment}...
        Strategy: #{strategy}
        Version: #{version}
        Deploy ID: #{deploy_id}

        [1/4] Building container image...
        Successfully built image: powernode:#{version}

        [2/4] Pushing to registry...
        Pushed: registry.powernode.org/powernode:#{version}

        [3/4] Updating #{environment} environment...
        Deployment #{deploy_id} started
        Waiting for rollout to complete...
        Rollout completed successfully

        [4/4] Running health checks...
        Health check passed: https://#{environment}.powernode.org/health
        All instances healthy (3/3)

        ✓ Deployment to #{environment} completed successfully
      LOGS

      {
        logs: logs.strip,
        outputs: {
          "deployed" => true,
          "environment" => environment,
          "version" => version,
          "deploy_id" => deploy_id,
          "strategy" => strategy,
          "instances" => 3,
          "url" => "https://#{environment}.powernode.org"
        }
      }
    end

    def generate_notify_output(config, step_name, pipeline_name)
      channels = config["channels"] || ["slack"]
      notify_type = config["type"] || "completion"

      logs = <<~LOGS
        Sending notifications...
        #{channels.map { |c| "  ✓ #{c.capitalize}: Message sent successfully" }.join("\n")}

        Notification summary:
          Pipeline: #{pipeline_name}
          Type: #{notify_type}
          Channels: #{channels.join(', ')}
          Timestamp: #{Time.current.iso8601}

        All notifications delivered successfully.
      LOGS

      {
        logs: logs.strip,
        outputs: {
          "notified" => true,
          "channels" => channels,
          "type" => notify_type,
          "message_count" => channels.length,
          "timestamp" => Time.current.iso8601
        }
      }
    end

    def generate_ai_output(config, step_name)
      model = config["model"] || "claude-sonnet-4-20250514"
      tokens_used = rand(500..2000)

      logs = <<~LOGS
        Executing AI task: #{step_name}
        Model: #{model}

        Processing request...
        Tokens used: #{tokens_used}

        AI Analysis Complete:
        ─────────────────────
        The code has been analyzed and processed successfully.
        No critical issues found.
        Suggestions have been generated.

        ✓ AI task completed successfully
      LOGS

      {
        logs: logs.strip,
        outputs: {
          "completed" => true,
          "model" => model,
          "tokens_used" => tokens_used,
          "quality_score" => rand(80..100),
          "issues_found" => rand(0..3),
          "suggestions" => rand(1..5)
        }
      }
    end

    def generate_comment_output(config, step_name)
      comment_id = rand(1000..9999)
      {
        logs: "Posted comment ##{comment_id} successfully\nComment body: Pipeline execution completed.",
        outputs: {
          "comment_id" => comment_id,
          "posted" => true,
          "url" => "https://gitea.powernode.org/powernode/powernode-platform/issues/1#comment-#{comment_id}"
        }
      }
    end

    def generate_pr_output(config, step_name)
      pr_number = rand(100..500)
      {
        logs: "Created pull request ##{pr_number}\nTitle: Automated changes from pipeline\nBase: develop ← Head: feature/auto-#{SecureRandom.hex(4)}",
        outputs: {
          "pr_number" => pr_number,
          "created" => true,
          "url" => "https://gitea.powernode.org/powernode/powernode-platform/pulls/#{pr_number}",
          "state" => "open"
        }
      }
    end

    def generate_branch_output(config, step_name)
      branch_name = config["branch_name"] || "feature/auto-#{SecureRandom.hex(4)}"
      {
        logs: "Created branch: #{branch_name}\nBased on: develop\nPushed to origin successfully.",
        outputs: {
          "branch_name" => branch_name,
          "created" => true,
          "base_branch" => "develop",
          "ref" => "refs/heads/#{branch_name}"
        }
      }
    end

    def generate_upload_output(config, step_name)
      artifact_name = config["name"] || "build-artifacts"
      size = rand(1..50)
      {
        logs: "Uploading artifact: #{artifact_name}\nSize: #{size} MB\nRetention: 30 days\nUpload completed successfully.",
        outputs: {
          "artifact_name" => artifact_name,
          "uploaded" => true,
          "size_mb" => size,
          "retention_days" => 30,
          "artifact_id" => SecureRandom.uuid
        }
      }
    end

    def generate_download_output(config, step_name)
      artifact_name = config["artifact_name"] || "build-artifacts"
      size = rand(1..50)
      {
        logs: "Downloading artifact: #{artifact_name}\nSize: #{size} MB\nExtracted to: ./artifacts/\nDownload completed successfully.",
        outputs: {
          "artifact_name" => artifact_name,
          "downloaded" => true,
          "size_mb" => size,
          "path" => "./artifacts/#{artifact_name}"
        }
      }
    end

    def generate_custom_output(config, step_name)
      command = config["command"] || config["run"] || "echo 'Custom step'"
      exit_code = 0
      {
        logs: "$ #{command}\nCommand executed successfully\nExit code: #{exit_code}",
        outputs: {
          "exit_code" => exit_code,
          "success" => true,
          "command" => command
        }
      }
    end

    def generate_step_failure(step)
      step_type = step["step_type"]
      step_name = step["name"]

      case step_type
      when "run_tests"
        {
          error: "Test suite failed: 3 tests failed",
          logs: "Running tests...\n\nFAILED: test_user_authentication\nFAILED: test_api_validation\nFAILED: test_data_integrity\n\n3 failures, 47 passed",
          outputs: { "passed" => false, "failed_count" => 3 }
        }
      when "deploy"
        {
          error: "Deployment failed: Health check timeout",
          logs: "Deploying to staging...\nHealth check failed after 60s\nRolling back...\nRollback completed",
          outputs: { "deployed" => false, "rolled_back" => true }
        }
      else
        {
          error: "Step #{step_name} failed",
          logs: "Error executing #{step_name}\nSimulated failure for testing",
          outputs: { "success" => false }
        }
      end
    end
  end
end
