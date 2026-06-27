# frozen_string_literal: true

require 'rails_helper'

# D3 — chat-attachment malware scan (worker half). Pattern B: the worker fetches
# bytes + runs ClamAV; all model/DB state stays on the server, which it reaches
# via the scan_payload (GET) and scan_result (POST) internal endpoints.
RSpec.describe Chat::AttachmentScanJob, type: :job do
  before do
    mock_powernode_worker_config
    allow_any_instance_of(BaseJob).to receive(:check_runaway_loop).and_return(nil)
    allow_logging_methods
  end

  let(:attachment_id) { SecureRandom.uuid }
  let(:job) { described_class.new }
  let(:api_client) { instance_double(BackendApiClient) }
  let(:scan_path) { "/api/v1/internal/chat/attachments/#{attachment_id}/scan_result" }

  before do
    allow(job).to receive(:api_client).and_return(api_client)
    allow(job).to receive(:already_processed?).and_return(false)
    allow(job).to receive(:mark_processed)
  end

  def stub_payload(payload)
    allow(api_client).to receive(:get)
      .with("/api/v1/internal/chat/attachments/#{attachment_id}/scan_payload")
      .and_return(payload)
  end

  context "when scannable and clean" do
    before do
      stub_payload("found" => true, "scannable" => true, "file_object_id" => "fo-1")
      allow(job).to receive(:clamav_available?).and_return(true)
      allow(api_client).to receive(:download_file_content).with("fo-1").and_return("filebytes")
      allow(job).to receive(:scan_file).and_return(status: :clean, output: "OK")
    end

    it "posts a completed/clean verdict" do
      expect(api_client).to receive(:post)
        .with(scan_path, hash_including(status: "completed", malware_detected: false))
      job.execute(attachment_id)
    end
  end

  context "when scannable and infected" do
    before do
      stub_payload("found" => true, "scannable" => true, "file_object_id" => "fo-1")
      allow(job).to receive(:clamav_available?).and_return(true)
      allow(api_client).to receive(:download_file_content).with("fo-1").and_return("evilbytes")
      allow(job).to receive(:scan_file).and_return(status: :infected, threat: "Eicar-Test", output: "FOUND")
    end

    it "posts a completed verdict with malware_detected + threat" do
      expect(api_client).to receive(:post)
        .with(scan_path, hash_including(status: "completed", malware_detected: true, threat: "Eicar-Test"))
      job.execute(attachment_id)
    end
  end

  context "when the attachment is not scannable (no file object)" do
    before { stub_payload("found" => true, "scannable" => false, "reason" => "no_file_object") }

    it "reports skipped without downloading or scanning" do
      expect(api_client).not_to receive(:download_file_content)
      expect(api_client).to receive(:post).with(scan_path, hash_including(status: "skipped", reason: "no_file_object"))
      job.execute(attachment_id)
    end
  end

  context "when ClamAV is unavailable" do
    before do
      stub_payload("found" => true, "scannable" => true, "file_object_id" => "fo-1")
      allow(job).to receive(:clamav_available?).and_return(false)
    end

    it "reports skipped (clamav_unavailable) and does NOT mark idempotent-processed" do
      expect(job).not_to receive(:mark_processed)
      expect(api_client).to receive(:post).with(scan_path, hash_including(status: "skipped", reason: "clamav_unavailable"))
      job.execute(attachment_id)
    end
  end

  context "when the attachment is already scanned (idempotent)" do
    before { allow(job).to receive(:already_processed?).and_return(true) }

    it "short-circuits without hitting the server" do
      expect(api_client).not_to receive(:get)
      expect(api_client).not_to receive(:post)
      job.execute(attachment_id)
    end
  end
end
