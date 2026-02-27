# frozen_string_literal: true

module Ai
  module Missions
    class PrdGenerationService
      include Ai::Concerns::PromptTemplateLookup
      include AgentBackedService

      class PrdGenerationError < StandardError; end

      PROMPT_SLUG = "ai-prd-generation"
      FALLBACK_PROMPT = <<~LIQUID
        You are a senior software architect creating a Product Requirements Document (PRD).
        Your job is to break down a feature into concrete, implementable tasks.

        Output ONLY valid JSON with this structure:
        {
          "title": "Feature title",
          "description": "Brief description of the feature",
          "tasks": [
            {
              "key": "task_1",
              "name": "Short task name",
              "description": "Detailed description of what to implement",
              "priority": 1,
              "acceptance_criteria": "What defines this task as complete",
              "dependencies": []
            }
          ]
        }

        Rules:
        - Break work into 2-8 discrete tasks, ordered by dependency
        - Each task should be completable by a single AI agent in one pass
        - Include file paths and specific changes when possible
        - Tasks should reference concrete files based on the repo structure
        - Use sequential keys: task_1, task_2, etc.
        - Priority: 1 = highest, higher numbers = lower priority
        - List task key dependencies (e.g. ["task_1"] means depends on task_1)
        - Output ONLY the JSON object, no markdown fences or commentary
      LIQUID

      attr_reader :mission, :account

      def initialize(mission:)
        @mission = mission
        @account = mission.account
      end

      # Orchestrates: validate → AI call → parse response → create RalphLoop
      # Returns the generated PRD hash
      def generate!
        validate!
        agent = discover_service_agent(
          "Generate a Product Requirement Document by decomposing features into implementable tasks",
          fallback_slug: "prd-generator"
        )
        raise PrdGenerationError, "No PRD Generator agent configured" unless agent

        client = build_agent_client(agent)
        messages = build_messages

        response = client.complete(messages: messages, model: agent_model(agent), max_tokens: agent_max_tokens(agent), temperature: agent_temperature(agent))
        raise PrdGenerationError, "AI provider returned error: #{response.content}" unless response.success?

        response_text = response.content
        raise PrdGenerationError, "AI returned empty response" if response_text.blank?

        prd_data = parse_prd_from_response(response_text)
        ralph_loop = create_ralph_loop_with_tasks!(prd_data)

        mission.update!(
          prd_json: prd_data,
          ralph_loop: ralph_loop
        )

        prd_data
      rescue PrdGenerationError
        raise
      rescue StandardError => e
        Rails.logger.error("[PrdGenerationService] #{e.message}\n#{e.backtrace.first(5).join("\n")}")
        raise PrdGenerationError, "PRD generation failed: #{e.message}"
      end

      private

      def validate!
        raise PrdGenerationError, "Mission must have a selected feature or objective" if
          mission.selected_feature.blank? && mission.objective.blank?
      end

      # Gets first active AI provider credential (mirrors RepoAnalysisService pattern)
      def build_messages
        system_prompt = resolve_prompt_template(
          PROMPT_SLUG,
          account: account,
          fallback: FALLBACK_PROMPT
        )

        user_content = build_user_message

        [
          { role: "system", content: system_prompt },
          { role: "user", content: user_content }
        ]
      end

      def build_user_message
        parts = []

        # Mission context
        parts << "## Objective"
        parts << (mission.objective || mission.name)

        # Selected feature details
        if mission.selected_feature.present?
          feature = mission.selected_feature
          parts << "\n## Selected Feature"
          parts << "Title: #{feature['title']}" if feature["title"]
          parts << "Description: #{feature['description']}" if feature["description"]
          parts << "Complexity: #{feature['complexity']}" if feature["complexity"]
          if feature["files_affected"].present?
            parts << "Files likely affected: #{Array(feature['files_affected']).join(', ')}"
          end
        end

        # Repository analysis context
        if mission.analysis_result.present?
          analysis = mission.analysis_result

          if analysis["tech_stack"].present?
            tech = analysis["tech_stack"]
            parts << "\n## Tech Stack"
            parts << "Dependencies: #{Array(tech['dependencies']).first(15).join(', ')}" if tech["dependencies"]
            parts << "Dev dependencies: #{Array(tech['dev_dependencies']).first(10).join(', ')}" if tech["dev_dependencies"]
          end

          if analysis.dig("structure", "entries").present?
            entries = analysis["structure"]["entries"]
            parts << "\n## Repository Structure"
            entries.first(40).each do |entry|
              prefix = entry["type"] == "tree" ? "[dir]" : "[file]"
              parts << "  #{prefix} #{entry['path']}"
            end
          end

          if analysis.dig("recent_activity", "recent_commits").present?
            commits = analysis["recent_activity"]["recent_commits"]
            parts << "\n## Recent Commits"
            commits.first(5).each do |c|
              parts << "  - #{c['sha']}: #{c['message']}"
            end
          end

          if analysis.dig("recent_activity", "open_issues").present?
            issues = analysis["recent_activity"]["open_issues"]
            parts << "\n## Open Issues"
            issues.first(5).each do |i|
              parts << "  - ##{i['number']}: #{i['title']}"
            end
          end
        end

        # Branch info
        parts << "\n## Branch"
        parts << "Working branch: #{mission.branch_name || 'TBD'}"
        parts << "Base branch: #{mission.base_branch || 'main'}"

        parts.join("\n")
      end

      # Parse PRD JSON from AI response text
      def parse_prd_from_response(text)
        # Try direct JSON parse
        parsed = JSON.parse(text)
        return normalize_prd(parsed) if parsed.is_a?(Hash) && parsed["tasks"]
      rescue JSON::ParserError
        # Try extracting from code fences
        if (match = text.match(/```(?:json)?\s*\n?(.*?)\n?\s*```/m))
          begin
            parsed = JSON.parse(match[1])
            return normalize_prd(parsed) if parsed.is_a?(Hash) && parsed["tasks"]
          rescue JSON::ParserError
            # Fall through
          end
        end

        # Try finding JSON object in text
        if (match = text.match(/\{.*"tasks"\s*:\s*\[.*\]/m))
          begin
            parsed = JSON.parse(match[0])
            return normalize_prd(parsed) if parsed.is_a?(Hash) && parsed["tasks"]
          rescue JSON::ParserError
            # Fall through
          end
        end

        # Fallback: single task from the objective
        Rails.logger.warn("[PrdGenerationService] Could not parse AI response as PRD JSON, using fallback")
        {
          "title" => mission.selected_feature&.dig("title") || mission.name,
          "description" => mission.objective,
          "tasks" => [{
            "key" => "task_1",
            "name" => "Implement feature",
            "description" => mission.objective,
            "priority" => 1,
            "acceptance_criteria" => "Feature works as described in the objective",
            "dependencies" => []
          }],
          "generated_at" => Time.current.iso8601
        }
      end

      def normalize_prd(parsed)
        parsed["generated_at"] = Time.current.iso8601
        parsed["title"] ||= mission.selected_feature&.dig("title") || mission.name
        parsed["description"] ||= mission.objective
        parsed
      end

      # Create RalphLoop and populate tasks using ExecutionService#parse_prd
      def create_ralph_loop_with_tasks!(prd_data)
        agent = find_default_agent
        raise PrdGenerationError, "No AI agent available for execution" unless agent

        ralph_loop = Ai::RalphLoop.create!(
          account: account,
          name: "Mission: #{mission.name}",
          description: "Auto-generated loop for mission #{mission.id}",
          status: "pending",
          default_agent: agent,
          mission: mission,
          repository_url: mission.repository&.clone_url,
          branch: mission.branch_name || "main",
          max_iterations: [prd_data["tasks"].size * 3, 30].min,
          prd_json: prd_data,
          configuration: { mission_id: mission.id }
        )

        # Use ExecutionService#parse_prd to create tasks from PRD
        exec_service = Ai::Ralph::ExecutionService.new(ralph_loop: ralph_loop)
        result = exec_service.parse_prd(prd_data)

        unless result[:success]
          ralph_loop.destroy!
          raise PrdGenerationError, "Failed to create tasks: #{result[:error]}"
        end

        Rails.logger.info("[PrdGenerationService] Created RalphLoop #{ralph_loop.id} with #{result[:tasks_created]} tasks")
        ralph_loop
      end

      # Priority: mission.team's first agent → account's first agent
      def find_default_agent
        if mission.team.present?
          agent = mission.team.agents.joins(:provider)
            .where(ai_providers: { is_active: true })
            .first
          return agent if agent
        end

        account.ai_agents.joins(:provider)
          .where(ai_providers: { is_active: true })
          .first
      end
    end
  end
end
