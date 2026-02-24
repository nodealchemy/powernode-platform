# frozen_string_literal: true

class Ai::McpAgentExecutor
  module MemoryWriteback
    extend ActiveSupport::Concern

    private

    def write_back_to_memory(execution_context, result)
      @logger.debug "[MemoryWriteback] Starting post-execution write-back"

      write_experiential_memory(execution_context, result)
      write_working_memory_state(execution_context, result)
      write_short_term_memory(execution_context, result)
      extract_and_store_facts(result)
      extract_compound_learnings(result)

      @logger.debug "[MemoryWriteback] Write-back completed"
    rescue StandardError => e
      @logger.warn "[MemoryWriteback] Top-level write-back failed: #{e.message}"
    end

    # Store execution input/output as experiential memory for future semantic search
    def write_experiential_memory(execution_context, result)
      storage = Ai::Memory::StorageService.new(account: @account, agent: @agent)

      input_text = execution_context[:input].to_s.truncate(500)
      output_text = result.dig("output").to_s.truncate(500)
      outcome_success = result.dig("metadata", "status") != "error"

      content = {
        "input_summary" => input_text,
        "output_summary" => output_text,
        "execution_id" => execution_context[:execution_id],
        "completed_at" => Time.current.iso8601
      }

      storage.store_experiential(
        content: content,
        context: { agent_type: @agent.agent_type, execution_id: execution_context[:execution_id] },
        outcome_success: outcome_success,
        tags: ["execution", @agent.agent_type].compact
      )
    rescue StandardError => e
      @logger.warn "[MemoryWriteback] Experiential memory write failed: #{e.message}"
    end

    # Persist working memory task state for cross-session continuity
    def write_working_memory_state(execution_context, result)
      working_memory = Ai::Memory::WorkingMemoryService.new(agent: @agent, account: @account)

      working_memory.store_task_state({
        "last_input" => execution_context[:input].to_s.truncate(300),
        "last_output" => result.dig("output").to_s.truncate(300),
        "completed_at" => Time.current.iso8601,
        "execution_id" => execution_context[:execution_id]
      })

      working_memory.persist_to_database("task_state")
    rescue StandardError => e
      @logger.warn "[MemoryWriteback] Working memory write failed: #{e.message}"
    end

    # Write to short-term memory for consolidation pipeline (STM→LTM→shared)
    # After 3 accesses, the STM callback auto-enqueues consolidation to CompoundLearning
    def write_short_term_memory(execution_context, result)
      return unless @agent && @execution

      execution_id = execution_context[:execution_id] || @execution.try(:execution_id) || @execution.try(:id)
      return unless execution_id

      Ai::AgentShortTermMemory.create!(
        account: @account,
        agent: @agent,
        memory_type: "general",
        memory_key: "execution:#{execution_id}:summary",
        memory_value: {
          "input_summary" => execution_context[:input].to_s.truncate(300),
          "output_summary" => result.dig("output").to_s.truncate(300),
          "execution_id" => execution_id,
          "agent_type" => @agent.agent_type,
          "completed_at" => Time.current.iso8601
        },
        session_id: execution_id,
        ttl_seconds: 86_400,
        expires_at: 24.hours.from_now
      )
    rescue StandardError => e
      @logger.warn "[MemoryWriteback] STM write failed: #{e.message}"
    end

    # Scan output for marker-based facts and store them
    def extract_and_store_facts(result)
      output_text = result.dig("output").to_s
      return if output_text.blank?

      storage = Ai::Memory::StorageService.new(account: @account, agent: @agent)
      markers = Ai::Memory::StorageService::LEARNING_MARKERS

      markers.each do |marker, category|
        output_text.scan(/#{Regexp.escape(marker)}\s*(.+?)(?:\n|$)/i).each do |match|
          value = match[0].strip
          next if value.blank? || value.length < 5

          key = "auto:#{category}:#{Digest::SHA256.hexdigest(value)[0..7]}"
          storage.store_fact(
            key: key,
            value: value,
            metadata: { category: category, source: "auto_extraction" },
            source_type: "agent_output"
          )
        end
      end
    rescue StandardError => e
      @logger.warn "[MemoryWriteback] Fact extraction failed: #{e.message}"
    end

    # Extract compound learnings from execution result
    def extract_compound_learnings(result)
      return unless @execution

      service = Ai::Learning::CompoundLearningService.new(account: @account)
      service.post_execution_extract(@execution)
    rescue StandardError => e
      @logger.warn "[MemoryWriteback] Compound learning extraction failed: #{e.message}"
    end
  end
end
