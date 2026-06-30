# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Connectors::LinearAdapter do
  subject(:adapter) { described_class.new }

  let(:endpoint) { "https://api.linear.app/graphql" }
  let(:api_key) { "lin_api_SECRETTOKEN" }
  let(:team_id) { "team-123" }

  before do
    allow(Ai::Connectors::TrackerConfig).to receive(:linear_api_key).and_return(api_key)
    allow(Ai::Connectors::TrackerConfig).to receive(:linear_team_id).and_return(team_id)
  end

  it "creates an issue via the Linear issueCreate GraphQL mutation" do
    stub = stub_request(:post, endpoint)
      .with(headers: { "Content-Type" => "application/json" }) do |req|
        next false unless req.headers["Authorization"].present?

        body = JSON.parse(req.body)
        input = body.dig("variables", "input")
        body["query"].to_s.include?("issueCreate") &&
          input["teamId"] == team_id &&
          input["title"] == "Disk full" &&
          input["description"] == "details" &&
          input["priority"] == 1
      end
      .to_return(
        status: 200,
        headers: { "Content-Type" => "application/json" },
        body: {
          data: {
            issueCreate: {
              success: true,
              issue: { id: "iss-uuid", identifier: "ENG-1", url: "https://linear.app/x/issue/ENG-1" }
            }
          }
        }.to_json
      )

    result = adapter.create_issue(title: "Disk full", body: "details", severity: "critical")

    expect(result[:ok]).to be(true)
    expect(result[:external_id]).to eq("iss-uuid")
    expect(result[:url]).to eq("https://linear.app/x/issue/ENG-1")
    expect(stub).to have_been_requested
  end

  it "returns ok:false on a non-2xx response without raising or leaking the token" do
    stub_request(:post, endpoint).to_return(status: 401, body: "unauthorized")

    result = adapter.create_issue(title: "x", body: "y")

    expect(result[:ok]).to be(false)
    expect(result[:error].to_s).not_to include(api_key)
  end

  it "returns ok:false when the GraphQL response reports errors" do
    stub_request(:post, endpoint).to_return(
      status: 200,
      body: { errors: [{ message: "Team not found" }] }.to_json
    )

    result = adapter.create_issue(title: "x", body: "y")

    expect(result[:ok]).to be(false)
  end

  it "returns ok:false (no raise) when required config is missing, without leaking the token" do
    allow(Ai::Connectors::TrackerConfig).to receive(:linear_team_id).and_return(nil)

    result = nil
    expect { result = adapter.create_issue(title: "x", body: "y") }.not_to raise_error
    expect(result[:ok]).to be(false)
    expect(result[:error].to_s).not_to include(api_key)
  end

  it "returns ok:false on a transport error without leaking the token" do
    stub_request(:post, endpoint).to_raise(Faraday::ConnectionFailed.new("refused"))

    result = adapter.create_issue(title: "x", body: "y")

    expect(result[:ok]).to be(false)
    expect(result[:error].to_s).not_to include(api_key)
  end
end
