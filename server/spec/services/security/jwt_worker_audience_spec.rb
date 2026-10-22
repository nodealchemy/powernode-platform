# frozen_string_literal: true

require "rails_helper"

# Worker job JWTs carry aud "worker": the worker requires it (or, for one
# release, no aud), and this server's own authentication refuses it, so a
# token sent to the worker can never be replayed against the server API.
RSpec.describe "worker JWT audience", type: :request do
  let(:token) { Security::JwtService.encode_for_worker({ type: "worker", sub: SecureRandom.uuid }, 5.minutes.from_now) }

  it "signs worker job JWTs with aud worker" do
    claims = JWT.decode(token, Rails.application.config.jwt_secret_key, true, algorithm: "HS256")[0]

    expect(claims["aud"]).to eq("worker")
  end

  it "is refused by the server's own token check" do
    expect { Security::JwtService.decode(token) }.to raise_error(StandardError, /Invalid token/)
  end

  it "is refused by authenticate_request" do
    get "/api/v1/auth/me", headers: { "Authorization" => "Bearer #{token}" }, as: :json

    expect(response).to have_http_status(:unauthorized)
  end
end
