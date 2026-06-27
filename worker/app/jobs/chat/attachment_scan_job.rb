# frozen_string_literal: true

# Worker boot.rb requires job files alphabetically, so this file loads before
# file_processing/clamav_scanner.rb — require the shared scanner explicitly
# (idempotent; require dedupes by realpath).
require_relative "../file_processing/clamav_scanner"

module Chat
  # Malware-scans a single Chat::MessageAttachment.
  #
  # Pattern B (matches ExternalAgentCardFetchJob): the worker does ONLY the
  # ClamAV I/O; all model/DB state stays on the server. Flow:
  #   1. GET  /internal/chat/attachments/:id/scan_payload -> { scannable, file_object_id, ... }
  #   2. download the bytes via the existing /worker/files/:id/download endpoint
  #   3. clamdscan/clamscan the temp file (shared FileProcessing::ClamavScanner)
  #   4. POST /internal/chat/attachments/:id/scan_result  -> server marks scanned / quarantines
  #
  # When the file can't be resolved or ClamAV isn't installed, the attachment is
  # left PENDING (scanned_for_malware stays false) — fail-closed: safe_to_use?
  # remains false until a real scan completes.
  class AttachmentScanJob < BaseJob
    include ::FileProcessing::ClamavScanner

    sidekiq_options queue: "file_processing", retry: 2

    def execute(attachment_id)
      validate_required_params({ "attachment_id" => attachment_id }, "attachment_id")

      idempotency_key = "chat_attachment_scan:#{attachment_id}"
      if already_processed?(idempotency_key)
        log_info("Chat attachment already scanned", attachment_id: attachment_id)
        return
      end

      payload = api_client.get("/api/v1/internal/chat/attachments/#{attachment_id}/scan_payload")
      data = payload["data"] || payload

      unless data && data["found"]
        log_warn("Chat attachment not found for scan", attachment_id: attachment_id)
        return
      end

      unless data["scannable"]
        log_info("Chat attachment not scannable, leaving pending",
                 attachment_id: attachment_id, reason: data["reason"])
        report_result(attachment_id, status: "skipped", reason: data["reason"])
        mark_processed(idempotency_key)
        return
      end

      unless clamav_available?
        # Do NOT mark idempotent-processed — a later run on a scanner-equipped
        # host should still scan this attachment.
        log_warn("ClamAV not installed, leaving attachment pending", attachment_id: attachment_id)
        report_result(attachment_id, status: "skipped", reason: "clamav_unavailable")
        return
      end

      temp_file = download_to_temp(data["file_object_id"])
      unless temp_file
        log_error("Failed to download chat attachment for scan", attachment_id: attachment_id)
        report_result(attachment_id, status: "error", reason: "download_failed")
        return
      end

      begin
        result = scan_file(temp_file.path)

        case result[:status]
        when :clean
          log_info("Chat attachment clean", attachment_id: attachment_id)
          report_result(attachment_id, status: "completed", malware_detected: false)
        when :infected
          log_warn("INFECTED chat attachment detected",
                   attachment_id: attachment_id, threat: result[:threat])
          report_result(attachment_id, status: "completed",
                        malware_detected: true, threat: result[:threat])
        when :error
          log_error("Chat attachment scan error",
                    attachment_id: attachment_id, output: result[:output])
          report_result(attachment_id, status: "error", reason: result[:output])
        end

        # Errors are transient (scanner hiccup) — leave un-idempotent so a retry
        # can re-scan; clean/infected verdicts are final.
        mark_processed(idempotency_key) unless result[:status] == :error
      ensure
        temp_file.close
        temp_file.unlink
      end
    end

    private

    def download_to_temp(file_object_id)
      return nil if file_object_id.to_s.empty?

      require "tempfile"
      content = api_client.download_file_content(file_object_id)
      return nil if content.nil?

      temp_file = Tempfile.new([ "chat_attachment_scan_", ".tmp" ])
      temp_file.binmode
      temp_file.write(content)
      temp_file.flush
      temp_file
    rescue StandardError => e
      log_error("Chat attachment download failed", e, file_object_id: file_object_id)
      nil
    end

    def report_result(attachment_id, status:, malware_detected: false, threat: nil, reason: nil)
      api_client.post("/api/v1/internal/chat/attachments/#{attachment_id}/scan_result", {
        status: status,
        malware_detected: malware_detected,
        threat: threat,
        reason: reason,
        scanned_at: Time.current.iso8601
      }.compact)
    rescue StandardError => e
      log_error("Failed to report chat attachment scan result", e, attachment_id: attachment_id)
    end
  end
end
