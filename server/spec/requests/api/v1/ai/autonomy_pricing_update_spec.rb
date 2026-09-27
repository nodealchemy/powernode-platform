# frozen_string_literal: true

require "rails_helper"

# PATCH /api/v1/ai/autonomy/pricing/:model_id — a manual price override. The
# cache-write rate is optional: a request that omits it (every client written
# before the column existed) keeps the stored rate instead of clearing it.
RSpec.describe "Api::V1::Ai::Autonomy pricing update", type: :request do
  let(:account) { create(:account) }
  let(:user)    { create(:user, account: account, permissions: %w[ai.agents.read ai.autonomy.manage]) }
  let(:headers) { auth_headers_for(user) }
  let!(:pricing) do
    Ai::ModelPricing.create!(model_id: "pricing-spec-model", provider_type: "anthropic", source: "litellm",
                             input_per_1k: 3.0, output_per_1k: 15.0, cached_input_per_1k: 0.3,
                             cache_write_per_1k: 3.75)
  end
  let(:path) { "/api/v1/ai/autonomy/pricing/#{pricing.model_id}" }

  it "sets the cache-write rate and returns it" do
    patch path, params: { input_per_1k: 3.0, output_per_1k: 15.0, cached_input_per_1k: 0.3, cache_write_per_1k: 4.5 },
                headers: headers, as: :json

    expect(response).to have_http_status(:ok)
    expect(pricing.reload.cache_write_per_1k.to_f).to eq(4.5)
    expect(json_response.dig("data", "cache_write_per_1k")).to eq(4.5)
  end

  it "keeps the stored cache-write rate when the request omits it" do
    patch path, params: { input_per_1k: 2.0, output_per_1k: 10.0, cached_input_per_1k: 0.2 },
                headers: headers, as: :json

    expect(response).to have_http_status(:ok)
    expect(pricing.reload.input_per_1k.to_f).to eq(2.0)
    expect(pricing.cache_write_per_1k.to_f).to eq(3.75)
  end
end
