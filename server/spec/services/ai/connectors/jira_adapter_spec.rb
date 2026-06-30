# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Connectors::JiraAdapter do
  subject(:adapter) { described_class.new }

  let(:base_url) { "https://acme.atlassian.net" }
  let(:email) { "bot@acme.test" }
  let(:token) { "jira_SECRETTOKEN" }
  let(:project_key) { "OPS" }

  before do
    allow(Ai::Connectors::TrackerConfig).to receive(:jira_base_url).and_return(base_url)
    allow(Ai::Connectors::TrackerConfig).to receive(:jira_email).and_return(email)
    allow(Ai::Connectors::TrackerConfig).to receive(:jira_api_token).and_return(token)
    allow(Ai::Connectors::TrackerConfig).to receive(:jira_project_key).and_return(project_key)
    allow(Ai::Connectors::TrackerConfig).to receive(:jira_issue_type).and_return("Task")
  end

  it "creates an issue via POST /rest/api/3/issue with Basic auth and an ADF description" do
    stub = stub_request(:post, "#{base_url}/rest/api/3/issue")
      .with(headers: { "Content-Type" => "application/json" }) do |req|
        next false unless req.headers["Authorization"].to_s.start_with?("Basic ")

        fields = JSON.parse(req.body)["fields"]
        fields["project"]["key"] == project_key &&
          fields["summary"] == "Disk full" &&
          fields["issuetype"]["name"] == "Task" &&
          fields["description"]["type"] == "doc" &&
          fields.dig("description", "content", 0, "content", 0, "text") == "details"
      end
      .to_return(
        status: 201,
        headers: { "Content-Type" => "application/json" },
        body: { id: "10001", key: "OPS-42", self: "#{base_url}/rest/api/3/issue/10001" }.to_json
      )

    result = adapter.create_issue(title: "Disk full", body: "details", severity: "high")

    expect(result[:ok]).to be(true)
    expect(result[:external_id]).to eq("OPS-42")
    expect(result[:url]).to eq("#{base_url}/browse/OPS-42")
    expect(stub).to have_been_requested
  end

  it "returns ok:false on a non-2xx response without raising or leaking the token" do
    stub_request(:post, "#{base_url}/rest/api/3/issue").to_return(status: 400, body: "bad request")

    result = adapter.create_issue(title: "x", body: "y")

    expect(result[:ok]).to be(false)
    expect(result[:error].to_s).not_to include(token)
  end

  it "returns ok:false (no raise) when required config is missing, without leaking the token" do
    allow(Ai::Connectors::TrackerConfig).to receive(:jira_project_key).and_return(nil)

    result = nil
    expect { result = adapter.create_issue(title: "x", body: "y") }.not_to raise_error
    expect(result[:ok]).to be(false)
    expect(result[:error].to_s).not_to include(token)
  end

  it "returns ok:false on a transport error without leaking the token" do
    stub_request(:post, "#{base_url}/rest/api/3/issue").to_raise(Faraday::TimeoutError.new("timeout"))

    result = adapter.create_issue(title: "x", body: "y")

    expect(result[:ok]).to be(false)
    expect(result[:error].to_s).not_to include(token)
  end
end
