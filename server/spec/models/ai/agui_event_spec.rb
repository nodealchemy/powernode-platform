# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::AguiEvent, type: :model do
  let(:account) { create(:account) }
  let(:session) { create(:ai_agui_session, account: account) }

  describe "associations" do
    it { should belong_to(:session).class_name("Ai::AguiSession") }
    it { should belong_to(:account) }
  end

  describe "validations" do
    subject { build(:ai_agui_event, session: session, account: account, sequence_number: 99) }

    it { should validate_presence_of(:event_type) }
    it { should validate_inclusion_of(:event_type).in_array(Ai::AguiEvent::EVENT_TYPES) }
    it { should validate_presence_of(:sequence_number) }

    it "is valid with valid attributes" do
      event = build(:ai_agui_event, session: session, account: account)
      expect(event).to be_valid
    end

    it "is invalid with an unknown event_type" do
      event = build(:ai_agui_event, session: session, account: account, event_type: "UNKNOWN_EVENT")
      expect(event).not_to be_valid
    end

    it "enforces sequence_number uniqueness within session" do
      create(:ai_agui_event, session: session, account: account, sequence_number: 1)
      duplicate = build(:ai_agui_event, session: session, account: account, sequence_number: 1)
      expect(duplicate).not_to be_valid
    end

    it "allows same sequence_number in different sessions" do
      other_session = create(:ai_agui_session, account: account)
      create(:ai_agui_event, session: session, account: account, sequence_number: 1)
      other_event = build(:ai_agui_event, session: other_session, account: account, sequence_number: 1)
      expect(other_event).to be_valid
    end
  end

  describe "EVENT_TYPES constant" do
    it "contains all 19 AG-UI event types" do
      expect(Ai::AguiEvent::EVENT_TYPES.length).to eq(19)
    end

    it "includes text message events" do
      expect(Ai::AguiEvent::EVENT_TYPES).to include("TEXT_MESSAGE_START", "TEXT_MESSAGE_CONTENT", "TEXT_MESSAGE_END")
    end

    it "includes tool call events" do
      expect(Ai::AguiEvent::EVENT_TYPES).to include("TOOL_CALL_START", "TOOL_CALL_ARGS", "TOOL_CALL_END", "TOOL_CALL_RESULT")
    end

    it "includes state events" do
      expect(Ai::AguiEvent::EVENT_TYPES).to include("STATE_SNAPSHOT", "STATE_DELTA")
    end

    it "includes lifecycle events" do
      expect(Ai::AguiEvent::EVENT_TYPES).to include("RUN_STARTED", "RUN_FINISHED", "RUN_ERROR")
    end

    it "includes step events" do
      expect(Ai::AguiEvent::EVENT_TYPES).to include("STEP_STARTED", "STEP_FINISHED")
    end

    it "includes custom and raw events" do
      expect(Ai::AguiEvent::EVENT_TYPES).to include("CUSTOM", "RAW")
    end
  end

  describe "scopes" do
    let!(:text_event) { create(:ai_agui_event, :text_content, session: session, account: account, sequence_number: 1) }
    let!(:tool_event) { create(:ai_agui_event, :tool_call_start, session: session, account: account, sequence_number: 2) }
    let!(:run_event) { create(:ai_agui_event, :run_started, session: session, account: account, sequence_number: 3) }
    let!(:state_event) { create(:ai_agui_event, :state_delta, session: session, account: account, sequence_number: 4) }
    let!(:step_event) { create(:ai_agui_event, :step_started, session: session, account: account, sequence_number: 5) }

    it "returns text events" do
      expect(described_class.text_events).to include(text_event)
      expect(described_class.text_events).not_to include(tool_event)
    end

    it "returns tool events" do
      expect(described_class.tool_events).to include(tool_event)
      expect(described_class.tool_events).not_to include(text_event)
    end

    it "returns state events" do
      expect(described_class.state_events).to include(state_event)
    end

    it "returns lifecycle events" do
      expect(described_class.lifecycle_events).to include(run_event)
    end

    it "returns step events" do
      expect(described_class.step_events).to include(step_event)
    end

    it "returns events ordered by sequence" do
      ordered = described_class.where(session: session).ordered
      expect(ordered.map(&:sequence_number)).to eq([1, 2, 3, 4, 5])
    end

    it "returns events after a sequence number" do
      result = described_class.where(session: session).after_sequence(2)
      expect(result.pluck(:sequence_number)).to eq([3, 4, 5])
    end
  end

  describe "#text_event?" do
    it "returns true for TEXT_MESSAGE events" do
      event = build(:ai_agui_event, event_type: "TEXT_MESSAGE_CONTENT")
      expect(event.text_event?).to be true
    end

    it "returns false for non-text events" do
      event = build(:ai_agui_event, event_type: "TOOL_CALL_START")
      expect(event.text_event?).to be false
    end
  end

  describe "#tool_event?" do
    it "returns true for TOOL_CALL events" do
      event = build(:ai_agui_event, event_type: "TOOL_CALL_START")
      expect(event.tool_event?).to be true
    end

    it "returns false for non-tool events" do
      event = build(:ai_agui_event, event_type: "TEXT_MESSAGE_START")
      expect(event.tool_event?).to be false
    end
  end

  describe "#lifecycle_event?" do
    it "returns true for RUN events" do
      event = build(:ai_agui_event, event_type: "RUN_STARTED")
      expect(event.lifecycle_event?).to be true
    end

    it "returns false for non-lifecycle events" do
      event = build(:ai_agui_event, event_type: "TEXT_MESSAGE_START")
      expect(event.lifecycle_event?).to be false
    end
  end

  describe "#to_sse_data" do
    it "returns a hash suitable for SSE" do
      event = create(:ai_agui_event, :text_content, session: session, account: account, sequence_number: 1)
      data = event.to_sse_data

      expect(data[:type]).to eq("TEXT_MESSAGE_CONTENT")
      expect(data[:sequence]).to eq(1)
      expect(data[:content]).to eq("Hello, world!")
      expect(data[:timestamp]).to be_present
    end

    it "excludes nil values" do
      event = create(:ai_agui_event, session: session, account: account, sequence_number: 1,
                     event_type: "RUN_STARTED", tool_call_id: nil, message_id: nil)
      data = event.to_sse_data

      expect(data).not_to have_key(:tool_call_id)
      expect(data).not_to have_key(:message_id)
    end
  end
end
