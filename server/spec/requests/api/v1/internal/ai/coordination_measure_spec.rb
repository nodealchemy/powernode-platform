# frozen_string_literal: true

require "rails_helper"

# Reproduction for the recurring boot error:
#   [CoordinationMeasure] Field <id> measurement failed: undefined method
#   'ai_agent_team_id' for #<Ai::PressureField ...>
# measure_all_fields passed team_id: field.ai_agent_team_id, but PressureField
# has no such column (and PressureFieldService#measure! ignores team_id anyway),
# so EVERY field raised NoMethodError → caught → measured stayed 0.
RSpec.describe "Api::V1::Internal::Ai::Coordination measure_all_fields", type: :request do
  include_context "internal api auth"

  describe "POST /api/v1/internal/ai/coordination/measure_all_fields" do
    it "measures existing pressure fields without raising" do
      Ai::PressureField.create!(
        account: internal_account, field_type: "code_quality",
        artifact_ref: "repo:1", pressure_value: 0.1
      )
      # Stub the metric calculation so the test doesn't depend on a calculator;
      # the bug raised while building the call args, before measure! ran.
      allow_any_instance_of(::Ai::Coordination::PressureFieldService)
        .to receive(:measure!).and_return(true)

      post "/api/v1/internal/ai/coordination/measure_all_fields", headers: service_headers

      expect(response).to have_http_status(:ok)
      data = JSON.parse(response.body)
      data = data["data"] || data
      expect(data["measured"]).to eq(1)
    end
  end
end
