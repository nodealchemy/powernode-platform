# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Agui::StateSyncService do
  let(:account) { create(:account) }
  let(:session) { create(:ai_agui_session, account: account, state: { "counter" => 0, "items" => [] }) }
  let(:service) { described_class.new(session: session) }

  describe "#push_state" do
    it "applies an add operation" do
      result = service.push_state(state_delta: [
        { "op" => "add", "path" => "/name", "value" => "test" }
      ])

      expect(result[:snapshot]["name"]).to eq("test")
      expect(result[:sequence]).to be > 0
    end

    it "applies a replace operation" do
      result = service.push_state(state_delta: [
        { "op" => "replace", "path" => "/counter", "value" => 42 }
      ])

      expect(result[:snapshot]["counter"]).to eq(42)
    end

    it "applies a remove operation" do
      result = service.push_state(state_delta: [
        { "op" => "remove", "path" => "/counter" }
      ])

      expect(result[:snapshot]).not_to have_key("counter")
    end

    it "applies multiple operations in sequence" do
      result = service.push_state(state_delta: [
        { "op" => "replace", "path" => "/counter", "value" => 5 },
        { "op" => "add", "path" => "/status", "value" => "active" }
      ])

      expect(result[:snapshot]["counter"]).to eq(5)
      expect(result[:snapshot]["status"]).to eq("active")
    end

    it "persists state changes to the session" do
      service.push_state(state_delta: [
        { "op" => "add", "path" => "/new_key", "value" => "persisted" }
      ])

      session.reload
      expect(session.state["new_key"]).to eq("persisted")
    end

    it "increments the session sequence number" do
      original_seq = session.sequence_number
      service.push_state(state_delta: [
        { "op" => "add", "path" => "/x", "value" => 1 }
      ])

      session.reload
      expect(session.sequence_number).to be > original_seq
    end
  end

  describe "#receive_client_state" do
    it "accepts client state when sequence is current" do
      result = service.receive_client_state(
        client_state: { "new" => "state" },
        client_sequence: session.sequence_number
      )

      expect(result[:accepted]).to be true
      expect(result[:snapshot]["new"]).to eq("state")
    end

    it "raises ConflictError when client is behind server" do
      session.update!(sequence_number: 10)

      expect {
        service.receive_client_state(
          client_state: { "stale" => true },
          client_sequence: 5
        )
      }.to raise_error(Ai::Agui::StateSyncService::ConflictError)
    end
  end

  describe "#snapshot" do
    it "returns current state and sequence" do
      result = service.snapshot

      expect(result[:state]).to eq({ "counter" => 0, "items" => [] })
      expect(result[:sequence]).to eq(session.sequence_number)
    end
  end

  describe "#apply_patch" do
    describe "add operation" do
      it "adds a new property" do
        result = service.apply_patch({ "a" => 1 }, [
          { "op" => "add", "path" => "/b", "value" => 2 }
        ])
        expect(result).to eq({ "a" => 1, "b" => 2 })
      end

      it "adds to an array with - index" do
        result = service.apply_patch({ "arr" => [1, 2] }, [
          { "op" => "add", "path" => "/arr/-", "value" => 3 }
        ])
        expect(result["arr"]).to eq([1, 2, 3])
      end

      it "inserts at specific array index" do
        result = service.apply_patch({ "arr" => ["a", "c"] }, [
          { "op" => "add", "path" => "/arr/1", "value" => "b" }
        ])
        expect(result["arr"]).to eq(["a", "b", "c"])
      end
    end

    describe "remove operation" do
      it "removes a property" do
        result = service.apply_patch({ "a" => 1, "b" => 2 }, [
          { "op" => "remove", "path" => "/b" }
        ])
        expect(result).to eq({ "a" => 1 })
      end

      it "raises PatchError for non-existent key" do
        expect {
          service.apply_patch({ "a" => 1 }, [
            { "op" => "remove", "path" => "/missing" }
          ])
        }.to raise_error(Ai::Agui::StateSyncService::PatchError)
      end

      it "removes array element by index" do
        result = service.apply_patch({ "arr" => [1, 2, 3] }, [
          { "op" => "remove", "path" => "/arr/1" }
        ])
        expect(result["arr"]).to eq([1, 3])
      end
    end

    describe "replace operation" do
      it "replaces an existing value" do
        result = service.apply_patch({ "key" => "old" }, [
          { "op" => "replace", "path" => "/key", "value" => "new" }
        ])
        expect(result["key"]).to eq("new")
      end

      it "raises PatchError for non-existent key" do
        expect {
          service.apply_patch({}, [
            { "op" => "replace", "path" => "/missing", "value" => "x" }
          ])
        }.to raise_error(Ai::Agui::StateSyncService::PatchError)
      end
    end

    describe "move operation" do
      it "moves a value from one path to another" do
        result = service.apply_patch({ "source" => "value", "other" => 1 }, [
          { "op" => "move", "from" => "/source", "path" => "/destination" }
        ])
        expect(result["destination"]).to eq("value")
        expect(result).not_to have_key("source")
      end
    end

    describe "copy operation" do
      it "copies a value from one path to another" do
        result = service.apply_patch({ "source" => "value" }, [
          { "op" => "copy", "from" => "/source", "path" => "/destination" }
        ])
        expect(result["source"]).to eq("value")
        expect(result["destination"]).to eq("value")
      end
    end

    describe "test operation" do
      it "succeeds when values match" do
        expect {
          service.apply_patch({ "key" => "value" }, [
            { "op" => "test", "path" => "/key", "value" => "value" }
          ])
        }.not_to raise_error
      end

      it "raises TestFailedError when values do not match" do
        expect {
          service.apply_patch({ "key" => "value" }, [
            { "op" => "test", "path" => "/key", "value" => "wrong" }
          ])
        }.to raise_error(Ai::Agui::StateSyncService::TestFailedError)
      end
    end

    describe "nested paths" do
      it "handles deeply nested add" do
        result = service.apply_patch({ "a" => { "b" => {} } }, [
          { "op" => "add", "path" => "/a/b/c", "value" => "deep" }
        ])
        expect(result["a"]["b"]["c"]).to eq("deep")
      end

      it "handles deeply nested replace" do
        result = service.apply_patch({ "a" => { "b" => { "c" => "old" } } }, [
          { "op" => "replace", "path" => "/a/b/c", "value" => "new" }
        ])
        expect(result["a"]["b"]["c"]).to eq("new")
      end
    end

    describe "unsupported operations" do
      it "raises PatchError for unknown operations" do
        expect {
          service.apply_patch({}, [
            { "op" => "invalid", "path" => "/key" }
          ])
        }.to raise_error(Ai::Agui::StateSyncService::PatchError, /Unsupported operation/)
      end
    end
  end
end
