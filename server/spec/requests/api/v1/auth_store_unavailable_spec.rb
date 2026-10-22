# frozen_string_literal: true

require "rails_helper"

# When the JWT key store cannot be read and this process has nothing cached,
# a token cannot be checked either way. That is the server's failure, not the
# client's: answer 503 so clients retry with the token they hold, instead of
# 401, which makes them discard it and log the user out.
RSpec.describe "Authentication when the JWT key store is unavailable", type: :request do
  let(:user) { create(:user) }
  let(:headers) { auth_headers_for(user) }

  it "answers 503, not 401" do
    headers # mint the token before the store goes away
    allow(Security::JwtService).to receive(:decode)
      .and_raise(Security::JwtKeyStore::StoreUnavailable, "JWT key store unavailable")

    get "/api/v1/auth/me", headers: headers, as: :json

    expect(response).to have_http_status(:service_unavailable)
  end

  it "still answers 401 for a token that is simply invalid" do
    get "/api/v1/auth/me", headers: { "Authorization" => "Bearer not-a-token" }, as: :json

    expect(response).to have_http_status(:unauthorized)
  end
end
