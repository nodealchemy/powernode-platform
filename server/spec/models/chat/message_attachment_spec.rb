# frozen_string_literal: true

require "rails_helper"

# D3 — chat-attachment malware-scan + transcription pipeline. Before this work
# the after_create callbacks called undefined WorkerJobService methods (rescued
# → silent no-op) so attachments were NEVER scanned, and the file_object
# association pointed at a non-existent class.
RSpec.describe Chat::MessageAttachment, type: :model do
  # Keep the after_create enqueue callbacks from making real worker HTTP calls.
  before do
    allow(WorkerJobService).to receive(:enqueue_chat_attachment_scan)
    allow(WorkerJobService).to receive(:enqueue_chat_transcription)
  end

  describe "file_object association" do
    it "resolves to the real FileManagement::Object model (was a phantom class_name)" do
      expect(described_class.reflect_on_association(:file_object).klass).to eq(FileManagement::Object)
    end
  end

  describe "create-time enqueue wiring" do
    it "enqueues a malware scan for a freshly created (unscanned) attachment" do
      expect(WorkerJobService).to receive(:enqueue_chat_attachment_scan).with(kind_of(String))
      create(:chat_message_attachment)
    end

    it "does NOT enqueue a scan for an already-scanned attachment" do
      expect(WorkerJobService).not_to receive(:enqueue_chat_attachment_scan)
      create(:chat_message_attachment, :scanned)
    end

    it "enqueues transcription for a new audio attachment with no transcription" do
      expect(WorkerJobService).to receive(:enqueue_chat_transcription).with(kind_of(String))
      create(:chat_message_attachment, :audio)
    end

    it "does NOT enqueue transcription for a non-audio attachment" do
      expect(WorkerJobService).not_to receive(:enqueue_chat_transcription)
      create(:chat_message_attachment, :image)
    end
  end

  describe "#apply_scan_result" do
    let(:attachment) { create(:chat_message_attachment) }

    it "marks a clean attachment scanned and safe_to_use?" do
      attachment.apply_scan_result(status: "completed", malware_detected: false)
      attachment.reload
      expect(attachment.scanned_for_malware?).to be true
      expect(attachment.malware_detected?).to be false
      expect(attachment.safe_to_use?).to be true
    end

    it "marks an infected attachment scanned + quarantined and records the threat" do
      attachment.apply_scan_result(status: "completed", malware_detected: true, threat: "Eicar-Test-Signature")
      attachment.reload
      expect(attachment.scanned_for_malware?).to be true
      expect(attachment.malware_detected?).to be true
      expect(attachment.safe_to_use?).to be false
      expect(attachment.metadata["threat"]).to eq("Eicar-Test-Signature")
    end

    it "leaves the attachment PENDING (fail-closed) on a skipped/error verdict" do
      attachment.apply_scan_result(status: "skipped", malware_detected: false)
      attachment.reload
      expect(attachment.scanned_for_malware?).to be false
      expect(attachment.safe_to_use?).to be false
    end
  end
end
