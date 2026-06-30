# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Internal::Ai::RalphLoops gate_canary (G11)", type: :request do
  include_context "internal api auth"

  let(:path) { "/api/v1/internal/ai/ralph_loops/gate_canary" }

  it "runs the gate-integrity canary and reports healthy against the real gate" do
    post path, headers: service_headers, as: :json

    expect(response).to have_http_status(:ok)
    data = JSON.parse(response.body)["data"]
    expect(data["healthy"]).to be true
    expect(data["checks"]).to be_present
    expect(data["checks"]).to all(include("ok" => true))
  end

  it "reports unhealthy and lists the offending checks when the gate is broken" do
    broken_gate = instance_double(Ai::Ralph::TestVerificationService)
    allow(broken_gate).to receive(:evaluate).and_return(success: true) # always-pass regression
    allow(Ai::Ralph::TestVerificationService).to receive(:new).and_return(broken_gate)

    post path, headers: service_headers, as: :json

    expect(response).to have_http_status(:ok)
    data = JSON.parse(response.body)["data"]
    expect(data["healthy"]).to be false
    failing = data["checks"].reject { |c| c["ok"] }.map { |c| c["name"] }
    expect(failing).to include("blank_framework_fail_closed")
  end
end
