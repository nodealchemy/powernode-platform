# frozen_string_literal: true

# AI response generation logic for conversations
#
# Extracted from ConversationsController to keep it under 300 lines.
# Handles building AI context and generating responses via providers.
module Ai
  module ConversationAiGeneration
    extend ActiveSupport::Concern

    private

    # Build messages array for AI provider from conversation history
    def build_messages_for_ai(conversation, agent)
      messages = []

      # Build enriched system prompt with all available context
      system_parts = []

      # 1. Agent base system prompt
      system_parts << agent.system_prompt if agent.system_prompt.present?

      # 2. Enabled skill system prompts and tool descriptions
      active_skills = agent.skills.joins(:agent_skills)
                           .where(ai_agent_skills: { is_active: true })
                           .where(status: "active")
      if active_skills.any?
        skill_lines = active_skills.filter_map do |skill|
          next unless skill.system_prompt.present? || skill.commands.present?
          parts = []
          parts << skill.system_prompt if skill.system_prompt.present?
          if skill.commands.present?
            cmds = skill.commands.map { |c| "- #{c['name']}: #{c['description']}" }.join("\n")
            parts << "Available commands:\n#{cmds}"
          end
          "### #{skill.name}\n#{parts.join("\n")}"
        end
        if skill_lines.any?
          system_parts << "## Skills & Tools\n#{skill_lines.join("\n\n")}"
        end
      end

      # 3. MCP tool capabilities
      if agent.mcp_tool_manifest.present?
        capabilities = agent.mcp_tool_manifest["capabilities"]
        if capabilities.is_a?(Array) && capabilities.any?
          system_parts << "## Capabilities\nYou have access to: #{capabilities.join(', ')}"
        end
      end

      # 4. Agent persistent memory
      begin
        memories = ::Ai::ContextPersistenceService.get_relevant_memories(agent: agent, limit: 10)
        if memories.present? && memories.any?
          memory_lines = memories.map do |entry|
            "- #{entry.entry_key}: #{entry.content_text.presence || entry.content.to_s.truncate(200)}"
          end
          system_parts << "## Shared Memory\n#{memory_lines.join("\n")}"
        end
      rescue StandardError => e
        Rails.logger.debug("[CONVERSATIONS] Memory retrieval skipped: #{e.message}")
      end

      # 5. Compound learnings (feature-flagged)
      begin
        last_user_msg = conversation.messages.where(role: "user").ordered.last
        if last_user_msg
          learning_service = ::Ai::Learning::CompoundLearningService.new(account: agent.account)
          result = learning_service.build_compound_context(
            agent: agent,
            task_description: last_user_msg.content,
            token_budget: 1000
          )
          system_parts << result[:context] if result[:context].present?
        end
      rescue StandardError => e
        Rails.logger.debug("[CONVERSATIONS] Compound learning injection skipped: #{e.message}")
      end

      # Combine into system message
      combined_system = system_parts.join("\n\n")
      if combined_system.present?
        messages << { role: "system", content: combined_system }
      end

      # Add conversation history (limit to last 20 messages for context window)
      conversation.messages.ordered.last(20).each do |msg|
        messages << { role: msg.role, content: msg.content }
      end

      messages
    end

    # Generate AI response using provider client
    def generate_ai_response(agent, messages)
      provider = agent.provider
      model = agent.model || provider.default_model

      # Get active credential for provider
      credential = provider.provider_credentials.where(is_active: true).first
      unless credential
        return { success: false, error: "No active credentials configured for provider #{provider.name}" }
      end

      # Build LLM client
      client = ::WorkerLlmClient.new(agent_id: agent.id)

      # Send messages to provider
      response = client.complete(
        messages: messages,
        model: model,
        temperature: agent.temperature || 0.7,
        max_tokens: agent.max_tokens || 2048
      )

      if response.success?
        {
          success: true,
          content: response.content,
          model: response.model || model,
          usage: response.usage,
          finish_reason: response.finish_reason || "stop"
        }
      else
        {
          success: false,
          error: response.raw_response&.dig(:error) || "Failed to generate AI response"
        }
      end
    rescue StandardError => e
      Rails.logger.error "[CONVERSATIONS] AI response generation error: #{e.message}"
      { success: false, error: "AI service error: #{e.message}" }
    end

    # Extract text content from various provider response formats
    def extract_content_from_response(data)
      return "" unless data

      if data.is_a?(String)
        data
      elsif data[:content].is_a?(Array)
        data[:content].map { |c| c[:text] || c["text"] }.compact.join("\n")
      elsif data[:content].is_a?(String)
        data[:content]
      elsif data[:choices].is_a?(Array)
        data[:choices].first&.dig(:message, :content) ||
          data[:choices].first&.dig("message", "content") || ""
      elsif data[:message].is_a?(Hash)
        data[:message][:content] || data[:message]["content"] || ""
      elsif data[:response]
        data[:response]
      else
        data.to_s
      end
    end

    # Calculate cost based on token usage
    def calculate_cost(usage, provider)
      return 0.0 unless usage

      input_tokens = usage[:prompt_tokens] || usage["prompt_tokens"] || 0
      output_tokens = usage[:completion_tokens] || usage["completion_tokens"] || 0

      pricing = provider.pricing_info || {}
      input_cost_per_1k = pricing["input_cost_per_1k_tokens"] || 0.0
      output_cost_per_1k = pricing["output_cost_per_1k_tokens"] || 0.0

      ((input_tokens / 1000.0) * input_cost_per_1k + (output_tokens / 1000.0) * output_cost_per_1k).round(6)
    end
  end
end
