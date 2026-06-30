# frozen_string_literal: true

module Devops
  # Worker-side secret detection over a REAL git diff, used by the land
  # security-scan job (G4 worker depth) to catch credentials that live only in
  # the committed diff — the depth the server-side metadata gate cannot reach.
  #
  # The pattern list MIRRORS the server's DataManagement::Sanitizer::SECRET_PATTERNS
  # (G15). The server/worker boundary is HTTP-only and forbids sharing the Ruby
  # constant, so the two lists are kept in sync BY HAND — the same contract the
  # worker already uses for AiTestExecutionJob::FRAMEWORK_DETECTION vs the server's
  # TestVerificationService::FRAMEWORKS. Keep them aligned when either changes.
  #
  # Crypto-safe by construction: a finding carries ONLY a derived category label
  # (e.g. "private_key", "credential") — NEVER the matched secret value — so
  # findings are safe to POST back, persist, and display.
  module SecretScanner
    SCANNER_NAME = "worker_diff_secret_scan"
    # A secret in newly-introduced code blocks the land (mirrors the server gate's
    # critical secret severity).
    SEVERITY = "critical"

    # [pattern, category]. Categories mirror the server's Sanitizer#secret_category
    # labels so findings read consistently across the two services.
    SECRET_PATTERNS = [
      # PEM private-key blocks (any key type) — whole block.
      [ /-----BEGIN[A-Z ]*PRIVATE KEY-----.*?-----END[A-Z ]*PRIVATE KEY-----/m, "private_key" ],
      # JWTs (header.payload.signature).
      [ %r{\beyJ[A-Za-z0-9_-]+\.eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+}, "jwt" ],
      # Authorization: Bearer <token>.
      [ /Authorization\s*:\s*Bearer\s+[A-Za-z0-9._\-]+/i, "credential" ],
      # Named key/secret/token/password assignments.
      [ /(?:api[_-]?key|secret(?:[_-]?key)?|client[_-]?secret|access[_-]?token|auth[_-]?token|token|password|passwd|mnemonic|seed[_-]?phrase)["']?\s*[:=]\s*["']?[^\s"',]{6,}/i, "credential" ],
      # ENV-style UPPER_SNAKE keys ending in KEY/TOKEN/SECRET/PASSWORD/PASSWD.
      [ /[A-Z][A-Z0-9_]*(?:KEY|TOKEN|SECRET|PASSWORD|PASSWD)\s*=\s*\S+/, "credential" ],
      # Common vendor token formats.
      [ /\bsk-[A-Za-z0-9]{16,}\b/, "token" ],          # OpenAI-style
      [ /\bxox[baprs]-[A-Za-z0-9-]{10,}\b/, "token" ], # Slack
      [ /\bgh[pousr]_[A-Za-z0-9]{20,}\b/, "token" ],   # GitHub
      [ /\bAKIA[0-9A-Z]{16}\b/, "aws_key" ]            # AWS access key id
    ].freeze

    module_function

    # Scan only the lines a diff INTRODUCES (added `+` lines). Returns one finding
    # per match: { scanner:, severity:, detail: }. Removed/context lines are
    # ignored — a change that DELETES a secret should not block the land.
    def findings(diff_text)
      return [] unless diff_text.is_a?(String) && !diff_text.empty?

      added = added_lines(diff_text)
      return [] if added.empty?

      results = []
      SECRET_PATTERNS.each do |pattern, category|
        added.scan(pattern) { results << finding(category) }
      end
      results
    end

    # The content of added diff lines (`+`), with the leading marker stripped and
    # diff file headers (`+++`) excluded. Joined so multi-line matches (PEM blocks)
    # still detect.
    def added_lines(diff_text)
      diff_text.each_line
               .select { |line| line.start_with?("+") && !line.start_with?("+++") }
               .map { |line| line[1..].to_s }
               .join
    end

    def finding(category)
      { scanner: SCANNER_NAME, severity: SEVERITY, detail: "potential secret detected (#{category})" }
    end
  end
end
