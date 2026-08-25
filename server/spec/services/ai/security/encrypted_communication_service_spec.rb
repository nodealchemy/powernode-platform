# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Security::EncryptedCommunicationService, type: :service do
  let(:account) { create(:account) }
  let(:provider) { create(:ai_provider, account: account) }
  let(:agent_a) { create(:ai_agent, account: account, provider: provider) }
  let(:agent_b) { create(:ai_agent, account: account, provider: provider) }

  subject(:service) { described_class.new(account: account) }

  # Every Redis handle in this file MUST be Powernode::Redis.client — never a
  # hand-built `Redis.new(url: ENV.fetch("REDIS_URL", ...))`.
  #
  # The service under test writes through Powernode::Redis.client, which under
  # RAILS_ENV=test is isolated onto TEST_DATABASE (db 15) — the isolation added
  # after the suite sharing db 0 accumulated 425,484 orphaned keys / 10.6 GB and
  # took a node down (2026-08-17). A raw handle defaults to db 0, so the spec
  # wrote nothing there and read back nil.
  #
  # Note what that did to the deletion assertion at the bottom of this file: it
  # asserted a key was absent from a database the service had never written to,
  # so it PASSED while proving nothing. A wrong-database read fails loudly in
  # the positive assertions and silently in the negative ones.
  after do
    redis = Powernode::Redis.client
    redis.keys("powernode:encrypted_session:*").each { |k| redis.del(k) }
  rescue StandardError
    nil
  end

  describe "#establish_session!" do
    it "returns a session ID" do
      session_id = service.establish_session!(agent_a: agent_a, agent_b: agent_b)

      expect(session_id).to be_present
      expect(session_id).to match(/\A[0-9a-f\-]{36}\z/)
    end

    it "stores session data in Redis" do
      session_id = service.establish_session!(agent_a: agent_a, agent_b: agent_b)

      redis = Powernode::Redis.client
      data = redis.get("powernode:encrypted_session:#{session_id}")
      expect(data).to be_present

      parsed = JSON.parse(data)
      expect(parsed["agent_a_id"]).to eq(agent_a.id)
      expect(parsed["agent_b_id"]).to eq(agent_b.id)
    end

    it "creates an audit trail entry" do
      expect {
        service.establish_session!(agent_a: agent_a, agent_b: agent_b)
      }.to change(Ai::SecurityAuditTrail, :count).by_at_least(1)
    end

    it "accepts an optional task_id" do
      task_id = SecureRandom.uuid
      session_id = service.establish_session!(agent_a: agent_a, agent_b: agent_b, task_id: task_id)

      redis = Powernode::Redis.client
      data = JSON.parse(redis.get("powernode:encrypted_session:#{session_id}"))
      expect(data["task_id"]).to eq(task_id)
    end
  end

  describe "#encrypt and #decrypt" do
    let(:session_id) { service.establish_session!(agent_a: agent_a, agent_b: agent_b) }
    let(:plaintext) { "Hello, this is a secret message between agents!" }

    it "encrypts and decrypts a message successfully" do
      message = service.encrypt(
        session_id: session_id,
        from_agent_id: agent_a.id,
        to_agent_id: agent_b.id,
        plaintext: plaintext
      )

      expect(message).to be_persisted
      expect(message.ciphertext).to be_present
      expect(message.nonce).to be_present
      expect(message.auth_tag).to be_present
      expect(message.session_id).to eq(session_id)

      decrypted = service.decrypt(message_id: message.id)
      expect(decrypted).to eq(plaintext)
    end

    it "creates an EncryptedMessage record" do
      expect {
        service.encrypt(
          session_id: session_id,
          from_agent_id: agent_a.id,
          to_agent_id: agent_b.id,
          plaintext: plaintext
        )
      }.to change(Ai::EncryptedMessage, :count).by(1)
    end

    it "marks message as read after decryption" do
      message = service.encrypt(
        session_id: session_id,
        from_agent_id: agent_a.id,
        to_agent_id: agent_b.id,
        plaintext: plaintext
      )

      service.decrypt(message_id: message.id)
      message.reload
      expect(message.status).to eq("read")
    end

    it "raises SessionError for expired/missing session" do
      expect {
        service.encrypt(
          session_id: "nonexistent",
          from_agent_id: agent_a.id,
          to_agent_id: agent_b.id,
          plaintext: plaintext
        )
      }.to raise_error(Ai::Security::EncryptedCommunicationService::SessionError)
    end

    it "increments sequence numbers for successive messages" do
      msg1 = service.encrypt(
        session_id: session_id,
        from_agent_id: agent_a.id,
        to_agent_id: agent_b.id,
        plaintext: "Message 1"
      )
      msg2 = service.encrypt(
        session_id: session_id,
        from_agent_id: agent_a.id,
        to_agent_id: agent_b.id,
        plaintext: "Message 2"
      )

      expect(msg2.sequence_number).to be > msg1.sequence_number
    end
  end

  describe "atomic sequence numbers" do
    let(:session_id) { service.establish_session!(agent_a: agent_a, agent_b: agent_b) }

    it "uses atomic Redis INCR for sequence numbers" do
      redis = Powernode::Redis.client
      seq_key = "powernode:encrypted_session:#{session_id}:seq"

      # Initial value should be "0"
      expect(redis.get(seq_key)).to eq("0")

      msg1 = service.encrypt(
        session_id: session_id,
        from_agent_id: agent_a.id,
        to_agent_id: agent_b.id,
        plaintext: "Message 1"
      )

      # After first encrypt, seq should be 1
      expect(redis.get(seq_key).to_i).to eq(1)
      expect(msg1.sequence_number).to eq(1)
    end

    it "produces monotonically increasing sequence numbers" do
      messages = 3.times.map do |i|
        service.encrypt(
          session_id: session_id,
          from_agent_id: agent_a.id,
          to_agent_id: agent_b.id,
          plaintext: "Message #{i}"
        )
      end

      sequences = messages.map(&:sequence_number)
      expect(sequences).to eq([1, 2, 3])
    end
  end

  describe "#close_session!" do
    let(:session_id) { service.establish_session!(agent_a: agent_a, agent_b: agent_b) }

    it "removes session from Redis" do
      service.close_session!(session_id: session_id)

      redis = Powernode::Redis.client
      expect(redis.get("powernode:encrypted_session:#{session_id}")).to be_nil
    end

    it "marks delivered messages as expired" do
      message = service.encrypt(
        session_id: session_id,
        from_agent_id: agent_a.id,
        to_agent_id: agent_b.id,
        plaintext: "test"
      )

      service.close_session!(session_id: session_id)

      message.reload
      expect(message.status).to eq("expired")
    end

    it "returns a success result" do
      result = service.close_session!(session_id: session_id)
      expect(result[:closed]).to be true
      expect(result[:session_id]).to eq(session_id)
    end
  end
end
