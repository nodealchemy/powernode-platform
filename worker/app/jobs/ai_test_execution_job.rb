# frozen_string_literal: true

# Runs a Ralph loop iteration's test suite in an isolated checkout on the worker
# and POSTs the RAW result back to the server, which parses + gates task.pass!.
# Part of the in-platform sandbox engine (Phase A). This job is a dumb-but-real
# executor: it clones the branch, runs the given command (or auto-detects one
# from the repo-root manifest when none is supplied), and reports exit code +
# output. It does NOT decide pass/fail — the server's TestVerificationService
# parses the framework output and applies the success rule. The server dispatches
# this whenever real_test_execution gates a commit — the default since G1 (opt-out).
class AiTestExecutionJob < BaseJob
  include DevopsWorkspaceSteps

  sidekiq_options queue: "ai_execution", retry: 1

  # Manifest (at repo root) => [framework, command], in priority order (first
  # match wins). Deliberately mirrors the server's
  # Ai::Ralph::TestVerificationService::FRAMEWORKS — the server/worker boundary
  # forbids sharing the constant, so the two are kept in sync by hand.
  FRAMEWORK_DETECTION = [
    [ "Gemfile",          "rspec",  "bundle exec rspec" ],
    [ "pytest.ini",       "pytest", "python -m pytest -q" ],
    [ "pyproject.toml",   "pytest", "python -m pytest -q" ],
    [ "setup.py",         "pytest", "python -m pytest -q" ],
    [ "requirements.txt", "pytest", "python -m pytest -q" ],
    [ "package.json",     "jest",   "npm test --silent" ],
    [ "go.mod",           "gotest", "go test ./..." ],
    [ "Cargo.toml",       "cargo",  "cargo test" ]
  ].freeze

  def execute(args = {})
    loop_id      = args["ralph_loop_id"]
    iteration_id = args["ralph_iteration_id"]
    repository   = args["repository"]
    branch       = args["branch"].presence || "main"
    command      = args["command"].presence
    framework    = args["framework"].presence
    timeout_secs = (args["timeout_seconds"] || 600).to_i
    return if loop_id.blank? || iteration_id.blank?

    log_info("[AiTestExecution] starting", loop_id: loop_id, iteration_id: iteration_id,
             repository: repository, command: command || "(auto-detect)")

    workspace = nil
    begin
      workspace = checkout_workspace(repository, branch)

      # No explicit command ⇒ auto-detect the framework from the repo root.
      # Fail-closed: if nothing is recognised, report a failure rather than
      # silently passing a loop that has no real gate.
      if command.blank?
        detected = detect_framework(workspace)
        if detected.nil?
          report(loop_id, iteration_id, framework: nil, command: nil,
                 exit_code: 1, output: "", error: "no recognised test framework at repo root")
          return
        end
        framework = detected[:framework]
        command   = detected[:command]
      end

      run = run_workspace_command(workspace, command, timeout_secs: timeout_secs)
      report(loop_id, iteration_id, framework: framework, command: command,
             exit_code: run[:exit_code], output: run[:output], error: run[:error])
    rescue StandardError => e
      log_error("[AiTestExecution] execution failed", e, loop_id: loop_id, iteration_id: iteration_id)
      # Report as a failure (exit 1) so the iteration resolves rather than hanging.
      report(loop_id, iteration_id, framework: framework, command: command,
             exit_code: 1, output: "", error: e.message)
    ensure
      FileUtils.rm_rf(workspace) if workspace.present? && File.directory?(workspace)
    end
  end

  private

  # Inspect the checked-out repo root and return { framework:, command: } for the
  # first recognised manifest, or nil when none match (caller fails closed).
  def detect_framework(workspace)
    entries = Dir.children(workspace)
    FRAMEWORK_DETECTION.each do |manifest, framework, command|
      return { framework: framework, command: command } if entries.include?(manifest)
    end
    nil
  rescue SystemCallError => e
    log_error("[AiTestExecution] could not read workspace root for detection", e, workspace: workspace)
    nil
  end

  def report(loop_id, iteration_id, framework:, command:, exit_code:, output:, error:)
    api_client.post(
      "/api/v1/internal/ai/ralph_loops/#{loop_id}/iterations/#{iteration_id}/test_results",
      {
        test_result: {
          framework: framework,
          command: command,
          exit_code: exit_code,
          output: output.to_s,
          error: error.to_s,
          completed_at: Time.current.iso8601
        }
      }
    )
  rescue StandardError => e
    log_error("[AiTestExecution] failed to post test results", e, loop_id: loop_id, iteration_id: iteration_id)
  end
end
