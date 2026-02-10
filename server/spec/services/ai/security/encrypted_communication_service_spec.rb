# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Security::EncryptedCommunicationService, type: :service do
  let(:account) { create(:account) }
  let(:provider) { create(:ai_provider, account: account) }
  let(:agent_a) { create(:ai_agent, account: account, provider: provider) }
  let(:agent_b) { create(:ai_agent, account: account, provider: provider) }

  subject(:service) { described_class.new(account: account) }

  # Clean up Redis session keys after each test
  after do
    redis = Redis.new(url: ENV.fetch("REDIS_URL", "redis://localhost:6379"))
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

      redis = Redis.new(url: ENV.fetch("REDIS_URL", "redis://localhost:6379"))
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

      redis = Redis.new(url: ENV.fetch("REDIS_URL", "redis://localhost:6379"))
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

  describe "#close_session!" do
    let(:session_id) { service.establish_session!(agent_a: agent_a, agent_b: agent_b) }

    it "removes session from Redis" do
      service.close_session!(session_id: session_id)

      redis = Redis.new(url: ENV.fetch("REDIS_URL", "redis://localhost:6379"))
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
