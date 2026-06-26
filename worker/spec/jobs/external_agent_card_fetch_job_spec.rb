# frozen_string_literal: true

require "rails_helper"

RSpec.describe ExternalAgentCardFetchJob, type: :job do
  subject { described_class }

  it_behaves_like "a base job", described_class
  it_behaves_like "a job with API communication"

  let(:job_instance)      { described_class.new }
  let(:api_client_double) { double("BackendApiClient") }

  let(:external_agent_id) { "agent-uuid-1" }
  let(:agent_card_url)    { "https://example.com/.well-known/agent-card.json" }
  let(:callback_path)     { "/api/v1/internal/external_agents/#{external_agent_id}/card_result" }

  before do
    mock_powernode_worker_config
    Sidekiq::Testing.fake!
    allow(job_instance).to receive(:api_client).and_return(api_client_double)
    allow(api_client_double).to receive(:post).and_return("success" => true)
    allow_any_instance_of(BaseJob).to receive(:check_runaway_loop).and_return(nil)
  end

  after { Sidekiq::Worker.clear_all }

  describe "job configuration" do
    it "uses the default queue" do
      expect(described_class.get_sidekiq_options["queue"]).to eq("default")
    end
  end

  describe "#execute" do
    context "when the external GET succeeds" do
      let(:card_body) { { "name" => "External Agent", "url" => "https://example.com/a2a" }.to_json }

      before do
        stub_request(:get, agent_card_url)
          .to_return(status: 200, body: card_body, headers: { "Content-Type" => "application/json" })
      end

      it "POSTs the raw { http_status, body } outcome to the server (no A2A parsing in the worker)" do
        job_instance.execute(external_agent_id, agent_card_url)

        expect(api_client_double).to have_received(:post).with(
          callback_path,
          hash_including("http_status" => 200, "body" => card_body)
        )
      end

      it "does not include an error key on success" do
        job_instance.execute(external_agent_id, agent_card_url)

        expect(api_client_double).to have_received(:post) do |_path, payload|
          expect(payload).not_to have_key("error")
        end
      end
    end

    context "when the external GET returns a non-2xx status" do
      before do
        stub_request(:get, agent_card_url).to_return(status: 503, body: "unavailable")
      end

      # The worker reports the raw status/body and lets the server decide validity.
      it "still POSTs { http_status, body } and lets the server judge" do
        job_instance.execute(external_agent_id, agent_card_url)

        expect(api_client_double).to have_received(:post).with(
          callback_path,
          hash_including("http_status" => 503, "body" => "unavailable")
        )
      end
    end

    context "when the external GET times out" do
      before do
        stub_request(:get, agent_card_url).to_timeout
      end

      it "POSTs an { error } outcome instead of raising" do
        expect { job_instance.execute(external_agent_id, agent_card_url) }.not_to raise_error

        expect(api_client_double).to have_received(:post).with(
          callback_path,
          hash_including("error")
        )
      end
    end

    context "when the agent_card_url is malformed" do
      let(:agent_card_url) { "http://" }

      it "POSTs an { error } outcome instead of raising" do
        expect { job_instance.execute(external_agent_id, agent_card_url) }.not_to raise_error

        expect(api_client_double).to have_received(:post).with(
          callback_path,
          hash_including("error")
        )
      end
    end
  end
end
