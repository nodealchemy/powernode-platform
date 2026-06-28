# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::VideoGenerationService do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:provider) { create(:ai_provider, :runway, account: account) }
  let!(:credential) { create(:ai_provider_credential, account: account, provider: provider, credentials: { "api_key" => "rw-test-key" }) }
  let(:service) { described_class.new(account: account, user: user, poll_interval: 0, max_polls: 5) }
  let(:base) { "https://api.dev.runwayml.com/v1" }
  let(:task_id) { "task-123" }
  let(:output_url) { "https://cdn.runway.test/out.mp4" }

  def stub_submit(id: "task-123")
    stub_request(:post, "#{base}/image_to_video")
      .to_return(status: 200, body: { id: id }.to_json, headers: { "Content-Type" => "application/json" })
  end

  def stub_poll(id: "task-123", status: "SUCCEEDED", output: ["https://cdn.runway.test/out.mp4"])
    stub_request(:get, "#{base}/tasks/#{id}")
      .to_return(status: 200, body: { status: status, output: output }.to_json, headers: { "Content-Type" => "application/json" })
  end

  def stub_download(url: "https://cdn.runway.test/out.mp4", body: "MP4BYTES")
    stub_request(:get, url).to_return(status: 200, body: body)
  end

  describe "#generate (happy path)" do
    before { stub_submit; stub_poll; stub_download }

    it "submits, polls, downloads, and returns the bytes (store: false)" do
      result = service.generate(prompt: "a cat surfing", store: false)
      expect(result[:video_data]).to eq("MP4BYTES")
      expect(result[:task_id]).to eq(task_id)
      expect(result[:model]).to eq("gen3a_turbo") # provider default
      expect(result[:output_url]).to eq(output_url)
    end

    it "sends a Bearer auth header to Runway" do
      service.generate(prompt: "x", store: false)
      expect(WebMock).to have_requested(:post, "#{base}/image_to_video")
        .with(headers: { "Authorization" => /\ABearer / })
    end

    it "stores the result as an ai_generated video/mp4 file via FileStorageService" do
      storage_service = instance_double(FileStorageService)
      fo = build_stubbed(:file_object)
      captured = nil
      allow(FileStorageService).to receive(:new).with(account).and_return(storage_service)
      allow(storage_service).to receive(:upload_file) { |_io, **opts| captured = opts; fo }

      result = service.generate(prompt: "a cat surfing")
      expect(result[:file_object]).to eq(fo)
      expect(captured[:content_type]).to eq("video/mp4")
      expect(captured[:category]).to eq("ai_generated")
      expect(captured[:metadata][:generator]).to eq("runway")
    end
  end

  describe "polling outcomes" do
    it "raises when the task fails" do
      stub_submit
      stub_request(:get, "#{base}/tasks/#{task_id}")
        .to_return(status: 200, body: { status: "FAILED", error: "bad prompt" }.to_json, headers: { "Content-Type" => "application/json" })
      expect { service.generate(prompt: "x", store: false) }
        .to raise_error(described_class::GenerationError, /failed/i)
    end

    it "raises when the task never completes within max_polls" do
      stub_submit
      stub_request(:get, "#{base}/tasks/#{task_id}")
        .to_return(status: 200, body: { status: "PENDING" }.to_json, headers: { "Content-Type" => "application/json" })
      expect { service.generate(prompt: "x", store: false) }
        .to raise_error(described_class::GenerationError, /did not complete/)
    end

    it "raises when succeeded but no output url" do
      stub_submit
      stub_poll(output: [])
      expect { service.generate(prompt: "x", store: false) }
        .to raise_error(described_class::GenerationError, /no output url/i)
    end
  end

  describe "validation + provider resolution errors" do
    it "raises when prompt is blank" do
      expect { service.generate(prompt: "  ", store: false) }.to raise_error(described_class::GenerationError, /prompt is required/)
    end

    it "raises when no active runway provider exists" do
      credential.provider.update!(is_active: false)
      expect { service.generate(prompt: "x", store: false) }
        .to raise_error(described_class::GenerationError, /No active runway provider/)
    end

    it "raises when no credential exists" do
      credential.update!(is_active: false)
      expect { service.generate(prompt: "x", store: false) }
        .to raise_error(described_class::GenerationError, /No active credential/)
    end
  end
end
