# frozen_string_literal: true

module SupplyChain
  class ContainerScanService
    class ScanError < StandardError; end

    SUPPORTED_SCANNERS = %w[trivy grype].freeze

    attr_reader :account, :image, :options

    def initialize(account:, image:, options: {})
      @account = account
      @image = image
      @options = options.with_indifferent_access
      @logger = Rails.logger
    end

    def scan!
      scanner = options[:scanner] || "trivy"
      validate_scanner!(scanner)

      scan = create_scan_record(scanner)
      scan.start!

      begin
        results = perform_scan(scanner, image.full_reference)

        scan.complete!(results[:vulnerabilities])

        # Update image vulnerability counts
        image.update_vulnerability_counts!(
          critical: scan.critical_count,
          high: scan.high_count,
          medium: scan.medium_count,
          low: scan.low_count
        )

        # Evaluate policies
        evaluate_policies(image)

        scan
      rescue StandardError => e
        scan.fail!(e.message)
        @logger.error "[ContainerScanService] Scan failed: #{e.message}"
        raise ScanError, "Container scan failed: #{e.message}"
      end
    end

    def evaluate_policies(img = nil)
      img ||= image
      policies = account.supply_chain_image_policies.active.ordered

      results = []
      overall_passed = true

      policies.each do |policy|
        result = policy.evaluate(img)
        results << result

        if !result[:passed] && policy.blocking?
          overall_passed = false
        end
      end

      # Update image status based on policy results
      if !overall_passed
        img.quarantine!("Failed policy evaluation")
      elsif results.all? { |r| r[:passed] || r[:skipped] }
        img.verify! if img.unverified?
      end

      {
        passed: overall_passed,
        policy_results: results
      }
    end

    private

    def validate_scanner!(scanner)
      unless SUPPORTED_SCANNERS.include?(scanner)
        raise ScanError, "Unsupported scanner: #{scanner}. Supported: #{SUPPORTED_SCANNERS.join(', ')}"
      end
    end

    def create_scan_record(scanner)
      SupplyChain::VulnerabilityScan.create!(
        container_image: image,
        account: account,
        scanner_name: scanner,
        scanner_version: get_scanner_version(scanner),
        status: "pending",
        triggered_by: options[:user]
      )
    end

    def perform_scan(scanner, image_reference)
      case scanner
      when "trivy"
        scan_with_trivy(image_reference)
      when "grype"
        scan_with_grype(image_reference)
      else
        { vulnerabilities: [] }
      end
    end

    def scan_with_trivy(image_reference)
      # This is a placeholder for actual Trivy integration
      # In production, this would execute trivy CLI or call the Trivy API

      @logger.info "[ContainerScanService] Scanning #{image_reference} with Trivy"

      # Simulated response structure matching Trivy JSON output
      {
        vulnerabilities: []
      }
    end

    def scan_with_grype(image_reference)
      # This is a placeholder for actual Grype integration
      # In production, this would execute grype CLI

      @logger.info "[ContainerScanService] Scanning #{image_reference} with Grype"

      {
        vulnerabilities: []
      }
    end

    def get_scanner_version(scanner)
      # Get scanner version - would execute version command
      case scanner
      when "trivy" then "0.50.0"
      when "grype" then "0.74.0"
      else "unknown"
      end
    end

    def parse_trivy_output(output)
      results = JSON.parse(output)
      vulnerabilities = []

      (results["Results"] || []).each do |result|
        (result["Vulnerabilities"] || []).each do |vuln|
          vulnerabilities << {
            "id" => vuln["VulnerabilityID"],
            "pkg_name" => vuln["PkgName"],
            "installed_version" => vuln["InstalledVersion"],
            "fixed_version" => vuln["FixedVersion"],
            "severity" => vuln["Severity"]&.downcase,
            "title" => vuln["Title"],
            "description" => vuln["Description"],
            "cvss" => extract_cvss(vuln),
            "layer" => result["Target"]
          }
        end
      end

      { vulnerabilities: vulnerabilities }
    end

    def parse_grype_output(output)
      results = JSON.parse(output)
      vulnerabilities = []

      (results["matches"] || []).each do |match|
        vuln = match["vulnerability"]
        artifact = match["artifact"]

        vulnerabilities << {
          "id" => vuln["id"],
          "pkg_name" => artifact["name"],
          "installed_version" => artifact["version"],
          "fixed_version" => vuln.dig("fix", "versions", 0),
          "severity" => vuln["severity"]&.downcase,
          "description" => vuln["description"],
          "cvss" => extract_grype_cvss(vuln)
        }
      end

      { vulnerabilities: vulnerabilities }
    end

    def extract_cvss(vuln)
      cvss = vuln["CVSS"] || {}
      nvd = cvss["nvd"] || cvss.values.first || {}

      {
        "score" => nvd["V3Score"] || nvd["V2Score"],
        "vector" => nvd["V3Vector"] || nvd["V2Vector"]
      }
    end

    def extract_grype_cvss(vuln)
      cvss = vuln["cvss"] || []
      primary = cvss.first || {}

      {
        "score" => primary.dig("metrics", "baseScore"),
        "vector" => primary["vector"]
      }
    end
  end
end
