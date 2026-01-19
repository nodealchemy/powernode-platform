# frozen_string_literal: true

# ClamAV antivirus integration service
# Placeholder for file scanning functionality
class ClamavService
  class << self
    def scan_file(file_path)
      # TODO: Implement ClamAV integration
      { clean: true, message: "File scan not implemented" }
    end

    def available?
      false
    end
  end
end
