# frozen_string_literal: true

require "rails_helper"

RSpec.describe FileManagement::ProcessingJob do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:file_object) { create(:file_object, account: account, uploaded_by: user) }

  describe "job_type validation" do
    it "lists the media + stitching job types" do
      expect(described_class::JOB_TYPES).to include("video_processing", "audio_processing", "video_stitching")
    end

    %w[video_processing audio_processing video_stitching].each do |type|
      it "accepts #{type} as a job_type" do
        job = build(:file_processing_job, account: account, object: file_object, job_type: type)
        expect(job).to be_valid
      end

      it "persists #{type} (DB check constraint allows it)" do
        job = create(:file_processing_job, account: account, object: file_object, job_type: type)
        expect(job.reload.job_type).to eq(type)
      end
    end

    it "still rejects an unknown job_type" do
      job = build(:file_processing_job, account: account, object: file_object, job_type: "transmogrify")
      expect(job).not_to be_valid
      expect(job.errors[:job_type]).to be_present
    end
  end

  # Regression: FileManagement::Object#queue_processing_jobs queues
  # video_processing / audio_processing on create. Before the enum was extended,
  # creating any video/audio object raised RecordInvalid (the job_type was rejected).
  describe "media object creation (regression)" do
    before do
      # Isolate from the worker HTTP dispatch — we only assert the ProcessingJob row.
      allow_any_instance_of(WorkerApiClient).to receive(:queue_file_processing_job).and_return(true)
    end

    it "creates a video object and queues a video_processing job" do
      video = nil
      expect { video = create(:file_object, :video, account: account, uploaded_by: user) }.not_to raise_error
      expect(video.processing_jobs.pluck(:job_type)).to include("video_processing")
    end

    it "creates an audio object and queues an audio_processing job" do
      audio = nil
      expect { audio = create(:file_object, :audio, account: account, uploaded_by: user) }.not_to raise_error
      expect(audio.processing_jobs.pluck(:job_type)).to include("audio_processing")
    end
  end
end
