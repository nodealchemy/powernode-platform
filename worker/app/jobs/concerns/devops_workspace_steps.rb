# frozen_string_literal: true

# Shared plumbing for jobs that operate on a REAL checkout via the Devops step
# handlers: clone+checkout a branch and run a command inside the workspace.
# Extracted from AiTestExecutionJob so the land security-scan job reuses the same
# checkout/run pipeline instead of duplicating it.
#
# The step handlers are referenced lexically (from inside `module Devops`) by the
# pipeline job, but a top-level job doesn't reliably trigger their autoload in the
# Sidekiq process, so resolution falls back to an explicit require (base first).
module DevopsWorkspaceSteps
  # Clone + checkout the branch; returns the workspace path (raises if none).
  def checkout_workspace(repository, branch)
    handler = step_handler_class("CheckoutHandler", "checkout_handler").new(api_client: api_client, logger: logger)
    result = handler.execute(
      config: { "ref" => branch },
      context: { trigger_context: { repository: repository, branch: branch } },
      previous_outputs: {}
    )
    workspace = step_output(result, :workspace)
    raise "checkout produced no workspace for #{repository}@#{branch}" if workspace.blank?

    workspace
  end

  # Run a shell command inside a checked-out workspace; returns
  # { exit_code:, output:, error: }. continue_on_error keeps the exit code instead
  # of raising so the caller can inspect it.
  def run_workspace_command(workspace, command, timeout_secs: 600, continue_on_error: true)
    handler = step_handler_class("RunCommandHandler", "run_command_handler").new(api_client: api_client, logger: logger)
    result = handler.execute(
      config: {
        "command" => command,
        "timeout_minutes" => [ (timeout_secs / 60.0).ceil, 1 ].max,
        "continue_on_error" => continue_on_error
      },
      context: { trigger_context: {} },
      previous_outputs: { "checkout" => { workspace: workspace } }
    )
    {
      exit_code: (step_output(result, :exit_code) || 1).to_i,
      output: step_output(result, :output).to_s,
      error: step_output(result, :error)
    }
  end

  # Resolve a Devops::StepHandlers::* class, requiring it explicitly when the
  # Sidekiq process hasn't autoloaded it.
  def step_handler_class(const_name, file)
    ::Devops::StepHandlers.const_get(const_name)
  rescue NameError
    dir = File.expand_path("../../services/devops/step_handlers", __dir__)
    require File.join(dir, "base")
    require File.join(dir, file)
    ::Devops::StepHandlers.const_get(const_name)
  end

  # Step handlers return { outputs: {...} } with symbol-ish keys; tolerate both.
  def step_output(result, key)
    outputs = result[:outputs] || result["outputs"] || {}
    outputs[key] || outputs[key.to_s]
  end
end
