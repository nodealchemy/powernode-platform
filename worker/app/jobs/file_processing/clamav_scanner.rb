# frozen_string_literal: true

module FileProcessing
  # Shared ClamAV scanning helpers. Extracted from VirusScanJob so the chat
  # attachment scan pipeline (Chat::AttachmentScanJob) reuses the exact same
  # clamdscan/clamscan shell-out instead of duplicating it. Behavior is
  # identical to the original inline implementation.
  module ClamavScanner
    # True when either clamdscan (daemon mode, faster) or clamscan (standalone)
    # is available on PATH.
    def clamav_available?
      system("which clamdscan > /dev/null 2>&1") || system("which clamscan > /dev/null 2>&1")
    end

    # Scans a file on disk. Returns one of:
    #   { status: :clean,    output: }
    #   { status: :infected, output:, threat: }
    #   { status: :error,    output: }
    def scan_file(file_path)
      # Prefer clamdscan (daemon mode, faster) over clamscan (standalone, slower)
      scanner = system("which clamdscan > /dev/null 2>&1") ? "clamdscan" : "clamscan"

      output = `#{scanner} --no-summary "#{file_path}" 2>&1`
      exit_code = $?.exitstatus

      case exit_code
      when 0
        { status: :clean, output: output.strip }
      when 1
        # Extract threat name from output (format: "/path/file: ThreatName FOUND")
        threat = output.match(/:\s*(.+)\s*FOUND/)&.captures&.first || "Unknown threat"
        { status: :infected, output: output.strip, threat: threat.strip }
      else
        { status: :error, output: output.strip }
      end
    end
  end
end
