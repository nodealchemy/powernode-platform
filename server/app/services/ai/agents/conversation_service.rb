# frozen_string_literal: true

module Ai
  module Agents
    # Service for managing agent conversations
    #
    # Provides conversation management including:
    # - Conversation creation and updates
    # - Message sending
    # - Conversation lifecycle (pause, resume, complete, archive)
    # - Message regeneration and rating
    #
    # Usage:
    #   service = Ai::Agents::ConversationService.new(agent: agent, user: current_user)
    #   result = service.create(title: "New conversation")
    #
    class ConversationService
      attr_reader :agent, :user, :account

      Result = Struct.new(:success?, :data, :error, keyword_init: true)

      def initialize(agent:, user:)
        @agent = agent
        @user = user
        @account = user.account
      end

      # Create a new conversation
      # @param attributes [Hash] Conversation attributes
      # @return [Result] Creation result
      def create(attributes)
        conversation = agent.conversations.build(attributes)
        conversation.user = user
        conversation.account = account
        conversation.provider = agent.provider

        if conversation.save
          Result.new(success?: true, data: { conversation: conversation })
        else
          Result.new(success?: false, error: conversation.errors.full_messages.join(", "))
        end
      end

      # Update a conversation
      # @param conversation [Ai::Conversation] Conversation to update
      # @param attributes [Hash] Attributes to update
      # @return [Result] Update result
      def update(conversation, attributes)
        if conversation.update(attributes)
          Result.new(success?: true, data: { conversation: conversation })
        else
          Result.new(success?: false, error: conversation.errors.full_messages.join(", "))
        end
      end

      # Delete a conversation
      # @param conversation [Ai::Conversation] Conversation to delete
      # @return [Result] Delete result
      def destroy(conversation)
        if conversation.destroy
          Result.new(success?: true, data: { message: "Conversation deleted successfully" })
        else
          Result.new(success?: false, error: "Failed to delete conversation")
        end
      end

      # Send a message to the conversation
      # @param conversation [Ai::Conversation] Target conversation
      # @param content [String] Message content
      # @param metadata [Hash] Optional metadata
      # @return [Result] Message result
      def send_message(conversation, content:, metadata: {})
        message = conversation.add_user_message(
          content,
          user: user,
          metadata: metadata
        )

        Result.new(success?: true, data: { message: message })
      rescue StandardError => e
        Result.new(success?: false, error: "Failed to send message: #{e.message}")
      end

      # Pause a conversation
      # @param conversation [Ai::Conversation] Conversation to pause
      # @return [Result] Pause result
      def pause(conversation)
        conversation.pause_conversation!
        Result.new(success?: true, data: { conversation: conversation })
      rescue StandardError => e
        Result.new(success?: false, error: "Failed to pause conversation: #{e.message}")
      end

      # Resume a conversation
      # @param conversation [Ai::Conversation] Conversation to resume
      # @return [Result] Resume result
      def resume(conversation)
        conversation.resume_conversation!
        Result.new(success?: true, data: { conversation: conversation })
      rescue StandardError => e
        Result.new(success?: false, error: "Failed to resume conversation: #{e.message}")
      end

      # Complete a conversation
      # @param conversation [Ai::Conversation] Conversation to complete
      # @return [Result] Complete result
      def complete(conversation)
        conversation.complete_conversation!
        Result.new(success?: true, data: { conversation: conversation })
      rescue StandardError => e
        Result.new(success?: false, error: "Failed to complete conversation: #{e.message}")
      end

      # Archive a conversation
      # @param conversation [Ai::Conversation] Conversation to archive
      # @return [Result] Archive result
      def archive(conversation)
        conversation.archive_conversation!
        Result.new(success?: true, data: { conversation: conversation })
      rescue StandardError => e
        Result.new(success?: false, error: "Failed to archive conversation: #{e.message}")
      end

      # Export a conversation
      # @param conversation [Ai::Conversation] Conversation to export
      # @param format [String] Export format
      # @return [Hash] Export data
      def export(conversation, format: "json")
        {
          conversation: conversation,
          export_format: format,
          exported_at: Time.current.iso8601
        }
      end

      # Regenerate an assistant message
      # @param conversation [Ai::Conversation] Conversation containing the message
      # @param message [Ai::Message] Message to regenerate
      # @return [Result] Regeneration result
      def regenerate_message(conversation, message)
        unless message.role == "assistant"
          return Result.new(success?: false, error: "Can only regenerate assistant messages")
        end

        old_content = message.content
        message.update!(
          metadata: (message.processing_metadata || {}).merge(
            "regenerated" => true,
            "regenerated_at" => Time.current.iso8601,
            "original_content" => old_content
          )
        )

        regeneration_request = {
          message_id: message.id,
          conversation_id: conversation.id,
          agent_id: agent.id,
          requested_by: user.id,
          requested_at: Time.current.iso8601
        }

        Result.new(
          success?: true,
          data: {
            message: message.reload,
            regeneration_queued: true,
            regeneration_request: regeneration_request
          }
        )
      rescue StandardError => e
        Result.new(success?: false, error: "Failed to regenerate message: #{e.message}")
      end

      # Rate an assistant message
      # @param message [Ai::Message] Message to rate
      # @param rating [String] Rating value (thumbs_up or thumbs_down)
      # @param feedback [String] Optional feedback text
      # @return [Result] Rating result
      def rate_message(message, rating:, feedback: nil)
        unless message.role == "assistant"
          return Result.new(success?: false, error: "Can only rate assistant messages")
        end

        unless %w[thumbs_up thumbs_down].include?(rating)
          return Result.new(success?: false, error: "Rating must be thumbs_up or thumbs_down")
        end

        rating_data = {
          "rating" => rating,
          "rated_at" => Time.current.iso8601,
          "rated_by" => user.id
        }
        rating_data["feedback"] = feedback if feedback.present?

        message.update!(
          metadata: (message.processing_metadata || {}).merge("user_rating" => rating_data)
        )

        Result.new(
          success?: true,
          data: {
            message: message.reload,
            rating: rating_data
          }
        )
      rescue StandardError => e
        Result.new(success?: false, error: "Failed to rate message: #{e.message}")
      end
    end
  end
end
