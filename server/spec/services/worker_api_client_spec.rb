# frozen_string_literal: true

require "rails_helper"

RSpec.describe WorkerApiClient do
  describe "#job_class_for_type" do
    subject(:client) { described_class.new }

    {
      "thumbnail" => "ThumbnailGenerationJob",
      "metadata_extract" => "MetadataExtractionJob",
      "video_processing" => "VideoProcessingJob",
      "audio_processing" => "AudioProcessingJob",
      "video_stitching" => "VideoStitchingJob"
    }.each do |job_type, expected_class|
      it "maps #{job_type} to #{expected_class}" do
        expect(client.send(:job_class_for_type, job_type)).to eq(expected_class)
      end
    end

    it "raises for an unknown job_type" do
      expect { client.send(:job_class_for_type, "nope") }.to raise_error(described_class::ApiError)
    end
  end
end
