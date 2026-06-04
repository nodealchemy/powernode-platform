# frozen_string_literal: true

require "rails_helper"

RSpec.describe AiConversationChannel, type: :channel do
  # Regression: the WebSocket serializer previously merged only a subset of
  # content_metadata (actions/action_context/concierge_action/action_params/
  # mentions) and silently dropped `cards`. Rich chat cards therefore rendered
  # only on the immediate HTTP concierge response and vanished over live
  # broadcasts. A2UI surfaces ride the same `cards`/`a2ui_surface` keys, so the
  # serializer MUST pass them through.
  describe ".serialize_message content_metadata pass-through" do
    let(:card) do
      { "kind" => "provisioning_brief", "tool" => "capture_brief",
        "payload" => { "brief" => { "name" => "demo" } } }
    end

    let(:a2ui_surface) do
      { "version" => "v0.9", "surface_id" => "main",
        "surface" => { "createSurface" => { "surfaceId" => "main" } } }
    end

    let(:message) do
      create(:ai_message, :ai_response,
             content_metadata: {
               "cards" => [card],
               "a2ui_surface" => a2ui_surface,
               "actions" => [{ "type" => "approve" }]
             })
    end

    subject(:serialized) { described_class.send(:serialize_message, message) }

    it "includes rich chat cards in the broadcast metadata" do
      expect(serialized[:metadata][:cards]).to eq([card])
    end

    it "includes the a2ui_surface in the broadcast metadata" do
      expect(serialized[:metadata][:a2ui_surface]).to eq(a2ui_surface)
    end

    it "still passes the existing action metadata through" do
      expect(serialized[:metadata][:actions]).to eq([{ "type" => "approve" }])
    end
  end
end
