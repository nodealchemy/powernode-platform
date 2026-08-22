# frozen_string_literal: true

require "rails_helper"

RSpec.describe WorkerApiClient do
  describe "#job_class_for_type" do
    subject(:client) { described_class.new }

    {
      "thumbnail" => "FileProcessing::ThumbnailGenerationJob",
      "metadata_extract" => "FileProcessing::MetadataExtractionJob",
      "video_processing" => "FileProcessing::VideoProcessingJob",
      "audio_processing" => "FileProcessing::AudioProcessingJob",
      "video_stitching" => "VideoStitchingJob",
      "document_generation" => "DocumentGenerationJob"
    }.each do |job_type, expected_class|
      it "maps #{job_type} to #{expected_class}" do
        expect(client.send(:job_class_for_type, job_type)).to eq(expected_class)
      end
    end

    it "raises for an unknown job_type" do
      expect { client.send(:job_class_for_type, "nope") }.to raise_error(described_class::ApiError)
    end
  end

  describe "transport error mapping" do
    subject(:client) { described_class.new(base_url: base_url) }

    let(:base_url) { "http://worker.example.test:4567" }

    before do
      allow(WorkerJobService).to receive(:system_worker_jwt).and_return("test-jwt")
    end

    it "parses a successful response" do
      stub_request(:post, "#{base_url}/api/v1/jobs").to_return(status: 200, body: { "jid" => "abc" }.to_json)

      expect(client.queue_job("SomeJob", [1])).to eq({ "jid" => "abc" })
    end

    it "returns {} when a 2xx body is not valid JSON" do
      stub_request(:get, "#{base_url}/health").to_return(status: 200, body: "not json")

      expect(client.send(:get, "/health")).to eq({})
    end

    it "maps 401 to AuthenticationError" do
      stub_request(:get, "#{base_url}/health").to_return(status: 401, body: "")

      expect { client.send(:get, "/health") }.to raise_error(described_class::AuthenticationError)
    end

    it "maps other non-2xx to ApiError with status and body" do
      stub_request(:get, "#{base_url}/health").to_return(status: 500, body: "boom")

      expect { client.send(:get, "/health") }
        .to raise_error(described_class::ApiError, /500.*boom/)
    end

    it "maps connection failures to NetworkError" do
      stub_request(:get, "#{base_url}/health").to_raise(Errno::ECONNREFUSED)

      expect { client.send(:get, "/health") }.to raise_error(described_class::NetworkError)
    end
  end
end
