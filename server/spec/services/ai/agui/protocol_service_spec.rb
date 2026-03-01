# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Agui::ProtocolService do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:service) { described_class.new(account: account) }

  describe "#create_session" do
    it "creates a new AG-UI session" do
      session = service.create_session(thread_id: "test_thread_1")

      expect(session).to be_persisted
      expect(session.thread_id).to eq("test_thread_1")
      expect(session.status).to eq("idle")
      expect(session.account).to eq(account)
      expect(session.expires_at).to be_present
    end

    it "associates a user when provided" do
      session = service.create_session(thread_id: "test_thread_2", user: user)

      expect(session.user).to eq(user)
    end

    it "stores tools and capabilities" do
      tools = [{ name: "calculator" }]
      capabilities = { streaming: true }

      session = service.create_session(
        thread_id: "test_thread_3",
        tools: tools,
        capabilities: capabilities
      )

      expect(session.tools).to eq([{ "name" => "calculator" }])
      expect(session.capabilities).to eq({ "streaming" => true })
    end

    it "stores agent_id when provided" do
      agent_id = SecureRandom.uuid
      session = service.create_session(thread_id: "test_thread_4", agent_id: agent_id)

      expect(session.agent_id).to eq(agent_id)
    end
  end

  describe "#get_session" do
    it "returns the session by id" do
      session = service.create_session(thread_id: "lookup_thread")
      found = service.get_session(session.id)

      expect(found.id).to eq(session.id)
    end

    it "raises RecordNotFound for unknown id" do
      expect { service.get_session(SecureRandom.uuid) }.to raise_error(ActiveRecord::RecordNotFound)
    end

    it "scopes by account" do
      other_account = create(:account)
      other_session = create(:ai_agui_session, account: other_account)

      expect { service.get_session(other_session.id) }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end

  describe "#list_sessions" do
    before do
      create(:ai_agui_session, :idle, account: account)
      create(:ai_agui_session, :running, account: account)
      create(:ai_agui_session, :completed, account: account)
    end

    it "returns all sessions for the account" do
      sessions = service.list_sessions
      expect(sessions.count).to eq(3)
    end

    it "filters by status" do
      sessions = service.list_sessions(status: "running")
      expect(sessions.count).to eq(1)
      expect(sessions.first.status).to eq("running")
    end

    it "filters by thread_id" do
      target = create(:ai_agui_session, account: account, thread_id: "specific_thread")
      sessions = service.list_sessions(thread_id: "specific_thread")
      expect(sessions).to include(target)
    end

    it "does not return sessions from other accounts" do
      other_account = create(:account)
      create(:ai_agui_session, account: other_account)

      sessions = service.list_sessions
      expect(sessions.count).to eq(3) # only the account's sessions
    end
  end

  describe "#destroy_session" do
    it "destroys the session" do
      session = service.create_session(thread_id: "destroy_thread")
      service.destroy_session(session.id)

      expect { Ai::AguiSession.find(session.id) }.to raise_error(ActiveRecord::RecordNotFound)
    end

    it "cancels active sessions before destroying" do
      session = create(:ai_agui_session, :running, account: account)
      service.destroy_session(session.id)

      expect { Ai::AguiSession.find(session.id) }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end

  describe "#run_agent" do
    let(:session) { service.create_session(thread_id: "run_thread") }

    it "starts and completes a run" do
      result = service.run_agent(session: session, input: "Hello")

      expect(result[:status]).to eq("completed")
      expect(result[:run_id]).to be_present
      expect(result[:session].status).to eq("completed")
    end

    it "emits RUN_STARTED and RUN_FINISHED events" do
      service.run_agent(session: session, input: "Test")

      events = session.agui_events.reload.ordered
      event_types = events.map(&:event_type)

      expect(event_types).to include("RUN_STARTED")
      expect(event_types).to include("RUN_FINISHED")
    end

    it "emits text message events" do
      service.run_agent(session: session, input: "Test")

      events = session.agui_events.reload.ordered
      event_types = events.map(&:event_type)

      expect(event_types).to include("TEXT_MESSAGE_START", "TEXT_MESSAGE_CONTENT", "TEXT_MESSAGE_END")
    end

    it "increments session sequence for each event" do
      service.run_agent(session: session, input: "Test")

      session.reload
      expect(session.sequence_number).to be > 0
    end
  end

  describe "#cancel_run" do
    it "cancels a running session" do
      session = create(:ai_agui_session, :running, account: account)
      result = service.cancel_run(session: session)

      expect(result[:success]).to be true
      expect(session.reload.status).to eq("cancelled")
    end

    it "returns error for non-running sessions" do
      session = create(:ai_agui_session, :idle, account: account)
      result = service.cancel_run(session: session)

      expect(result[:success]).to be false
    end
  end

  describe "#emit_text_stream" do
    let(:session) { create(:ai_agui_session, :running, account: account) }

    it "emits START, CONTENT, and END events" do
      service.emit_text_stream(session: session, message_id: "msg_1", delta: "Hello")

      events = session.agui_events.reload.ordered
      expect(events.count).to eq(3)
      expect(events.map(&:event_type)).to eq(%w[TEXT_MESSAGE_START TEXT_MESSAGE_CONTENT TEXT_MESSAGE_END])
    end

    it "sets role to assistant on START event" do
      service.emit_text_stream(session: session, message_id: "msg_2", delta: "Hi")

      start_event = session.agui_events.find_by(event_type: "TEXT_MESSAGE_START")
      expect(start_event.role).to eq("assistant")
    end
  end

  describe "#emit_tool_call" do
    let(:session) { create(:ai_agui_session, :running, account: account) }

    it "emits TOOL_CALL_START, TOOL_CALL_ARGS, and TOOL_CALL_END events" do
      service.emit_tool_call(
        session: session,
        tool_call_id: "tc_1",
        tool_name: "calculator",
        args_delta: { x: 1 }
      )

      events = session.agui_events.reload.ordered
      expect(events.count).to eq(3)
      expect(events.map(&:event_type)).to eq(%w[TOOL_CALL_START TOOL_CALL_ARGS TOOL_CALL_END])
    end
  end

  describe "#emit_tool_result" do
    let(:session) { create(:ai_agui_session, :running, account: account) }

    it "emits a TOOL_CALL_RESULT event" do
      service.emit_tool_result(
        session: session,
        message_id: "msg_1",
        tool_call_id: "tc_1",
        content: "42"
      )

      event = session.agui_events.reload.last
      expect(event.event_type).to eq("TOOL_CALL_RESULT")
      expect(event.content).to eq("42")
    end
  end

  describe "#emit_state_delta" do
    let(:session) { create(:ai_agui_session, :running, account: account) }

    it "emits a STATE_DELTA event" do
      delta = [{ "op" => "add", "path" => "/key", "value" => "val" }]
      service.emit_state_delta(session: session, delta: delta)

      event = session.agui_events.reload.last
      expect(event.event_type).to eq("STATE_DELTA")
      expect(event.delta).to eq(delta)
    end
  end

  describe "#emit_state_snapshot" do
    let(:session) { create(:ai_agui_session, :running, account: account) }

    it "emits a STATE_SNAPSHOT event" do
      snapshot = { "counter" => 5 }
      service.emit_state_snapshot(session: session, snapshot: snapshot)

      event = session.agui_events.reload.last
      expect(event.event_type).to eq("STATE_SNAPSHOT")
      expect(event.delta).to eq(snapshot)
    end
  end

  describe "#emit_step" do
    let(:session) { create(:ai_agui_session, :running, account: account) }

    it "emits STEP_STARTED event" do
      service.emit_step(session: session, step_id: "step_1", status: "started")

      event = session.agui_events.reload.last
      expect(event.event_type).to eq("STEP_STARTED")
      expect(event.step_id).to eq("step_1")
    end

    it "emits STEP_FINISHED event" do
      service.emit_step(session: session, step_id: "step_1", status: "finished")

      event = session.agui_events.reload.last
      expect(event.event_type).to eq("STEP_FINISHED")
    end
  end

  describe "#get_events" do
    let(:session) { create(:ai_agui_session, account: account) }

    before do
      5.times do |i|
        create(:ai_agui_event, session: session, account: account,
               event_type: "TEXT_MESSAGE_CONTENT", sequence_number: i + 1)
      end
    end

    it "returns events ordered by sequence" do
      events = service.get_events(session_id: session.id)
      expect(events.map(&:sequence_number)).to eq([1, 2, 3, 4, 5])
    end

    it "filters events after a sequence number" do
      events = service.get_events(session_id: session.id, after_sequence: 3)
      expect(events.map(&:sequence_number)).to eq([4, 5])
    end

    it "limits results" do
      events = service.get_events(session_id: session.id, limit: 2)
      expect(events.count).to eq(2)
    end
  end
end
