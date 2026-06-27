# frozen_string_literal: true

require "rails_helper"

# Worker callbacks for the chat-attachment scan + transcription pipeline.
# The standalone worker runs ClamAV / off-request-path I/O and calls these
# endpoints; the server owns all model/DB state (Pattern B). Like every worker
# callback they MUST NOT 500 on a processing error (Sidekiq retry storms).
RSpec.describe "Api::V1::Internal::Chat::Attachments", type: :request do
  include_context "internal api auth"

  # The attachment after_create callbacks enqueue worker jobs — stub so spec
  # setup doesn't make real worker HTTP calls.
  before do
    allow(WorkerJobService).to receive(:enqueue_chat_attachment_scan)
    allow(WorkerJobService).to receive(:enqueue_chat_transcription)
  end

  let(:attachment) { create(:chat_message_attachment) }

  describe "GET scan_payload" do
    let(:path) { "/api/v1/internal/chat/attachments/#{attachment.id}/scan_payload" }

    it "requires worker mTLS authentication" do
      get path
      expect(response).to have_http_status(:unauthorized)
    end

    it "reports scannable + file_object_id when a file object is linked" do
      scannable = create(:chat_message_attachment, :with_file_object)
      get "/api/v1/internal/chat/attachments/#{scannable.id}/scan_payload", headers: service_headers

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body.dig("data", "scannable")).to be true
      expect(body.dig("data", "file_object_id")).to eq(scannable.file_object_id)
    end

    it "reports not-scannable (fail-closed) when no file object is linked" do
      get path, headers: service_headers
      body = JSON.parse(response.body)
      expect(response).to have_http_status(:ok)
      expect(body.dig("data", "scannable")).to be false
      expect(body.dig("data", "reason")).to eq("no_file_object")
    end

    it "reports found:false for an unknown attachment (idempotent no-op)" do
      get "/api/v1/internal/chat/attachments/#{SecureRandom.uuid}/scan_payload", headers: service_headers
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body).dig("data", "found")).to be false
    end
  end

  describe "POST scan_result" do
    let(:path) { "/api/v1/internal/chat/attachments/#{attachment.id}/scan_result" }

    it "marks a clean attachment scanned + safe" do
      post path, params: { status: "completed", malware_detected: false }, headers: service_headers, as: :json
      expect(response).to have_http_status(:ok)
      attachment.reload
      expect(attachment.scanned_for_malware?).to be true
      expect(attachment.safe_to_use?).to be true
    end

    it "quarantines an infected attachment" do
      post path, params: { status: "completed", malware_detected: true, threat: "Eicar" },
                 headers: service_headers, as: :json
      expect(response).to have_http_status(:ok)
      attachment.reload
      expect(attachment.malware_detected?).to be true
      expect(attachment.safe_to_use?).to be false
    end

    it "leaves the attachment pending on a skipped verdict (fail-closed)" do
      post path, params: { status: "skipped", reason: "clamav_unavailable" },
                 headers: service_headers, as: :json
      expect(response).to have_http_status(:ok)
      expect(attachment.reload.scanned_for_malware?).to be false
    end

    it "never 500s on a malformed verdict" do
      post path, params: { status: nil, malware_detected: "garbage" }, headers: service_headers, as: :json
      expect(response).to have_http_status(:ok)
      expect(response).not_to have_http_status(:internal_server_error)
    end

    it "returns 2xx for an unknown attachment (no retry storm)" do
      post "/api/v1/internal/chat/attachments/#{SecureRandom.uuid}/scan_result",
           params: { status: "completed", malware_detected: false }, headers: service_headers, as: :json
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body).dig("data", "reason")).to eq("attachment_not_found")
    end
  end

  describe "POST transcribe" do
    let(:audio) { create(:chat_message_attachment, :audio) }
    let(:path) { "/api/v1/internal/chat/attachments/#{audio.id}/transcribe" }

    it "no-ops gracefully (2xx, never 500) when no transcription provider is configured" do
      post path, headers: service_headers, as: :json
      expect(response).to have_http_status(:ok)
      expect(response).not_to have_http_status(:internal_server_error)
      body = JSON.parse(response.body)
      expect(body.dig("data", "transcribed")).to be false
      expect(body.dig("data", "reason")).to be_present
      expect(audio.reload.transcription).to be_nil
    end

    it "returns 2xx for an unknown attachment" do
      post "/api/v1/internal/chat/attachments/#{SecureRandom.uuid}/transcribe", headers: service_headers, as: :json
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body).dig("data", "reason")).to eq("attachment_not_found")
    end
  end
end
