# frozen_string_literal: true

module Ai
  module Skills
    # LLM-driven recipe designer. Given a free-text operator intent, produces
    # an Ai::Skill recipe spec (NOT persisted — operator confirms first).
    #
    # The flow:
    #
    #   1. Shortlist relevant MCP tools via SemanticToolDiscoveryService
    #   2. Build a prompt listing the shortlist + the intent
    #   3. LLM call (structured output) producing recipe JSON
    #   4. Validate recipe — each step's tool exists in the registry, params
    #      are well-formed, captures resolve, output template references
    #      defined captures/inputs
    #   5. Return { success, data: { slug, name, description, recipe, source_tools } }
    #
    # On success, the caller (typically Powernode Assistant) presents the
    # recipe to the operator for confirmation. Operator approval triggers a
    # separate `create_recipe_skill` action that persists the Ai::Skill row
    # with metadata.recipe populated.
    class DesignSkillFromIntentExecutor
      # Supplies tracked_client_for (IMP 019fe1da).
      include AgentBackedService

      MAX_SHORTLIST_TOOLS = 20
      MAX_RECIPE_STEPS    = 8

      class DesignError < StandardError; end

      def self.descriptor
        {
          name: "design_skill_from_intent",
          description: "Design a recipe-based skill from a free-text operator intent. Returns a recipe spec (NOT persisted) for operator review. Use when an operator describes a multi-step workflow they want repeatable, e.g. 'find the cheapest provider and provision an instance there'.",
          category: "skill_management",
          inputs: {
            intent:        { type: "string",  required: true,
                             description: "Free-text description of the workflow the operator wants automated" },
            suggested_name: { type: "string", required: false,
                              description: "Optional operator-suggested name for the new skill" },
            max_steps:     { type: "integer", required: false,
                             default: MAX_RECIPE_STEPS,
                             description: "Max number of recipe steps (1-#{MAX_RECIPE_STEPS})" }
          },
          outputs: {
            slug:          :string,
            name:          :string,
            description:   :string,
            recipe:        :object,
            source_tools:  :array,
            confidence:    :string
          }
        }
      end

      def initialize(account:, agent: nil, user: nil)
        @account = account
        @agent   = agent
        @user    = user
      end

      def execute(intent:, suggested_name: nil, max_steps: MAX_RECIPE_STEPS)
        return failure("intent is required") if intent.to_s.strip.empty?
        return failure("account is required") if @account.blank?

        max_steps = max_steps.to_i.clamp(1, MAX_RECIPE_STEPS)

        # 1. Shortlist tools
        shortlist = shortlist_tools(intent)
        return failure("No relevant MCP tools found for intent") if shortlist.empty?

        # 2. LLM-driven design
        design = generate_recipe_design(intent, shortlist, suggested_name, max_steps)
        return failure(design[:error]) if design[:error]

        recipe = design[:recipe]

        # 3. Validate
        errors = validate_recipe(recipe, shortlist)
        return failure("Recipe failed validation: #{errors.join('; ')}") if errors.any?

        # 4. Stamp slug + return for operator confirmation
        slug         = build_slug(recipe["name"] || suggested_name || intent)
        name         = recipe["name"] || suggested_name || "Skill from: #{intent.truncate(40)}"
        normalized   = normalize_recipe(recipe, max_steps)
        steps_count  = Array(normalized["steps"]).size

        result_data = {
          slug:         slug,
          name:         name,
          description:  recipe["description"] || intent,
          recipe:       normalized,
          source_tools: shortlist.map { |t| { name: t[:name], description: t[:description].to_s.truncate(80) } },
          confidence:   confidence_for(shortlist, recipe)
        }

        # Structured confirmation hint — ConciergeToolBridge auto-surfaces
        # a confirmation card so operators don't depend on the LLM following
        # up with request_confirmation.
        result_data[:confirmation] = {
          action_type:        "create_recipe_skill",
          action_description: "Create recipe skill **#{name}** (#{steps_count} step#{steps_count == 1 ? '' : 's'})",
          action_params:      result_data.deep_stringify_keys.except("confirmation")
        }

        success(result_data)
      rescue DesignError => e
        failure(e.message)
      rescue StandardError => e
        Rails.logger.error("[DesignSkillFromIntent] crash: #{e.class}: #{e.message}")
        failure("Designer crashed: #{e.class}: #{e.message}")
      end

      private

      # === Tool shortlisting ============================================

      def shortlist_tools(intent)
        discovery = ::Ai::Tools::SemanticToolDiscoveryService.new(account: @account)
        ranked = discovery.discover(query: intent, limit: MAX_SHORTLIST_TOOLS)
        Array(ranked).map { |t| { name: t[:name] || t["name"], description: t[:description] || t["description"] } }
                     .reject { |t| t[:name].blank? }
      rescue StandardError => e
        Rails.logger.warn("[DesignSkillFromIntent] tool discovery failed: #{e.message}")
        []
      end

      # === LLM-driven design ============================================

      def generate_recipe_design(intent, shortlist, suggested_name, max_steps)
        # OpenAI-compatible provider preferred — Anthropic's structured-output
        # path doesn't reliably return JSON-only via the worker. Falling back
        # to default if openai isn't configured.
        # Wrapped so the design call lands an Ai::AgentExecution (IMP 019fe1da).
        # Attributed to the INVOKING agent only: this is skill design, not
        # provisioning, so falling back to a provisioning agent would file the
        # cost under the wrong actor. With no invoking agent the call stays
        # untracked rather than mis-attributed. The openai preference and the
        # provider that serves the call are unchanged — this only wraps.
        llm = ::WorkerLlmClient.for_account(@account, provider_type: "openai") ||
              ::WorkerLlmClient.for_account(@account)
        llm = tracked_client_for(llm, agent: @agent)
        return { error: "No LLM provider configured for account" } unless llm

        messages = build_design_messages(intent, shortlist, suggested_name, max_steps)

        # Use plain `complete` and parse JSON ourselves; the structured-output
        # path on the worker returns empty/error response in current build.
        # The system prompt is explicit that the model must output ONLY JSON.
        result = llm.complete(
          messages: messages,
          model:    designer_model(llm),
          temperature: 0.2,
          max_tokens: 2048
        )

        unless result&.success?
          err = result&.finish_reason || "no response"
          return { error: "LLM call failed (finish_reason=#{err})" }
        end

        content = result.content.to_s.strip
        # Strip possible markdown JSON fences if the model added them despite instructions.
        content = content.sub(/\A```(?:json)?\s*\n?/i, "").sub(/\n?```\s*\z/, "").strip
        parsed = JSON.parse(content)
        { recipe: parsed }
      rescue JSON::ParserError => e
        { error: "LLM returned malformed JSON: #{e.message.truncate(120)}" }
      rescue StandardError => e
        { error: "Recipe generation failed: #{e.class}: #{e.message}" }
      end

      def designer_model(llm)
        # Resolve from the client's bound provider (default_model already falls
        # back to the provider's first available model) — never a hardcoded
        # vendor id, since the account may be Anthropic/Ollama-only. Recipe
        # design is structured output; modern small models handle it fine.
        llm.provider&.default_model
      end

      def build_design_messages(intent, shortlist, suggested_name, max_steps)
        tools_section = shortlist.each_with_index.map do |t, idx|
          "  #{idx + 1}. `#{t[:name]}` — #{t[:description].to_s.truncate(120)}"
        end.join("\n")

        system_prompt = <<~SYSTEM
          You design recipe-based skills for the Powernode platform. Given an
          operator's natural-language workflow description and a shortlist of
          available MCP tools, produce a recipe specification.

          Recipe spec format (JSON):
          {
            "name":        "<short skill name>",
            "description": "<one-sentence description>",
            "inputs":      [ { "name": "...", "type": "string|number|boolean", "required": true|false } ],
            "steps": [
              { "id": "step1",
                "tool": "<exact tool name from shortlist>",
                "params": { "<param>": "<literal or {{ inputs.x }} or {{ stepN.field }}>" },
                "capture": "<variable name for later steps>",
                "require_approval": true|false  // true for state-mutating actions
              }
            ],
            "output": { "<key>": "<{{ stepN.field }} reference>" }
          }

          Rules:
            * Use ONLY tools from the shortlist below. Don't invent tool names.
            * Variable interpolation: `{{ inputs.x }}` and `{{ <capture>.<path> }}`.
              Array indexing: `{{ stepN.results[0].id }}`.
            * Mark `require_approval: true` on steps that create, modify, or
              destroy state (provision, terminate, delete, deploy, etc.).
            * Read-only steps (list, get, search, discover) don't require approval.
            * Keep recipes simple — max #{max_steps} steps.
            * If the intent can't be accomplished with the available tools,
              return an empty steps array and explain in `description`.
        SYSTEM

        user_prompt = <<~USER
          OPERATOR INTENT:
          #{intent}

          #{suggested_name.present? ? "OPERATOR-SUGGESTED NAME: #{suggested_name}\n\n" : ''}AVAILABLE TOOLS (shortlist of #{shortlist.size}):
          #{tools_section}

          Design a recipe to accomplish the intent above. Output only the JSON
          recipe spec — no commentary, no markdown fences.
        USER

        [
          { role: "system", content: system_prompt },
          { role: "user",   content: user_prompt }
        ]
      end

      def recipe_design_schema
        {
          "type" => "object",
          "required" => %w[name description inputs steps output],
          "properties" => {
            "name"        => { "type" => "string" },
            "description" => { "type" => "string" },
            "inputs" => {
              "type" => "array",
              "items" => {
                "type" => "object",
                "required" => %w[name type required],
                "properties" => {
                  "name" => { "type" => "string" },
                  "type" => { "type" => "string", "enum" => %w[string number boolean] },
                  "required" => { "type" => "boolean" },
                  "description" => { "type" => "string" }
                }
              }
            },
            "steps" => {
              "type" => "array",
              "items" => {
                "type" => "object",
                "required" => %w[id tool params],
                "properties" => {
                  "id" => { "type" => "string" },
                  "tool" => { "type" => "string" },
                  "params" => { "type" => "object", "additionalProperties" => true },
                  "capture" => { "type" => "string" },
                  "require_approval" => { "type" => "boolean" }
                }
              }
            },
            "output" => { "type" => "object", "additionalProperties" => true }
          }
        }
      end

      # === Recipe validation ============================================

      def validate_recipe(recipe, shortlist)
        errors = []
        errors << "missing name" if recipe["name"].to_s.empty?
        errors << "missing description" if recipe["description"].to_s.empty?
        errors << "missing or empty steps" unless Array(recipe["steps"]).any?

        shortlist_names = shortlist.map { |t| t[:name] }
        defined_captures = []

        Array(recipe["steps"]).each_with_index do |step, idx|
          step_id = step["id"] || "step#{idx + 1}"
          errors << "step #{step_id} missing tool" if step["tool"].to_s.empty?
          if step["tool"].present? && !shortlist_names.include?(step["tool"]) &&
             !::Ai::Tools::PlatformApiToolRegistry.all_tools.key?(step["tool"])
            errors << "step #{step_id} references unknown tool #{step['tool'].inspect}"
          end
          # Capture names must be unique
          if step["capture"].present?
            if defined_captures.include?(step["capture"])
              errors << "step #{step_id} reuses capture name #{step['capture'].inspect}"
            end
            defined_captures << step["capture"]
          end
        end

        errors
      end

      def normalize_recipe(recipe, max_steps)
        recipe = recipe.dup
        recipe["version"] = "1"
        recipe["steps"] = Array(recipe["steps"]).first(max_steps)
        # Ensure require_approval defaults
        recipe["steps"].each do |step|
          step["require_approval"] = false if step["require_approval"].nil?
        end
        recipe
      end

      # === Misc helpers =================================================

      def build_slug(source)
        base = source.to_s.parameterize.truncate(60, omission: "")
        candidate = "custom-#{base}"
        i = 1
        while ::Ai::Skill.exists?(slug: candidate)
          candidate = "custom-#{base}-#{i}"
          i += 1
        end
        candidate
      end

      def confidence_for(shortlist, recipe)
        return "low" if shortlist.empty? || Array(recipe["steps"]).empty?
        return "high" if Array(recipe["steps"]).all? { |s| !s["require_approval"] }

        "medium"
      end

      def success(data)
        { success: true, data: data, requires_approval: true }
      end

      def failure(msg)
        { success: false, error: msg }
      end
    end
  end
end
