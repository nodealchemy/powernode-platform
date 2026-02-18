# frozen_string_literal: true

require "rails_helper"

RSpec.describe Security::JwtService do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, password: TestUsers::PASSWORD) }

  describe ".encode" do
    it "includes type: access by default when no type is provided" do
      token = described_class.encode({ sub: user.id, account_id: account.id })
      payload = described_class.decode(token)

      expect(payload[:type]).to eq("access")
    end

    it "respects explicitly provided type" do
      token = described_class.encode({ sub: user.id, type: "worker" })
      payload = described_class.decode(token)

      expect(payload[:type]).to eq("worker")
    end

    it "respects string-keyed type" do
      token = described_class.encode({ "sub" => user.id, "type" => "service" })
      payload = described_class.decode(token)

      expect(payload[:type]).to eq("service")
    end

    it "includes standard JWT claims" do
      token = described_class.encode({ sub: user.id })
      payload = described_class.decode(token)

      expect(payload[:sub]).to eq(user.id)
      expect(payload[:exp]).to be_present
      expect(payload[:iat]).to be_present
      expect(payload[:jti]).to be_present
      expect(payload[:version]).to eq(Security::JwtService::CURRENT_TOKEN_VERSION)
    end

    it "uses access token expiration by default" do
      token = described_class.encode({ sub: user.id })
      payload = described_class.decode(token)

      expected_exp = (Time.current + 15.minutes).to_i
      expect(payload[:exp]).to be_within(5).of(expected_exp)
    end

    it "uses custom expiration when provided" do
      custom_exp = 1.hour.from_now
      token = described_class.encode({ sub: user.id }, custom_exp)
      payload = described_class.decode(token)

      expect(payload[:exp]).to be_within(2).of(custom_exp.to_i)
    end

    it "uses type-specific expiration for refresh tokens" do
      token = described_class.encode({ sub: user.id, type: "refresh" })
      payload = described_class.decode(token)

      expected_exp = (Time.current + 7.days).to_i
      expect(payload[:exp]).to be_within(5).of(expected_exp)
    end
  end

  describe ".decode" do
    it "returns a HashWithIndifferentAccess" do
      token = described_class.encode({ sub: user.id })
      payload = described_class.decode(token)

      expect(payload).to be_a(HashWithIndifferentAccess)
      expect(payload[:sub]).to eq(payload["sub"])
    end

    it "raises on invalid token" do
      expect {
        described_class.decode("invalid.token.here")
      }.to raise_error(StandardError, /Invalid token/)
    end

    it "raises on expired token" do
      token = described_class.encode({ sub: user.id }, 1.second.ago)

      expect {
        described_class.decode(token)
      }.to raise_error(StandardError, /Invalid token/)
    end

    it "raises on blacklisted token" do
      token = described_class.encode({ sub: user.id })
      described_class.blacklist_token(token, reason: "test")

      expect {
        described_class.decode(token)
      }.to raise_error(StandardError, /blacklisted/)
    end
  end

  describe ".generate_user_tokens" do
    it "returns access and refresh tokens" do
      result = described_class.generate_user_tokens(user)

      expect(result).to include(:access_token, :refresh_token, :expires_at, :refresh_expires_at)
      expect(result[:access_token]).to be_a(String)
      expect(result[:refresh_token]).to be_a(String)
    end

    it "access token has correct type and sub" do
      result = described_class.generate_user_tokens(user)
      payload = described_class.decode(result[:access_token])

      expect(payload[:type]).to eq("access")
      expect(payload[:sub]).to eq(user.id)
      expect(payload[:account_id]).to eq(user.account_id)
      expect(payload[:email]).to eq(user.email)
    end

    it "refresh token has correct type and sub" do
      result = described_class.generate_user_tokens(user)
      payload = described_class.decode(result[:refresh_token])

      expect(payload[:type]).to eq("refresh")
      expect(payload[:sub]).to eq(user.id)
    end
  end

  describe ".refresh_access_token" do
    it "issues new tokens from a valid refresh token" do
      tokens = described_class.generate_user_tokens(user)
      new_tokens = described_class.refresh_access_token(tokens[:refresh_token])

      expect(new_tokens[:access_token]).to be_present
      expect(new_tokens[:refresh_token]).to be_present
      expect(new_tokens[:access_token]).not_to eq(tokens[:access_token])
    end

    it "rejects access tokens" do
      tokens = described_class.generate_user_tokens(user)

      expect {
        described_class.refresh_access_token(tokens[:access_token])
      }.to raise_error(StandardError, /Invalid token type/)
    end
  end

  describe ".blacklist_token" do
    it "blacklists a valid token" do
      token = described_class.encode({ sub: user.id })
      result = described_class.blacklist_token(token, reason: "logout")

      expect(result).to be_truthy
      expect(described_class.blacklisted?(token)).to be true
    end

    it "handles already-expired tokens gracefully" do
      token = described_class.encode({ sub: user.id }, 1.second.ago)
      result = described_class.blacklist_token(token, reason: "cleanup")

      expect(result).to be_truthy
    end
  end

  describe ".generate_service_token" do
    it "creates a service token with correct type" do
      result = described_class.generate_service_token("worker-api")
      payload = described_class.decode(result[:token])

      expect(payload[:type]).to eq("service")
      expect(payload[:service]).to eq("worker-api")
      expect(payload[:sub]).to eq("worker-api")
    end
  end

  describe "authentication integration" do
    it "bare encode produces a token accepted by authentication" do
      token = described_class.encode({ sub: user.id, account_id: user.account_id })
      payload = described_class.decode(token)

      expect(payload[:type]).to eq("access")
      expect(payload[:sub]).to eq(user.id)

      # Simulates what Authentication concern does
      case payload[:type]
      when "access"
        found_user = User.find(payload[:sub])
        expect(found_user).to eq(user)
      else
        raise "Unexpected token type"
      end
    end
  end
end
