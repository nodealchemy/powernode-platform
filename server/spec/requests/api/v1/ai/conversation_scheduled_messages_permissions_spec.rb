# frozen_string_literal: true

require "rails_helper"

# IMP-4fdae24c24a3 claimed Ai::ScheduledMessage "has no permission check at all on its
# actions". On the REST door it does: validate_permissions maps every
# scheduled_messages_* action to an ai.conversations.* permission, and the conversation
# is resolved inside the caller's account. These examples pin that so the claim cannot
# silently become true.
RSpec.describe "Api::V1::Ai::Conversations scheduled messages permissions", type: :request do
  let(:account) { create(:account) }
  let!(:owner) { create(:user, account: account) }
  let(:conversation) { create(:ai_conversation, account: account, user: owner) }
  let(:path) { "/api/v1/ai/conversations/#{conversation.id}/scheduled_messages" }
  let(:unprivileged) { create(:user, account: account, permissions: []) }

  it "refuses to list scheduled messages without ai.conversations.read" do
    get path, headers: auth_headers_for(unprivileged), as: :json

    expect(response).to have_http_status(:forbidden)
  end

  it "refuses to create a scheduled message without ai.conversations.create, writing nothing" do
    reader = create(:user, account: account, permissions: %w[ai.conversations.read])

    expect {
      post path, params: { scheduled_message: { content: "later" } }, headers: auth_headers_for(reader), as: :json
    }.not_to change(Ai::ScheduledMessage, :count)
    expect(response).to have_http_status(:forbidden)
  end

  it "does not resolve another account's conversation" do
    foreign = create(:ai_conversation, account: create(:account))
    reader = create(:user, account: account, permissions: %w[ai.conversations.read])

    get "/api/v1/ai/conversations/#{foreign.id}/scheduled_messages", headers: auth_headers_for(reader), as: :json

    expect(response).to have_http_status(:not_found)
  end

  it "lists them for a holder of ai.conversations.read" do
    reader = create(:user, account: account, permissions: %w[ai.conversations.read])

    get path, headers: auth_headers_for(reader), as: :json

    expect(response).to have_http_status(:ok)
  end
end
