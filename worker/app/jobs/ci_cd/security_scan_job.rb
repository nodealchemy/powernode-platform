# frozen_string_literal: true

module CiCd
  # Runs AI security analysis on repositories
  # Queue: ci_cd_default
  # Retry: 2
  class SecurityScanJob < BaseJob
    sidekiq_options queue: "ci_cd_default", retry: 2

    DEFAULT_SECURITY_PROMPT = <<~PROMPT
      Perform a comprehensive security analysis of this codebase:

      1. **Dependency Vulnerabilities**: Check for known CVEs
      2. **Code Vulnerabilities**: SQL injection, XSS, CSRF, etc.
      3. **Authentication/Authorization**: JWT handling, session management
      4. **Secrets Exposure**: Hardcoded credentials, API keys
      5. **Configuration Issues**: Insecure defaults, debug modes
      6. **OWASP Top 10**: Check against current OWASP guidelines

      For each finding:
      - Severity: CRITICAL/HIGH/MEDIUM/LOW
      - Location: File path and line number
      - Description: What the issue is
      - Recommendation: How to fix it
      - Code Example: Fixed code if applicable

      Output as structured JSON with format:
      {
        "findings": [
          {
            "severity": "HIGH",
            "category": "injection",
            "location": { "file": "path/to/file.rb", "line": 42 },
            "title": "SQL Injection vulnerability",
            "description": "...",
            "recommendation": "...",
            "cwe_id": "CWE-89"
          }
        ],
        "summary": {
          "critical": 0,
          "high": 1,
          "medium": 3,
          "low": 5
        }
      }
    PROMPT

    # Run security scan on a repository
    # @param repository_id [String] The repository ID
    # @param options [Hash] Additional options
    def execute(repository_id, options = {})
      log_info "Starting security scan", repository_id: repository_id

      options = options.deep_symbolize_keys

      # Fetch repository and provider info
      repo_data = fetch_repository(repository_id)
      provider_data = fetch_provider(repo_data["provider_id"])

      # Clone repository to temp directory
      work_dir = clone_repository(repo_data, provider_data)

      begin
        # Fetch security prompt template or use default
        prompt = fetch_security_prompt(repo_data["account_id"]) || DEFAULT_SECURITY_PROMPT

        # Run Claude security analysis
        result = run_security_analysis(work_dir, prompt, options)

        # Parse and store results
        findings = parse_findings(result[:output])

        # Report results back to backend
        report_scan_results(repository_id, findings, options)

        # Create issues for critical findings if configured
        if options[:create_issues] && findings["summary"]&.dig("critical")&.positive?
          create_security_issues(repo_data, provider_data, findings)
        end

        log_info "Security scan completed",
                 repository_id: repository_id,
                 critical: findings.dig("summary", "critical") || 0,
                 high: findings.dig("summary", "high") || 0
      ensure
        # Clean up temp directory
        FileUtils.rm_rf(work_dir) if work_dir && File.directory?(work_dir)
      end
    rescue StandardError => e
      log_error "Security scan failed", e, repository_id: repository_id
      report_scan_error(repository_id, e)
      raise
    end

    private

    def fetch_repository(repository_id)
      response = api_client.get("/api/v1/internal/ci_cd/repositories/#{repository_id}")
      response.dig("data", "repository")
    end

    def fetch_provider(provider_id)
      response = api_client.get("/api/v1/internal/ci_cd/providers/#{provider_id}")
      response.dig("data", "provider")
    end

    def fetch_security_prompt(account_id)
      response = api_client.get("/api/v1/internal/ci_cd/prompt_templates", {
        account_id: account_id,
        category: "security",
        is_active: true
      })
      templates = response.dig("data", "prompt_templates") || []
      templates.first&.dig("content")
    rescue StandardError => e
      log_warn "Failed to fetch security prompt template, using default", exception: e.message
      nil
    end

    def clone_repository(repo_data, provider_data)
      work_dir = File.join(Dir.tmpdir, "security_scan_#{SecureRandom.hex(8)}")
      FileUtils.mkdir_p(work_dir)

      # Build clone URL with authentication
      clone_url = build_authenticated_url(repo_data["clone_url"], provider_data)

      # Clone the repository
      log_info "Cloning repository", full_name: repo_data["full_name"]

      result = Open3.capture3(
        "git", "clone", "--depth", "1", clone_url, work_dir,
        chdir: Dir.tmpdir
      )

      unless result[2].success?
        raise StandardError, "Failed to clone repository: #{result[1]}"
      end

      work_dir
    end

    def build_authenticated_url(clone_url, provider_data)
      uri = URI.parse(clone_url)
      uri.user = "git"
      uri.password = provider_data["api_token"]
      uri.to_s
    end

    def run_security_analysis(work_dir, prompt, options)
      # Execute Claude with the security prompt
      cmd = build_claude_command(options)

      output = nil
      error_output = nil
      exit_status = nil

      Open3.popen3(cmd, chdir: work_dir) do |stdin, stdout, stderr, wait_thr|
        stdin.write(prompt)
        stdin.close

        Timeout.timeout(options[:timeout_seconds] || 900) do
          output = stdout.read
          error_output = stderr.read
          exit_status = wait_thr.value
        end
      end

      {
        success: exit_status&.success?,
        output: output,
        error: error_output
      }
    end

    def build_claude_command(options)
      cmd_parts = ["claude", "--print"]
      cmd_parts << "--model" << options[:model] if options[:model]
      cmd_parts.join(" ")
    end

    def parse_findings(output)
      # Try to extract JSON from the output
      json_match = output.match(/\{[\s\S]*"findings"[\s\S]*\}/)

      if json_match
        JSON.parse(json_match[0])
      else
        # Return a structured response with the raw output
        {
          "findings" => [],
          "summary" => { "critical" => 0, "high" => 0, "medium" => 0, "low" => 0 },
          "raw_output" => output
        }
      end
    rescue JSON::ParserError => e
      log_warn "Failed to parse security findings JSON", exception: e.message
      {
        "findings" => [],
        "summary" => { "critical" => 0, "high" => 0, "medium" => 0, "low" => 0 },
        "raw_output" => output,
        "parse_error" => e.message
      }
    end

    def report_scan_results(repository_id, findings, options)
      api_client.post("/api/v1/internal/ci_cd/security_scans", {
        security_scan: {
          repository_id: repository_id,
          status: "completed",
          findings: findings["findings"],
          summary: findings["summary"],
          completed_at: Time.current.iso8601
        }
      })
    rescue StandardError => e
      log_warn "Failed to report scan results", exception: e.message
    end

    def report_scan_error(repository_id, exception)
      api_client.post("/api/v1/internal/ci_cd/security_scans", {
        security_scan: {
          repository_id: repository_id,
          status: "failed",
          error_message: exception.message,
          completed_at: Time.current.iso8601
        }
      })
    rescue StandardError => e
      log_warn "Failed to report scan error", exception: e.message
    end

    def create_security_issues(repo_data, provider_data, findings)
      critical_findings = findings["findings"]&.select { |f| f["severity"] == "CRITICAL" } || []

      critical_findings.each do |finding|
        GitProviderClient.new(
          provider_type: provider_data["provider_type"],
          base_url: provider_data["base_url"],
          api_token: provider_data["api_token"]
        ).create_issue(
          repository: repo_data["full_name"],
          title: "🚨 [Security] #{finding['title']}",
          body: format_issue_body(finding),
          labels: ["security", "critical"]
        )
      end
    rescue StandardError => e
      log_warn "Failed to create security issues", exception: e.message
    end

    def format_issue_body(finding)
      <<~BODY
        ## Security Finding: #{finding['title']}

        **Severity**: #{finding['severity']}
        **Category**: #{finding['category']}
        **CWE**: #{finding['cwe_id']}

        ### Location
        - File: `#{finding.dig('location', 'file')}`
        - Line: #{finding.dig('location', 'line')}

        ### Description
        #{finding['description']}

        ### Recommendation
        #{finding['recommendation']}

        ---
        *Detected by AI Security Scan*
      BODY
    end
  end
end
