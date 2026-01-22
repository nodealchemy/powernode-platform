# frozen_string_literal: true

FactoryBot.define do
  factory :supply_chain_scan_execution, class: "SupplyChain::ScanExecution" do
    association :scan_instance, factory: :supply_chain_scan_instance
    association :account
    triggered_by { nil }
    sequence(:execution_id) { |n| "exec-#{Time.current.strftime('%Y%m%d%H%M%S')}-#{SecureRandom.hex(4)}-#{n}" }
    trigger_type { "manual" }
    status { "pending" }
    input_data { {} }
    output_data { {} }
    metadata { {} }
    logs { "" }

    trait :pending do
      status { "pending" }
      started_at { nil }
      completed_at { nil }
    end

    trait :running do
      status { "running" }
      started_at { Time.current }
      completed_at { nil }
      logs { "[#{Time.current.iso8601}] Scan started\n[#{Time.current.iso8601}] Processing dependencies..." }
    end

    trait :completed do
      status { "completed" }
      started_at { 5.minutes.ago }
      completed_at { Time.current }
      duration_ms { 300_000 } # 5 minutes
      output_data do
        {
          total_packages_scanned: rand(50..200),
          vulnerabilities_found: rand(0..20),
          critical_count: rand(0..3),
          high_count: rand(0..5),
          medium_count: rand(0..10),
          low_count: rand(0..15)
        }
      end
      logs do
        <<~LOGS
          [#{5.minutes.ago.iso8601}] Scan started
          [#{4.minutes.ago.iso8601}] Fetching dependency tree...
          [#{3.minutes.ago.iso8601}] Scanning 150 packages...
          [#{2.minutes.ago.iso8601}] Analyzing vulnerabilities...
          [#{1.minute.ago.iso8601}] Generating report...
          [#{Time.current.iso8601}] Scan completed successfully
        LOGS
      end
    end

    trait :failed do
      status { "failed" }
      started_at { 2.minutes.ago }
      completed_at { Time.current }
      duration_ms { 120_000 } # 2 minutes
      error_message { "Scan failed: Unable to fetch dependency tree - timeout after 60 seconds" }
      logs do
        <<~LOGS
          [#{2.minutes.ago.iso8601}] Scan started
          [#{1.minute.ago.iso8601}] Fetching dependency tree...
          [#{Time.current.iso8601}] ERROR: Connection timeout
          [#{Time.current.iso8601}] Scan failed
        LOGS
      end
    end

    trait :cancelled do
      status { "cancelled" }
      started_at { 1.minute.ago }
      completed_at { Time.current }
      duration_ms { 60_000 } # 1 minute
      logs do
        <<~LOGS
          [#{1.minute.ago.iso8601}] Scan started
          [#{Time.current.iso8601}] Scan cancelled by user
        LOGS
      end
    end

    trait :manual do
      trigger_type { "manual" }
      association :triggered_by, factory: :user
    end

    trait :scheduled do
      trigger_type { "scheduled" }
      triggered_by { nil }
    end

    trait :webhook do
      trigger_type { "webhook" }
      triggered_by { nil }
      input_data do
        {
          webhook_source: "github",
          event_type: "push",
          repository: "org/repo",
          branch: "main"
        }
      end
    end

    trait :pipeline do
      trigger_type { "pipeline" }
      triggered_by { nil }
      input_data do
        {
          pipeline_id: "pipeline-#{SecureRandom.hex(4)}",
          stage: "security-scan",
          job_id: "job-#{SecureRandom.hex(4)}"
        }
      end
    end

    trait :api do
      trigger_type { "api" }
      input_data do
        {
          api_client: "ci-integration",
          request_id: SecureRandom.uuid
        }
      end
    end

    trait :with_vulnerabilities do
      status { "completed" }
      output_data do
        {
          total_packages_scanned: 150,
          vulnerabilities_found: 12,
          critical_count: 2,
          high_count: 4,
          medium_count: 4,
          low_count: 2,
          vulnerabilities: [
            {
              id: "CVE-2024-12345",
              severity: "critical",
              package: "lodash",
              version: "4.17.15",
              fixed_version: "4.17.21"
            },
            {
              id: "CVE-2024-67890",
              severity: "high",
              package: "axios",
              version: "0.21.1",
              fixed_version: "1.6.0"
            }
          ]
        }
      end
    end

    trait :clean_scan do
      status { "completed" }
      output_data do
        {
          total_packages_scanned: 100,
          vulnerabilities_found: 0,
          critical_count: 0,
          high_count: 0,
          medium_count: 0,
          low_count: 0
        }
      end
    end

    trait :long_running do
      status { "running" }
      started_at { 30.minutes.ago }
    end

    trait :quick_scan do
      status { "completed" }
      started_at { 30.seconds.ago }
      completed_at { Time.current }
      duration_ms { 30_000 } # 30 seconds
    end

    trait :with_detailed_logs do
      logs do
        <<~LOGS
          [#{10.minutes.ago.iso8601}] Scan initiated by user
          [#{10.minutes.ago.iso8601}] Loading scan configuration...
          [#{9.minutes.ago.iso8601}] Configuration loaded successfully
          [#{9.minutes.ago.iso8601}] Fetching dependency manifest...
          [#{8.minutes.ago.iso8601}] Found package.json
          [#{8.minutes.ago.iso8601}] Resolving 150 direct dependencies...
          [#{7.minutes.ago.iso8601}] Resolving 450 transitive dependencies...
          [#{6.minutes.ago.iso8601}] Total: 600 packages to scan
          [#{5.minutes.ago.iso8601}] Querying vulnerability databases...
          [#{4.minutes.ago.iso8601}] NVD: 12 matches found
          [#{4.minutes.ago.iso8601}] OSV: 8 matches found
          [#{3.minutes.ago.iso8601}] GitHub Advisory: 5 matches found
          [#{2.minutes.ago.iso8601}] Deduplicating results...
          [#{2.minutes.ago.iso8601}] 15 unique vulnerabilities identified
          [#{1.minute.ago.iso8601}] Generating scan report...
          [#{Time.current.iso8601}] Scan completed successfully
        LOGS
      end
    end

    trait :with_triggered_by do
      association :triggered_by, factory: :user
    end
  end
end
