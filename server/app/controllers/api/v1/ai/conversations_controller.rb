# frozen_string_literal: true

module Api
  module V1
    module Ai
      # Global conversations controller - manages conversations across all agents
      # Provides cross-agent conversation listing, filtering, and management
      class ConversationsController < ApplicationController
        include AuditLogging

        before_action :set_conversation, only: [ :show, :update, :destroy, :archive, :unarchive, :duplicate, :stats ]
        before_action :set_agent_for_nested, only: [ :active ]
        before_action :validate_permissions

        # =============================================================================
        # GLOBAL CONVERSATION ACTIONS
        # =============================================================================

        # GET /api/v1/ai/conversations
        def index
          conversations = current_user.account.ai_conversations
                                    .includes(:user, :agent, :provider)
                                    .order(last_activity_at: :desc)

          conversations = apply_filters(conversations)
          conversations = apply_pagination(conversations)

          render_success({
            conversations: conversations.map { |c| serialize_conversation(c) },
            pagination: pagination_data(conversations)
          })
        end

        # GET /api/v1/ai/agents/:agent_id/conversations/active
        def active
          conversations = @agent.conversations
                                .where(status: "active")
                                .where(user_id: current_user.id)
                                .order(last_activity_at: :desc)
                                .limit(1)

          render_success(data: conversations.map { |c| serialize_conversation_detail(c) })
        end

        # POST /api/v1/ai/agents/:agent_id/conversations
        def create
          agent = current_user.account.ai_agents.find(params[:agent_id])

          # Validate provider availability before creating conversation
          ProviderAvailabilityService.validate_agent_provider!(agent)

          conversation = agent.conversations.build(
            conversation_params.merge(
              conversation_id: SecureRandom.uuid,
              user_id: current_user.id,
              account_id: current_user.account_id,
              ai_provider_id: agent.ai_provider_id,
              status: "active",
              last_activity_at: Time.current
            )
          )

          if conversation.save
            render_success({
              conversation: serialize_conversation_detail(conversation)
            }, status: :created)

            log_audit_event("ai.conversations.create", conversation)
          else
            render_validation_error(conversation.errors)
          end
        rescue ActiveRecord::RecordNotFound
          render_error("Agent not found", status: :not_found)
        rescue ProviderAvailabilityService::ProviderUnavailableError => e
          render_error(e.message, status: :precondition_failed)
        end

        # GET /api/v1/ai/conversations/:id
        def show
          render_success({
            conversation: serialize_conversation_detail(@conversation)
          })
        end

        # PATCH /api/v1/ai/conversations/:id
        def update
          if @conversation.update(conversation_params)
            render_success({
              conversation: serialize_conversation_detail(@conversation)
            })

            log_audit_event("ai.conversations.update", @conversation)
          else
            render_validation_error(@conversation.errors)
          end
        end

        # DELETE /api/v1/ai/conversations/:id
        def destroy
          @conversation.destroy!

          render_success({
            message: "Conversation deleted successfully"
          })

          log_audit_event("ai.conversations.delete", @conversation)
        rescue ActiveRecord::RecordNotDestroyed => e
          render_error("Failed to delete conversation: #{e.message}", status: :unprocessable_content)
        end

        # POST /api/v1/ai/conversations/:id/archive
        def archive
          @conversation.archive_conversation!

          render_success({
            conversation: serialize_conversation(@conversation),
            message: "Conversation archived successfully"
          })

          log_audit_event("ai.conversations.archive", @conversation)
        rescue ActiveRecord::RecordInvalid => e
          render_error("Failed to archive conversation: #{e.message}", status: :unprocessable_content)
        end

        # POST /api/v1/ai/conversations/:id/unarchive
        def unarchive
          @conversation.update!(status: "completed")

          render_success({
            conversation: serialize_conversation(@conversation),
            message: "Conversation restored successfully"
          })

          log_audit_event("ai.conversations.unarchive", @conversation)
        rescue ActiveRecord::RecordInvalid => e
          render_error("Failed to restore conversation: #{e.message}", status: :unprocessable_content)
        end

        # POST /api/v1/ai/conversations/:id/duplicate
        def duplicate
          new_title = params[:title] || "Copy of #{@conversation.title}"
          include_messages = params[:include_messages] == "true" || params[:include_messages] == true

          # Create new conversation with same settings
          new_conversation = current_user.account.ai_conversations.build(
            user: current_user,
            agent: @conversation.agent,
            provider: @conversation.provider,
            title: new_title,
            status: "active",
            is_collaborative: @conversation.is_collaborative?,
            participants: @conversation.participants
          )

          if new_conversation.save
            # Copy messages if requested
            if include_messages
              @conversation.messages.ordered.each do |message|
                new_conversation.messages.create!(
                  role: message.role,
                  content: message.content,
                  message_type: message.message_type,
                  user: message.user,
                  agent: message.agent,
                  sequence_number: message.sequence_number
                )
              end
            end

            render_success({
              conversation: serialize_conversation_detail(new_conversation),
              message: "Conversation duplicated successfully"
            }, status: :created)

            log_audit_event("ai.conversations.duplicate", new_conversation,
              original_conversation_id: @conversation.conversation_id,
              included_messages: include_messages
            )
          else
            render_validation_error(new_conversation.errors)
          end
        rescue StandardError => e
          render_error("Failed to duplicate conversation: #{e.message}", status: :unprocessable_content)
        end

        # POST /api/v1/ai/agents/:agent_id/conversations/:id/send_message
        # Send a message in a conversation and get AI response
        def send_message
          # Find agent and conversation from nested route
          agent = current_user.account.ai_agents.find(params[:agent_id])
          conversation = agent.conversations.find(params[:id])

          # Validate conversation can receive messages
          unless conversation.can_send_message?
            return render_error("Conversation is not active", status: :unprocessable_content)
          end

          # Validate message content
          content = message_params[:content]
          if content.blank?
            return render_error("Message content cannot be blank", status: :unprocessable_content)
          end

          # Create user message
          user_message = conversation.add_user_message(
            content,
            user: current_user,
            message_type: message_params[:message_type] || "text",
            content_metadata: message_params[:metadata] || {}
          )

          # Check for active container instance — route through bridge if present
          bridge = ::Ai::ContainerChatBridgeService.new(account: current_user.account)
          if bridge.has_active_container?(conversation.id)
            bridge_result = bridge.route_message_to_container(
              conversation_id: conversation.id,
              message: { content: content, role: "user" }
            )

            if bridge_result[:routed]
              return render_success({
                user_message: serialize_message(user_message),
                assistant_message: nil,
                container_routed: true,
                container_execution_id: bridge_result[:container_execution_id],
                conversation: {
                  id: conversation.id,
                  message_count: conversation.reload.message_count
                }
              })
            end
          end

          # Build conversation history for AI
          messages_for_ai = build_messages_for_ai(conversation, agent)

          # Get AI response from provider
          assistant_response = generate_ai_response(agent, messages_for_ai)

          if assistant_response[:success]
            # Create assistant message
            assistant_message = conversation.add_assistant_message(
              assistant_response[:content],
              message_type: "text",
              token_count: assistant_response[:usage]&.dig(:total_tokens) || 0,
              cost_usd: calculate_cost(assistant_response[:usage], agent.provider),
              processing_metadata: {
                model: assistant_response[:model],
                finish_reason: assistant_response[:finish_reason],
                usage: assistant_response[:usage]
              }
            )

            render_success({
              user_message: serialize_message(user_message),
              assistant_message: serialize_message(assistant_message),
              conversation: {
                id: conversation.id,
                message_count: conversation.reload.message_count,
                total_tokens: conversation.total_tokens,
                total_cost: conversation.total_cost&.to_f
              }
            })

            log_audit_event("ai.conversations.send_message", conversation,
              user_message_id: user_message.id,
              assistant_message_id: assistant_message.id
            )
          else
            # AI response failed - still return user message but with error
            render_success({
              user_message: serialize_message(user_message),
              assistant_message: nil,
              error: assistant_response[:error],
              conversation: {
                id: conversation.id,
                message_count: conversation.reload.message_count
              }
            }, status: :partial_content)
          end
        rescue ActiveRecord::RecordNotFound
          render_error("Agent or conversation not found", status: :not_found)
        rescue ActiveRecord::RecordInvalid => e
          render_error("Failed to create message: #{e.message}", status: :unprocessable_content)
        rescue StandardError => e
          Rails.logger.error "[CONVERSATIONS] send_message error: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
          render_internal_error("Failed to send message", exception: e)
        end

        # GET /api/v1/ai/agents/:agent_id/conversations/:id/messages
        # Get all messages in a conversation
        def messages
          agent = current_user.account.ai_agents.find(params[:agent_id])
          conversation = agent.conversations.includes(messages: :user).find(params[:id])

          messages = conversation.messages.ordered
          messages = messages.page(params[:page] || 1).per(params[:per_page] || 50)

          render_success({
            messages: messages.map { |m| serialize_message(m) },
            pagination: {
              current_page: messages.current_page,
              per_page: messages.limit_value,
              total_pages: messages.total_pages,
              total_count: messages.total_count
            }
          })
        rescue ActiveRecord::RecordNotFound
          render_error("Agent or conversation not found", status: :not_found)
        end

        # GET /api/v1/ai/conversations/:id/stats
        def stats
          # Calculate statistics from messages
          messages = @conversation.messages

          # Calculate average response time (time between user message and next assistant message)
          response_times = []
          messages.ordered.each_cons(2) do |msg1, msg2|
            if msg1.role == "user" && msg2.role == "assistant"
              response_times << (msg2.created_at - msg1.created_at)
            end
          end

          avg_response_time = response_times.any? ? (response_times.sum / response_times.size) : 0

          # Calculate conversation duration
          first_message = messages.ordered.first
          last_message = messages.ordered.last
          duration = if first_message && last_message && first_message != last_message
                      (last_message.created_at - first_message.created_at)
          else
                      0
          end

          stats = {
            message_count: @conversation.message_count,
            token_usage: @conversation.total_tokens,
            avg_response_time: avg_response_time.round(2),
            duration: duration.round(2),
            total_cost: @conversation.total_cost&.to_f || 0.0,
            user_message_count: messages.user_messages.count,
            assistant_message_count: messages.assistant_messages.count,
            system_message_count: messages.system_messages.count,
            first_message_at: first_message&.created_at&.iso8601,
            last_message_at: last_message&.created_at&.iso8601,
            status: @conversation.status,
            is_collaborative: @conversation.is_collaborative?,
            participant_count: @conversation.participants.size
          }

          render_success({ stats: stats })
        rescue StandardError => e
          render_internal_error("Failed to retrieve conversation stats", exception: e)
        end

        private

        # =============================================================================
        # RESOURCE LOADING
        # =============================================================================

        def set_agent_for_nested
          @agent = current_user.account.ai_agents.find(params[:agent_id])
        rescue ActiveRecord::RecordNotFound
          render_error("Agent not found", status: :not_found)
        end

        def set_conversation
          # Try to find by id first (primary key), then by conversation_id (UUID field)
          @conversation = current_user.account.ai_conversations
                           .includes(:user, :agent, :provider, messages: [:user])
                           .find_by(id: params[:id]) ||
                         current_user.account.ai_conversations
                           .includes(:user, :agent, :provider, messages: [:user])
                           .find_by(conversation_id: params[:id])

          unless @conversation
            render_error("Conversation not found", status: :not_found)
          end
        end

        # =============================================================================
        # AUTHORIZATION
        # =============================================================================

        def validate_permissions
          case action_name
          when "index", "show", "stats", "messages", "active"
            require_permission("ai.conversations.read")
          when "create", "duplicate", "send_message"
            require_permission("ai.conversations.create")
          when "update", "archive", "unarchive"
            require_permission("ai.conversations.update")
          when "destroy"
            require_permission("ai.conversations.delete")
          end
        end

        # =============================================================================
        # PARAMETER HANDLING
        # =============================================================================

        def conversation_params
          params.require(:conversation).permit(
            :title, :status, :is_collaborative,
            participants: [],
            metadata: {}
          )
        end

        def message_params
          params.require(:message).permit(:content, :message_type, metadata: {})
        end

        # =============================================================================
        # AI MESSAGE GENERATION
        # =============================================================================

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
            memories = Ai::ContextPersistenceService.get_relevant_memories(agent: agent, limit: 10)
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
              learning_service = Ai::Learning::CompoundLearningService.new(account: agent.account)
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

          # Get provider client service (requires credential, not provider)
          client = ::Ai::ProviderClientService.new(credential)

          # Send messages to provider
          result = client.send_message(messages, {
            model: model,
            temperature: agent.temperature || 0.7,
            max_tokens: agent.max_tokens || 2048
          })

          if result[:success]
            # Extract content from response - ProviderClientService returns :response, not :data
            response_data = result[:response]
            content = extract_content_from_response(response_data)

            {
              success: true,
              content: content,
              model: model,
              usage: response_data&.dig(:usage),
              finish_reason: response_data&.dig(:choices, 0, :finish_reason) || "stop"
            }
          else
            {
              success: false,
              error: result[:error] || "Failed to generate AI response"
            }
          end
        rescue StandardError => e
          Rails.logger.error "[CONVERSATIONS] AI response generation error: #{e.message}"
          { success: false, error: "AI service error: #{e.message}" }
        end

        # Extract text content from various provider response formats
        def extract_content_from_response(data)
          return "" unless data

          # Handle different response structures
          if data.is_a?(String)
            data
          elsif data[:content].is_a?(Array)
            # Anthropic format: content is array of content blocks
            data[:content].map { |c| c[:text] || c["text"] }.compact.join("\n")
          elsif data[:content].is_a?(String)
            data[:content]
          elsif data[:choices].is_a?(Array)
            # OpenAI format: choices array with message
            data[:choices].first&.dig(:message, :content) ||
              data[:choices].first&.dig("message", "content") || ""
          elsif data[:message].is_a?(Hash)
            # Ollama format
            data[:message][:content] || data[:message]["content"] || ""
          elsif data[:response]
            # Simple response format
            data[:response]
          else
            data.to_s
          end
        end

        # Calculate cost based on token usage
        def calculate_cost(usage, provider)
          return 0.0 unless usage

          # Get token counts
          input_tokens = usage[:prompt_tokens] || usage["prompt_tokens"] || 0
          output_tokens = usage[:completion_tokens] || usage["completion_tokens"] || 0

          # Get pricing from provider (defaults for common providers)
          pricing = provider.pricing_info || {}
          input_cost_per_1k = pricing["input_cost_per_1k_tokens"] || 0.0
          output_cost_per_1k = pricing["output_cost_per_1k_tokens"] || 0.0

          # Calculate cost
          ((input_tokens / 1000.0) * input_cost_per_1k + (output_tokens / 1000.0) * output_cost_per_1k).round(6)
        end

        # =============================================================================
        # FILTERING & SORTING
        # =============================================================================

        def apply_filters(conversations)
          # Filter by status
          conversations = conversations.where(status: params[:status]) if params[:status].present?

          # Filter by agent
          conversations = conversations.where(ai_agent_id: params[:agent_id]) if params[:agent_id].present?

          # Filter by user
          conversations = conversations.where(user_id: params[:user_id]) if params[:user_id].present?

          # Search by title
          if params[:search].present?
            search_term = "%#{params[:search]}%"
            conversations = conversations.where("title ILIKE ?", search_term)
          end

          conversations
        end

        def apply_pagination(collection)
          page = params[:page]&.to_i || 1
          per_page = [ params[:per_page]&.to_i || 25, 100 ].min

          collection.page(page).per(per_page)
        end

        def pagination_data(collection)
          {
            current_page: collection.current_page,
            per_page: collection.limit_value,
            total_pages: collection.total_pages,
            total_count: collection.total_count
          }
        end

        # =============================================================================
        # SERIALIZATION
        # =============================================================================

        def serialize_conversation(conversation)
          {
            id: conversation.id,
            conversation_id: conversation.conversation_id,
            title: conversation.title || "Conversation with #{conversation.provider.name}",
            status: conversation.status,
            message_count: conversation.message_count,
            total_tokens: conversation.total_tokens,
            total_cost: conversation.total_cost&.to_f,
            is_collaborative: conversation.is_collaborative?,
            participant_count: conversation.participants.size,
            created_at: conversation.created_at.iso8601,
            last_activity_at: conversation.last_activity_at&.iso8601,
            ai_agent: conversation.agent ? {
              id: conversation.agent.id,
              name: conversation.agent.name,
              agent_type: conversation.agent.agent_type
            } : nil,
            provider: {
              id: conversation.provider.id,
              name: conversation.provider.name,
              provider_type: conversation.provider.provider_type
            },
            user: {
              id: conversation.user.id,
              name: conversation.user.full_name,
              email: conversation.user.email
            }
          }
        end

        def serialize_conversation_detail(conversation)
          serialize_conversation(conversation).merge(
            summary: conversation.summary,
            websocket_channel: conversation.websocket_channel,
            websocket_session_id: conversation.websocket_session_id,
            # participants is stored as JSONB array in the database
            participants: conversation.is_collaborative? ? (conversation.participants || []) : [],
            recent_messages: conversation.messages.recent.limit(10).map { |m| serialize_message(m) },
            metadata: {
              can_send_message: conversation.can_send_message?,
              active_session: conversation.websocket_session_id.present?
            }
          )
        end

        def serialize_message(message)
          message.message_data
        end
      end
    end
  end
end
