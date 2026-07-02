# frozen_string_literal: true

require "rails_helper"

# Shared timestamped-HMAC signing behavior for outbound webhook models
# (WebhookEndpoint and Devops::AccountGitWebhookConfig).
RSpec.shared_examples "a webhook signable model" do
  describe "#generate_signature" do
    it "returns nil when no signature_secret is present" do
      record.signature_secret = nil

      expect(record.generate_signature("payload")).to be_nil
    end

    it "produces a t=<ts>,v1=<hex> timestamped HMAC header" do
      record.signature_secret = "whsig_#{SecureRandom.base64(32).tr('+/', '-_')}"

      header = record.generate_signature(%({"event":"ping"}))

      expect(header).to match(/\At=\d+,v1=[0-9a-f]{64}\z/)
    end

    it "signs '<timestamp>.<payload>' with HMAC-SHA256 of the signature_secret" do
      record.signature_secret = "whsig_#{SecureRandom.base64(32).tr('+/', '-_')}"
      payload = %({"event":"ping"})

      header = record.generate_signature(payload)
      timestamp, signature = header.match(/\At=(\d+),v1=([0-9a-f]+)\z/).captures
      expected = OpenSSL::HMAC.hexdigest("SHA256", record.signature_secret, "#{timestamp}.#{payload}")

      expect(signature).to eq(expected)
    end
  end

  describe "#regenerate_signature_secret!" do
    it "persists a fresh whsig_-prefixed secret" do
      record.save!
      old_secret = record.signature_secret

      record.regenerate_signature_secret!

      expect(record.reload.signature_secret).to start_with("whsig_")
      expect(record.signature_secret).not_to eq(old_secret)
    end
  end
end

RSpec.describe "WebhookSignable models" do
  let(:account) { create(:account) }

  describe WebhookEndpoint do
    let(:record) { build(:webhook_endpoint, account: account) }

    it_behaves_like "a webhook signable model"

    describe "#verify_signature" do
      before { record.signature_secret = "whsig_#{SecureRandom.base64(32).tr('+/', '-_')}" }

      it "round-trips a header produced by generate_signature" do
        payload = %({"event":"ping"})
        header = record.generate_signature(payload)

        expect(record.verify_signature(payload, header)).to be(true)
      end

      it "rejects a tampered payload" do
        header = record.generate_signature("original")

        expect(record.verify_signature("tampered", header)).to be(false)
      end

      it "rejects a stale timestamp (older than 5 minutes)" do
        payload = "payload"
        stale_ts = Time.current.to_i - 3600
        sig = OpenSSL::HMAC.hexdigest("SHA256", record.signature_secret, "#{stale_ts}.#{payload}")

        expect(record.verify_signature(payload, "t=#{stale_ts},v1=#{sig}")).to be(false)
      end

      it "returns false for blank/malformed headers" do
        expect(record.verify_signature("payload", nil)).to be(false)
        expect(record.verify_signature("payload", "garbage")).to be(false)
      end
    end
  end

  describe Devops::AccountGitWebhookConfig do
    let(:record) do
      Devops::AccountGitWebhookConfig.new(
        account: account,
        name: "CI notifier",
        url: "https://ci.example.com/webhook"
      )
    end

    it_behaves_like "a webhook signable model"
  end
end
