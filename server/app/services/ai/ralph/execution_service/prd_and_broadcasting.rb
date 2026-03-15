# frozen_string_literal: true

module Ai
  module Ralph
    class ExecutionService
      module PrdAndBroadcasting
        extend ActiveSupport::Concern

        # Parse PRD JSON and create tasks
        def parse_prd(prd_data)
          return error_result("PRD data is required") if prd_data.blank?

          ActiveRecord::Base.transaction do
            ralph_loop.update!(prd_json: prd_data)

            # Clear existing tasks if reparsing
            ralph_loop.ralph_tasks.destroy_all

            tasks = extract_tasks_from_prd(prd_data)
            created_tasks = tasks.map.with_index do |task_data, index|
              ralph_loop.ralph_tasks.create!(
                task_key: task_data[:key] || "task_#{index + 1}",
                description: task_data[:description],
                priority: task_data[:priority] || 0,
                position: index + 1,
                dependencies: task_data[:dependencies] || [],
                acceptance_criteria: task_data[:acceptance_criteria],
                metadata: task_data[:metadata] || {}
              )
            end

            ralph_loop.update!(total_tasks: created_tasks.count)

            success_result(
              tasks_created: created_tasks.count,
              tasks: created_tasks.map(&:task_summary)
            )
          end
        rescue StandardError => e
          error_result("Failed to parse PRD: #{e.message}")
        end

        private

        def extract_tasks_from_prd(prd_data)
          # Convert ActionController::Parameters to hash if needed
          prd_data = prd_data.to_unsafe_h if prd_data.respond_to?(:to_unsafe_h)

          # Handle different PRD formats
          if prd_data.is_a?(Array)
            prd_data.map { |item| normalize_task_data(item) }
          elsif prd_data.respond_to?(:[]) && prd_data["tasks"]
            prd_data["tasks"].map { |item| normalize_task_data(item) }
          elsif prd_data.is_a?(Hash)
            [ normalize_task_data(prd_data) ]
          else
            []
          end
        end

        def normalize_task_data(data)
          data = data.deep_stringify_keys if data.respond_to?(:deep_stringify_keys)

          {
            key: data["key"] || data["task_key"] || data["id"],
            description: data["description"] || data["title"] || data["name"],
            priority: data["priority"]&.to_i || 0,
            dependencies: Array(data["dependencies"] || data["depends_on"]),
            acceptance_criteria: data["acceptance_criteria"] || data["criteria"],
            metadata: data["metadata"] || {}
          }
        end

        def store_iteration_learnings(output)
          pool = ensure_ralph_learning_pool
          return unless pool

          storage = Ai::Memory::StorageService.new(account: account)
          count = storage.process_completed_task(
            pool: pool,
            output: output,
            agent_id: ralph_loop.default_agent&.id
          )
          Rails.logger.info("[Ralph] Stored #{count} learnings from iteration") if count.positive?

          promote_to_compound_learnings(output)
        rescue StandardError => e
          Rails.logger.warn("[Ralph] Learning storage failed: #{e.message}")
        end

        def promote_to_compound_learnings(output)
          return if output.blank?

          markers = { "Discovery:" => "discovery", "Pattern:" => "pattern",
                      "Anti-pattern:" => "failure_mode", "Best practice:" => "best_practice" }

          learnings_found = []
          markers.each do |marker, category|
            output.scan(/#{Regexp.escape(marker)}\s*(.+?)(?:\n\n|\z)/mi).flatten.each do |content|
              learnings_found << { content: content.strip, category: category }
            end
          end

          return if learnings_found.empty?

          service = Ai::Learning::CompoundLearningService.new(account: account)
          learnings_found.each do |learning|
            service.store_learning(
              {
                title: learning[:content].truncate(100),
                content: learning[:content],
                category: learning[:category],
                extraction_method: "ralph_iteration",
                source_agent_id: ralph_loop.default_agent&.id,
                source_execution_successful: true,
                importance: 0.5,
                confidence: 0.4
              }
            )
          end
          Rails.logger.info("[Ralph] Promoted #{learnings_found.size} learnings to CompoundLearning")
        rescue StandardError => e
          Rails.logger.warn("[Ralph] CompoundLearning promotion failed: #{e.message}")
        end

        def ensure_ralph_learning_pool
          @ralph_pool ||= Ai::MemoryPool.find_or_create_by!(
            account: account,
            name: "Ralph Loop: #{ralph_loop.name}",
            pool_type: "shared",
            scope: "persistent"
          ) do |pool|
            pool.data = { "learnings" => [] }
            pool.access_control = { "public" => true, "agents" => [] }
            pool.persist_across_executions = true
          end
        rescue ActiveRecord::RecordInvalid
          # Pool already exists, find it
          Ai::MemoryPool.find_by(
            account: account,
            name: "Ralph Loop: #{ralph_loop.name}",
            pool_type: "shared",
            scope: "persistent"
          )
        end

        def inject_shared_learnings(task)
          storage = Ai::Memory::StorageService.new(account: account)
          context = storage.build_learning_context(
            query: task.description,
            max_chars: 1500
          )
          context || ""
        rescue StandardError => e
          Rails.logger.warn("[Ralph] Shared learning injection failed: #{e.message}")
          ""
        end

        # Broadcasting

        def broadcast_iteration_completed(iteration)
          AiOrchestrationChannel.broadcast_ralph_loop_iteration_completed(
            ralph_loop.reload, iteration.iteration_number
          )
        rescue StandardError => e
          Rails.logger.warn("Failed to broadcast iteration completed: #{e.message}")
        end

        def broadcast_task_status_changed(task)
          AiOrchestrationChannel.broadcast_ralph_loop_task_status_changed(
            ralph_loop, task
          )
        rescue StandardError => e
          Rails.logger.warn("Failed to broadcast task status changed: #{e.message}")
        end

        def broadcast_progress
          AiOrchestrationChannel.broadcast_ralph_loop_progress(ralph_loop)
        rescue StandardError => e
          Rails.logger.warn("Failed to broadcast progress: #{e.message}")
        end
      end
    end
  end
end
