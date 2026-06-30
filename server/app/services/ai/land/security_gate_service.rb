# frozen_string_literal: true

module Ai
  module Land
    # Blocking security gate for the autonomous land path. Runs BEFORE a land is
    # auto-approved/merged (see Ai::Land::ApprovalBinding) so a change carrying a
    # leaked secret (or, once external scanners are registered, a SAST/CVE finding)
    # never auto-merges — the land is forced to a human-gated state instead.
    #
    # Two layers:
    #   1. CORE secret-scan — in-process, always runs, no extension needed. Reuses
    #      the G15 DataManagement::Sanitizer SECRET_PATTERNS via #secret_findings.
    #   2. EXTERNAL scanners — SAST / dep-CVE / full-diff secret scan, contributed
    #      by extensions or the worker through Ai::Land::SecurityScannerRegistry.
    #      Core never names them; it just calls each registered handler.
    #
    # Findings are aggregated; `blocked` is true when any finding's severity meets
    # or exceeds BLOCKING_SEVERITY.
    #
    # SERVER-SIDE CONTENT LIMITATION: a CampaignLand row carries no git diff — only
    # textual artifacts already on record (land metadata, branch name, and any
    # content a source exposes via #land_scan_content). The core scan therefore
    # catches secrets that leaked INTO the recorded loop text/metadata, NOT secrets
    # living only in the committed diff. Full-diff SAST/CVE/secret scanning belongs
    # to the worker (which owns the checkout) and registers here — see the campaign
    # parity follow-up. Callers with real diff content may pass it explicitly via
    # `contents:` / `changed_files:`.
    class SecurityGateService
      # Lowest -> highest. A finding at/above BLOCKING_SEVERITY blocks the land.
      SEVERITY_ORDER = %w[info low medium high critical].freeze
      BLOCKING_SEVERITY = "high"
      DEFAULT_SEVERITY = "medium"

      # Convenience entry point. Pass a land (server-side artifacts are gathered
      # from it) and/or explicit change content.
      def self.evaluate(land = nil, changed_files: nil, contents: nil)
        new(land: land, changed_files: changed_files, contents: contents).evaluate
      end

      def initialize(land: nil, changed_files: nil, contents: nil)
        @land = land
        @changed_files = Array(changed_files).map(&:to_s)
        @contents = Array(contents).map(&:to_s)
      end

      # => { blocked:, findings: [{ scanner:, severity:, detail: }], scanned_content:, scanners: }
      def evaluate
        findings = core_secret_scan + external_scans
        {
          blocked: findings.any? { |f| blocking?(f) },
          findings: findings,
          # false when only paths/metadata were available (the diff-content gap).
          scanned_content: change_content_available?,
          scanners: SecurityScannerRegistry.names
        }
      end

      private

      # Layer 1: in-process secret detection over whatever text is available.
      def core_secret_scan
        text = scannable_text
        return [] if text.blank?

        DataManagement::Sanitizer.secret_findings(text).map do |m|
          {
            scanner: "core_secret_scan",
            severity: "critical",
            # Category label only — never the raw secret value.
            detail: "potential secret detected (#{m[:category]})"
          }
        end
      end

      # Layer 2: external scanners (extension/worker provided). Fail-closed: a
      # scanner that raises yields a blocking finding so the land parks for a human
      # rather than silently passing a security check.
      def external_scans
        context = scan_context
        SecurityScannerRegistry.handlers.flat_map do |name, handler|
          Array(handler.call(context)).map { |f| normalize_finding(f, default_scanner: name) }
        rescue StandardError => e
          Rails.logger.warn("[Ai::Land::SecurityGate] scanner #{name} failed: #{e.message}")
          [ { scanner: name.to_s, severity: "high", detail: "scanner error: #{e.message}" } ]
        end
      end

      def scan_context
        {
          land: @land,
          source: @land&.source,
          account: @land&.account,
          changed_files: @changed_files,
          contents: @contents,
          text: scannable_text
        }
      end

      # All server-side-available text to scan. Explicit content wins; otherwise we
      # fall back to land metadata, the branch name, and any source-provided text.
      def scannable_text
        @scannable_text ||= begin
          parts = @contents.dup
          parts.concat(@changed_files) # paths only — limited signal, but cheap
          if @land
            parts << @land.metadata.to_json if @land.respond_to?(:metadata) && @land.metadata.present?
            parts << @land.source_branch.to_s
            source = @land.source
            parts.concat(Array(source.land_scan_content).map(&:to_s)) if source.respond_to?(:land_scan_content)
          end
          parts.reject(&:blank?).join("\n")
        end
      end

      # True only when actual change CONTENT (not just paths/metadata) was scanned.
      def change_content_available?
        return true if @contents.any?

        src = @land&.source
        src.respond_to?(:land_scan_content) && Array(src.land_scan_content).any?
      end

      def normalize_finding(finding, default_scanner:)
        finding = finding.symbolize_keys if finding.respond_to?(:symbolize_keys)
        finding = {} unless finding.is_a?(Hash)
        {
          scanner: (finding[:scanner] || default_scanner).to_s,
          severity: normalize_severity(finding[:severity]),
          detail: finding[:detail].to_s
        }
      end

      def blocking?(finding)
        severity_rank(finding[:severity]) >= severity_rank(BLOCKING_SEVERITY)
      end

      def severity_rank(severity)
        SEVERITY_ORDER.index(normalize_severity(severity)) || 0
      end

      def normalize_severity(severity)
        s = severity.to_s.downcase
        SEVERITY_ORDER.include?(s) ? s : DEFAULT_SEVERITY
      end
    end
  end
end
