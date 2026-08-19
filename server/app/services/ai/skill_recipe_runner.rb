# frozen_string_literal: true

module Ai
  # Interprets recipe-skill specs (Ai::Skill.metadata["recipe"]) and dispatches
  # the declared MCP tool sequence. See docs/concepts/agents-and-autonomy.md
  # §"Recipe specification" for the spec format.
  #
  # Recipe shape:
  #
  #   {
  #     "version" => "1",
  #     "inputs"  => [ { "name" => "region", "type" => "string", "required" => true }, ... ],
  #     "steps"   => [
  #       { "id" => "step1", "tool" => "system_list_providers", "params" => {...}, "capture" => "providers" },
  #       { "id" => "step2", "tool" => "system_provision_instance",
  #         "params" => { "provider_id" => "{{ providers.results[0].id }}" },
  #         "require_approval" => true }
  #     ],
  #     "output" => { "instance_id" => "{{ step2.data.id }}" }
  #   }
  #
  # Variable interpolation: `{{ inputs.name }}` and `{{ <capture>.<dotted.path> }}`.
  # Array indexing: `{{ providers.results[0].id }}`.
  #
  # Three execution modes:
  #
  #   .execute(skill:, inputs:, ...)    — full run; dispatches tools, persists trace
  #   .dry_run(skill:, inputs:, ...)    — resolves bindings, validates, doesn't dispatch
  #   .resume(run:, ...)                — picks up a paused run after approval
  #
  # All return an Ai::SkillRecipeRun row (persisted), even on validation failure
  # (`status: "failed"`).
  class SkillRecipeRunner
    MAX_STEPS = 50           # safety cap — recipes shouldn't be huge
    INTERPOLATION_RE = /\{\{\s*([^}]+?)\s*\}\}/

    class RecipeError < StandardError; end

    def self.execute(skill:, inputs:, account:, user: nil, agent: nil, dry_run: false)
      new(skill: skill, inputs: inputs, account: account, user: user, agent: agent, dry_run: dry_run).run
    end

    def self.dry_run(skill:, inputs:, account:, user: nil, agent: nil)
      execute(skill: skill, inputs: inputs, account: account, user: user, agent: agent, dry_run: true)
    end

    def self.resume(run:)
      raise RecipeError, "Run is not paused" unless run.paused?

      new(skill: run.skill, inputs: run.inputs, account: run.account,
          user: run.user, agent: run.agent, existing_run: run).run
    end

    def initialize(skill:, inputs:, account:, user: nil, agent: nil, dry_run: false, existing_run: nil)
      @skill   = skill
      @inputs  = inputs.is_a?(Hash) ? inputs.with_indifferent_access : {}.with_indifferent_access
      @account = account
      @user    = user
      @agent   = agent
      @dry_run = dry_run
      @run     = existing_run
    end

    def run
      ensure_run!
      ensure_recipe!
      validate_inputs!

      @run.update!(status: "running", started_at: @run.started_at || Time.current) unless @dry_run

      captures = resume_captures_from(@run)
      remaining_steps = remaining_steps_for(@run)

      remaining_steps.each_with_index do |step, idx|
        global_idx = (@run.steps_log || []).size + idx
        raise RecipeError, "Recipe exceeds MAX_STEPS=#{MAX_STEPS}" if global_idx >= MAX_STEPS

        enforce_policy_block!(step) unless @dry_run

        if requires_approval?(step) && !@dry_run && !approval_already_granted_for?(step)
          pause_for_approval!(step)
          return @run
        end

        step_result = execute_step(step, captures)
        record_step!(step, step_result)

        if step_result[:error]
          fail_run!(step, step_result[:error])
          return @run
        end

        # capture output under the step's capture name (or id)
        capture_name = step["capture"] || step["id"]
        captures[capture_name] = step_result[:result] if capture_name.present?
      end

      finalize_run!(captures)
      @run
    rescue RecipeError => e
      fail_run!(nil, e.message)
      @run
    rescue StandardError => e
      Rails.logger.error("[SkillRecipeRunner] crash skill=#{@skill&.slug} run=#{@run&.id}: #{e.class}: #{e.message}")
      fail_run!(nil, "Runner crashed: #{e.class}: #{e.message}")
      @run
    end

    private

    def ensure_run!
      return if @run

      @run = ::Ai::SkillRecipeRun.create!(
        account: @account,
        skill: @skill,
        user: @user,
        agent: @agent,
        status: @dry_run ? "running" : "pending",
        inputs: @inputs.to_h,
        outputs: {},
        steps_log: [],
        dry_run: @dry_run,
        started_at: Time.current
      )
    end

    def ensure_recipe!
      raise RecipeError, "Skill #{@skill&.slug.inspect} is not a recipe skill" unless @skill&.recipe?
      raise RecipeError, "Recipe has no steps" if @skill.recipe_steps.empty?
    end

    def validate_inputs!
      missing = @skill.recipe_inputs.select { |spec| spec["required"] }
                                    .map { |spec| spec["name"] }
                                    .reject { |name| @inputs.key?(name) }
      raise RecipeError, "Missing required input(s): #{missing.join(', ')}" if missing.any?
    end

    # === Approval resolution ========================================
    #
    # `step["require_approval"]` is recipe CONTENT, so on its own it let the
    # author of a recipe decide whether their own recipe pauses — circular as a
    # control on caller-supplied material. Operator policy can now force the
    # pause, and the two combine one-way: policy may only ADD friction. A
    # permissive policy never removes an author-requested approval.
    def requires_approval?(step)
      return true if step["require_approval"]

      policy_forces_approval?(step)
    end

    # Resolves against Ai::InterventionPolicyService under a recipe-scoped
    # category ("ai.recipe.<tool>"), namespaced so it cannot collide with the
    # autonomy categories executors use.
    #
    # KEYED ON `record`, NOT ON THE VERDICT, and that is the load-bearing
    # detail. InterventionPolicyService#default_policy returns
    # "require_approval" when NOTHING matches, so asking for the verdict alone
    # would pause every step on every platform where no recipe policy has been
    # written. A gate that fires that readily gets routed around, which is
    # worse than the gap it closes. `record` is nil for the default and present
    # only when a real row matched, so "unconfigured" stays distinguishable
    # from "configured to require approval".
    def policy_verdict_for(step)
      resolved = ::Ai::InterventionPolicyService
                 .new(account: @account)
                 .resolve(action_category: recipe_action_category(step),
                          agent: @agent, user: @user)
      return nil if resolved[:record].nil?

      resolved[:policy].to_s
    end

    def policy_forces_approval?(step)
      policy_verdict_for(step) == "require_approval"
    rescue StandardError => e
      # FAIL CLOSED. An exception here is not a normal path, and the two
      # failure modes are not symmetric: pausing a run an operator can release
      # is recoverable, silently skipping a gate they configured is not.
      Rails.logger.error("[SkillRecipeRunner] policy resolution failed, pausing: #{e.class}: #{e.message}")
      true
    end

    # A blocked action is refused outright rather than paused: pausing would
    # offer an approver the chance to release something the operator blocked,
    # which is a different (and weaker) verdict than the one they set.
    def enforce_policy_block!(step)
      return unless policy_verdict_for(step) == "block"

      raise RecipeError,
            "Step '#{step['id']}' blocked by operator policy for #{recipe_action_category(step)}"
    rescue ::Ai::SkillRecipeRunner::RecipeError
      raise
    rescue StandardError => e
      Rails.logger.error("[SkillRecipeRunner] policy block check failed: #{e.class}: #{e.message}")
      nil
    end

    def recipe_action_category(step)
      "ai.recipe.#{step['tool']}"
    end

    # Reconstructs captures from prior step results when resuming a paused run.
    def resume_captures_from(run)
      captures = {}.with_indifferent_access
      Array(run.steps_log).each do |entry|
        capture_name = entry["capture"] || entry["step_id"] || entry["id"]
        next if capture_name.blank?
        next if entry["error"].present?

        captures[capture_name] = entry["result"]
      end
      captures
    end

    def remaining_steps_for(run)
      completed_ids = Array(run.steps_log).map { |e| e["step_id"] }
      @skill.recipe_steps.reject { |s| completed_ids.include?(s["id"]) }
    end

    # Returns true if this paused run is being resumed after operator approval
    # for this specific step. Detected via pending_step_id == step["id"]; the
    # resume() path clears that field when called.
    def approval_already_granted_for?(step)
      @run.pending_step_id == step["id"] && @run.status == "running"
    end

    def pause_for_approval!(step)
      @run.update!(
        status: "paused_for_approval",
        pending_step_id: step["id"]
      )
    end

    def execute_step(step, captures)
      started_at = Time.current

      resolved_params = interpolate(step["params"] || {}, captures)

      result =
        if @dry_run
          { dry_run: true, would_dispatch: step["tool"], with_params: resolved_params }
        else
          dispatch_tool(step["tool"], resolved_params)
        end

      {
        result:      result,
        started_at:  started_at.iso8601,
        finished_at: Time.current.iso8601,
        error:       nil
      }
    rescue StandardError => e
      {
        result:      nil,
        started_at:  started_at.iso8601,
        finished_at: Time.current.iso8601,
        error:       "#{e.class}: #{e.message}"
      }
    end

    # Dispatches an MCP tool action via the registered tool class. Returns the
    # tool's response hash ({success:, data:/error:}).
    #
    # Principal guard: a recipe step needs *some* caller to attribute the
    # dispatch to. `@user` and `@agent` are independently optional (see
    # `initialize`, and `Ai::SkillRecipeRun belongs_to :user, optional: true`),
    # so refuse outright when both are nil rather than let it fall through to
    # a downstream "permission denied: <perm> required" that reads like a
    # misconfigured grant. This guard refuses only the *no-principal* case.
    #
    # CORRECTED (IMP-245d8ae56f8c): this comment used to claim an agent-only
    # principal is legitimate because it is "the same LLM tool-calling path
    # McpPlatformToolRegistrar already recognizes for a bound mcp_agent". That
    # was false, and it is worth naming because it justified skipping the gate.
    # #enforce_permission! exempts exactly one user-less caller — an
    # `instance_authorized` mTLS principal — and otherwise raises
    # "Authentication required" whenever `user` is nil. A bound `mcp_agent` is
    # passed to CONSTRUCTION, never to authorization, so it has never stood in
    # for a permission.
    #
    # So an agent-only recipe now reaches the gate and is refused there, which
    # is the correct outcome rather than a regression: a recipe is
    # caller-supplied content, and "an agent authored it" is not authority to
    # run a tool the agent's principal cannot be checked against. The guard
    # below still admits it, because refusing at the gate produces the accurate
    # error; refusing here would report a missing principal that is present.
    #
    # `internal:` is deliberately NEVER passed to `klass.new` below. A recipe
    # is arbitrary caller-supplied content (skill metadata), not an in-process
    # system caller — passing `internal: true` (or inferring it from a nil
    # user) would hand every recipe the exact permission-gate bypass that
    # `Ai::Tools::BaseTool#internal?` exists to restrict, reopening the hole
    # IMP-9030413bc292 closed across SystemFleetTool/SdwanTool/SystemAcmeTool/
    # SystemIngressTool/SystemStorageOwnerTool/SystemPackageRepositoryTool/
    # SystemArchitectureCatalogTool. Do not "helpfully" add it here.
    def dispatch_tool(tool_name, params)
      raise RecipeError, "Step missing 'tool' name" if tool_name.blank?
      if @user.nil? && @agent.nil?
        raise RecipeError, "No principal for tool dispatch: recipe run has neither a user nor an agent"
      end

      tool_class_name = ::Ai::Tools::PlatformApiToolRegistry.all_tools[tool_name]
      raise RecipeError, "Unknown tool: #{tool_name}" if tool_class_name.blank?

      # IMP-245d8ae56f8c — dispatch through the REGISTRAR, not by constructing
      # the tool here.
      #
      # This used to do `klass.new(...).execute(...)` directly, which skipped
      # McpPlatformToolRegistrar#enforce_permission! — the ONLY reader of
      # REQUIRED_PERMISSION on an execution path. Ai::Tools::BaseTool#execute
      # runs the deny overlay, param validation and guardrails, and no
      # permission check at all, so for the 53 registry tool classes that carry
      # a floor constant and no ACTION_PERMISSIONS map the constant was
      # enforced NOWHERE on this path. The 12 map-carrying classes kept their
      # in-tool check, which made the hole invisible from the call site: the
      # same line was gated or ungated depending on the tool it named.
      #
      # Routing through execute_tool rather than re-implementing the check
      # keeps ONE enforcement seam, and picks up the rate limiter, the audit
      # log line and the action-scope check that the direct construction also
      # skipped.
      #
      # The `internal:` note above still holds and is now structural: this
      # method never constructs the tool, so it cannot pass `internal:` even by
      # accident.
      ::Ai::Tools::McpPlatformToolRegistrar.execute_tool(
        tool_name,
        params: params.merge(action: tool_name).with_indifferent_access,
        account: @account,
        user: @user,
        agent_id: @agent&.id,
        mcp_agent: @agent
      )
    end

    # === Variable interpolation =====================================
    #
    # Resolves `{{ inputs.x }}` and `{{ stepname.path.to.field }}` in any
    # nested structure (Hash, Array, String). Unrecognized paths resolve to
    # nil; the substituted value is preserved (so a Hash binding stays a
    # Hash, an Array stays an Array — only strings get string-substituted).

    def interpolate(value, captures)
      case value
      when Hash
        value.transform_values { |v| interpolate(v, captures) }
      when Array
        value.map { |v| interpolate(v, captures) }
      when String
        interpolate_string(value, captures)
      else
        value
      end
    end

    def interpolate_string(str, captures)
      # If the entire string is a single {{ ... }}, return the resolved value
      # as-is (preserves type). Otherwise, do string substitution.
      single_match = str.match(/\A\{\{\s*([^}]+?)\s*\}\}\z/)
      if single_match
        return resolve_path(single_match[1], captures)
      end

      str.gsub(INTERPOLATION_RE) { |_| resolve_path(Regexp.last_match(1), captures).to_s }
    end

    # Resolves a dotted path like "inputs.region" or "step1.data.results[0].name"
    # against the captures hash. Supports array indexing via [N].
    def resolve_path(path, captures)
      tokens = path.to_s.split(".")
      root = tokens.shift
      current =
        case root
        when "inputs" then @inputs
        else captures[root]
        end

      tokens.each do |token|
        # Support array indexing: "results[0]"
        if (m = token.match(/\A(\w+)\[(\d+)\]\z/))
          field, idx = m[1], m[2].to_i
          current = walk(current, field)
          current = current.is_a?(Array) ? current[idx] : nil
        else
          current = walk(current, token)
        end
        return nil if current.nil?
      end
      current
    end

    def walk(obj, key)
      case obj
      when Hash
        obj[key] || obj[key.to_sym]
      else
        nil
      end
    end

    # === Run lifecycle helpers ========================================

    def record_step!(step, step_result)
      @run.append_step!(
        "step_id"     => step["id"],
        "tool"        => step["tool"],
        "capture"     => step["capture"],
        "params_sent" => interpolate(step["params"] || {}, resume_captures_from(@run)),
        "result"      => step_result[:result],
        "started_at"  => step_result[:started_at],
        "finished_at" => step_result[:finished_at],
        "error"       => step_result[:error]
      )
      @run.save! unless @dry_run
    end

    def fail_run!(step, error_message)
      @run.update!(
        status:         "failed",
        failed_step_id: step&.dig("id"),
        error_message:  error_message,
        finished_at:    Time.current
      )
    end

    def finalize_run!(captures)
      output_template = @skill.recipe["output"] || {}
      resolved_output = interpolate(output_template, captures)

      @run.update!(
        status:           "completed",
        outputs:          resolved_output.is_a?(Hash) ? resolved_output : { value: resolved_output },
        pending_step_id:  nil,
        finished_at:      Time.current
      )
    end
  end
end
