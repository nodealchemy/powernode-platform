# frozen_string_literal: true

# AiConversationResponseJob - Worker equivalent of the server's Ai::ConversationResponseJob
# Bridges the dispatch signature (conversation_id, message_id, user_id) to the
# existing AiChatResponseJob flow which handles streaming AI responses.
class AiConversationResponseJob < BaseJob
  include AiJobsConcern
  include AiSuspensionCheckConcern

  sidekiq_options queue: 'ai_conversations', retry: 2

  def execute(conversation_id, user_message_id, user_id)
    validate_required_params(
      { 'conversation_id' => conversation_id, 'user_message_id' => user_message_id,
        'user_id' => user_id },
      'conversation_id', 'user_message_id', 'user_id'
    )

    log_info("Starting conversation response",
      conversation_id: conversation_id,
      message_id: user_message_id)

    # Fetch conversation to get agent_id and account_id
    conv_response = api_client.get("/api/v1/ai/conversations/#{conversation_id}")
    unless conv_response['success']
      broadcast_error(conversation_id, "Failed to fetch conversation")
      return
    end

    conversation = conv_response['data']['conversation'] || conv_response['data']
    agent_id = conversation['ai_agent_id'] || conversation['agent_id'] ||
               conversation.dig('ai_agent', 'id')
    account_id = conversation['account_id'] || conversation.dig('user', 'account_id')

    # Resolve account_id from the user if not in conversation data
    if account_id.nil? && user_id.present?
      user_response = api_client.get("/api/v1/users/#{user_id}") rescue nil
      account_id = user_response&.dig('data', 'account_id') || user_response&.dig('data', 'user', 'account_id')
    end

    unless agent_id
      log_warn("Conversation has no agent assigned", conversation_id: conversation_id)
      return
    end

    unless account_id
      log_warn("Could not resolve account_id", conversation_id: conversation_id)
      return
    end

    # Kill switch check — bail if AI activity is suspended for the account
    return if bail_if_ai_suspended!(account_id)

    # Delegate to AiChatResponseJob which has the full streaming implementation
    AiChatResponseJob.new.execute(conversation_id, user_message_id, agent_id, account_id)
  end

  private

  def broadcast_error(conversation_id, message)
    api_client.post("/api/v1/internal/ai/conversations/#{conversation_id}/broadcast", {
      event: 'error',
      data: { error: message }
    })
  rescue StandardError => e
    log_error("Failed to broadcast error", e, conversation_id: conversation_id)
  end
end
