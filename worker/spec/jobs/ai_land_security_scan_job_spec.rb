# frozen_string_literal: true

require "rails_helper"

# Worker-side deep security scan (G4) on the REAL staged land diff. The job
# checks out the source branch, diffs it against the land base, runs the secret
# scanner over the diff, and POSTs findings back to the server's land park-back
# surface. The checkout/run plumbing and the backend client are mocked.
RSpec.describe AiLandSecurityScanJob, type: :job do
  it_behaves_like "a base job", described_class

  let(:job) { described_class.new }
  let(:api_client) { instance_double(BackendApiClient) }

  let(:args) do
    {
      "land_id" => "L1",
      "repository" => "acme/widget",
      "source_branch" => "campaign/abc",
      "target_branch" => "develop",
      "base_sha" => "basesha123"
    }
  end

  before do
    mock_powernode_worker_config
    allow(job).to receive(:api_client).and_return(api_client)
    allow(job).to receive(:log_info)
    allow(job).to receive(:log_error)
    allow_any_instance_of(BaseJob).to receive(:check_runaway_loop).and_return(nil)
    allow(job).to receive(:checkout_workspace).and_return("/tmp/ws")
    allow(FileUtils).to receive(:rm_rf)
    allow(File).to receive(:directory?).and_return(false)
    # Default: brakeman not available / non-JSON output → cleanly skipped.
    allow(job).to receive(:run_workspace_command) do |_ws, cmd, **_opts|
      if cmd.include?("git diff")
        { exit_code: 0, output: clean_diff, error: nil }
      else
        { exit_code: 127, output: "brakeman: command not found", error: nil }
      end
    end
  end

  let(:clean_diff) do
    <<~DIFF
      diff --git a/lib/calc.rb b/lib/calc.rb
      --- a/lib/calc.rb
      +++ b/lib/calc.rb
      @@ -1,2 +1,3 @@
      +def add(a, b)
      +  a + b
      +end
    DIFF
  end

  let(:secret_diff) do
    <<~DIFF
      diff --git a/config.rb b/config.rb
      --- a/config.rb
      +++ b/config.rb
      @@ -1,1 +1,2 @@
      +api_key = "sk-ABCDEF1234567890ABCDEF"
    DIFF
  end

  let(:bundler_audit_high) do
    {
      "results" => [
        { "type" => "unpatched_gem", "gem" => { "name" => "nokogiri", "version" => "1.10.0" },
          "advisory" => { "id" => "CVE-2222-0001", "criticality" => "high", "title" => "XXE" } }
      ]
    }.to_json
  end

  it "runs on the ai_orchestration queue" do
    expect(described_class.get_sidekiq_options["queue"]).to eq("ai_orchestration")
  end

  describe "#execute" do
    it "checks out the source branch and diffs against the recorded base sha" do
      expect(job).to receive(:checkout_workspace).with("acme/widget", "campaign/abc").and_return("/tmp/ws")
      expect(job).to receive(:run_workspace_command)
        .with("/tmp/ws", a_string_matching(/git diff .*basesha123.*HEAD/), any_args)
        .and_return(exit_code: 0, output: clean_diff, error: nil)
      allow(api_client).to receive(:post).and_return("data" => { "blocked" => false })
      allow(AiCampaignLandCiPollJob).to receive(:perform_async)

      job.execute(args)
    end

    it "posts a blocking finding and does NOT advance to CI when the diff leaks a secret" do
      allow(job).to receive(:run_workspace_command) do |_ws, cmd, **_o|
        cmd.include?("git diff") ? { exit_code: 0, output: secret_diff, error: nil } : { exit_code: 127, output: "", error: nil }
      end

      expect(api_client).to receive(:post).with(
        "/api/v1/internal/ai/campaign_lands/L1/security_findings",
        hash_including(findings: array_including(hash_including(severity: "critical")), scanners: array_including("worker_diff_secret_scan"))
      ).and_return("data" => { "blocked" => true })
      expect(AiCampaignLandCiPollJob).not_to receive(:perform_async)

      job.execute(args)
    end

    it "never posts the raw secret value back to the server" do
      allow(job).to receive(:run_workspace_command) do |_ws, cmd, **_o|
        cmd.include?("git diff") ? { exit_code: 0, output: secret_diff, error: nil } : { exit_code: 127, output: "", error: nil }
      end
      posted = nil
      allow(api_client).to receive(:post) { |_path, body| posted = body; { "data" => { "blocked" => true } } }

      job.execute(args)

      expect(posted.to_json).not_to include("sk-ABCDEF1234567890ABCDEF")
    end

    it "posts a blocking finding and does NOT advance to CI when a dependency has a HIGH CVE" do
      allow(job).to receive(:run_workspace_command) do |_ws, cmd, **_o|
        if cmd.include?("git diff")
          { exit_code: 0, output: clean_diff, error: nil }
        elsif cmd.include?("bundle-audit")
          { exit_code: 1, output: bundler_audit_high, error: nil }
        else
          { exit_code: 127, output: "command not found", error: nil }
        end
      end

      expect(api_client).to receive(:post).with(
        "/api/v1/internal/ai/campaign_lands/L1/security_findings",
        hash_including(
          findings: array_including(hash_including(scanner: "dependency-cve", severity: "high")),
          scanners: array_including("dependency-cve")
        )
      ).and_return("data" => { "blocked" => true })
      expect(AiCampaignLandCiPollJob).not_to receive(:perform_async)

      job.execute(args)
    end

    it "records the dependency-cve scanner but does NOT block on a clean dependency scan" do
      allow(job).to receive(:run_workspace_command) do |_ws, cmd, **_o|
        if cmd.include?("git diff")
          { exit_code: 0, output: clean_diff, error: nil }
        elsif cmd.include?("bundle-audit")
          { exit_code: 0, output: { "results" => [] }.to_json, error: nil }
        else
          { exit_code: 127, output: "command not found", error: nil }
        end
      end
      posted = nil
      allow(api_client).to receive(:post) { |_path, body| posted = body; { "data" => { "blocked" => false } } }
      expect(AiCampaignLandCiPollJob).to receive(:perform_async)
        .with("land_id" => "L1", "gate" => "staged", "attempt" => 0)

      job.execute(args)

      expect(posted[:findings]).to be_empty
      expect(posted[:scanners]).to include("dependency-cve")
    end

    it "advances to the staged-CI poll when the diff is clean" do
      allow(api_client).to receive(:post).and_return("data" => { "blocked" => false })
      expect(AiCampaignLandCiPollJob).to receive(:perform_async)
        .with("land_id" => "L1", "gate" => "staged", "attempt" => 0)

      job.execute(args)
    end

    it "skips the deep scan and advances to CI when no repository can be resolved" do
      expect(job).not_to receive(:checkout_workspace)
      expect(api_client).not_to receive(:post)
      expect(AiCampaignLandCiPollJob).to receive(:perform_async)
        .with("land_id" => "L1", "gate" => "staged", "attempt" => 0)

      job.execute(args.merge("repository" => nil))
    end

    it "no-ops without a land_id" do
      expect(job).not_to receive(:checkout_workspace)
      expect(AiCampaignLandCiPollJob).not_to receive(:perform_async)
      job.execute("repository" => "acme/widget")
    end

    it "parks for human review (does NOT advance to CI) when the checkout fails" do
      allow(job).to receive(:checkout_workspace).and_raise(StandardError.new("clone denied"))

      expect(api_client).to receive(:post).with(
        "/api/v1/internal/ai/campaign_lands/L1/security_findings",
        hash_including(
          findings: array_including(
            hash_including(scanner: "land-security-scan", severity: "high")
          ),
          scanners: array_including("land-security-scan")
        )
      ).and_return("data" => { "blocked" => true })
      expect(AiCampaignLandCiPollJob).not_to receive(:perform_async)

      result = job.execute(args)
      expect(result).to include(blocked: true, scan_incomplete: true)
    end

    it "parks for human review (does NOT advance to CI) when the diff cannot be produced" do
      # Every `git diff` invocation (base-sha attempt AND the fallback) exits
      # non-zero — the scan cannot complete, so the land must park, not pass.
      allow(job).to receive(:run_workspace_command) do |_ws, cmd, **_o|
        if cmd.include?("git diff")
          { exit_code: 128, output: "fatal: bad revision", error: nil }
        else
          { exit_code: 127, output: "", error: nil }
        end
      end

      expect(api_client).to receive(:post).with(
        "/api/v1/internal/ai/campaign_lands/L1/security_findings",
        hash_including(
          findings: array_including(
            hash_including(scanner: "land-security-scan", severity: "high")
          )
        )
      ).and_return("data" => { "blocked" => true })
      expect(AiCampaignLandCiPollJob).not_to receive(:perform_async)

      job.execute(args)
    end

    it "keeps the incomplete-scan park-back detail free of underlying error content" do
      allow(job).to receive(:checkout_workspace)
        .and_raise(StandardError.new("https://x-token-abc123@git.example/repo.git denied"))
      posted = nil
      allow(api_client).to receive(:post) { |_path, body| posted = body; { "data" => { "blocked" => true } } }

      job.execute(args)

      expect(posted.to_json).not_to include("x-token-abc123")
    end

    it "cleans up the workspace afterwards" do
      allow(File).to receive(:directory?).with("/tmp/ws").and_return(true)
      allow(api_client).to receive(:post).and_return("data" => { "blocked" => false })
      allow(AiCampaignLandCiPollJob).to receive(:perform_async)

      job.execute(args)

      expect(FileUtils).to have_received(:rm_rf).with("/tmp/ws")
    end
  end
end
