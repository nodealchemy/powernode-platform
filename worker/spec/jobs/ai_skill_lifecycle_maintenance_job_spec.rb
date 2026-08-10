# frozen_string_literal: true

require "rails_helper"

# IMP-89bf582d6ee5 — the maintenance crons gate server-side on the
# skill_optimization feature flag (default OFF), and this job used to log
# "completed successfully" without ever reading the response body — so a
# fresh install ran three no-op crons for months while the logs said
# everything worked. The job now surfaces the server's {skipped:, reason:}
# verdict LOUDLY. Deliberately logging-only: flipping the flag on is an
# explicit operator decision, not a side effect of this fix.
RSpec.describe AiSkillLifecycleMaintenanceJob, type: :job do
  let(:api_client) { instance_double(BackendApiClient) }
  let(:job) { described_class.new }

  before do
    mock_powernode_worker_config
    allow(job).to receive(:api_client).and_return(api_client)
    allow(job).to receive(:log_info)
    allow(job).to receive(:log_warn)
  end

  it "logs a LOUD no-op warning (not success) when the server skipped on the disabled flag" do
    allow(api_client).to receive(:post)
      .with("/api/v1/ai/skill_graph/maintenance/daily")
      .and_return("data" => { "skipped" => true, "reason" => "skill_optimization feature flag disabled" })

    result = job.execute("daily")

    expect(job).to have_received(:log_warn)
      .with(/daily maintenance DID NOT RUN.*skill_optimization feature flag disabled/)
    expect(job).not_to have_received(:log_info)
      .with(/completed successfully/)
    expect(result).to eq(skipped: true, reason: "skill_optimization feature flag disabled")
  end

  it "still logs success when the server actually ran the maintenance" do
    allow(api_client).to receive(:post)
      .with("/api/v1/ai/skill_graph/maintenance/weekly")
      .and_return("data" => { "effectiveness_recalculated" => 12 })

    result = job.execute("weekly")

    expect(job).to have_received(:log_info)
      .with(/weekly maintenance completed successfully/)
    expect(job).not_to have_received(:log_warn)
    expect(result).to eq(skipped: false)
  end

  it "treats a bodyless/unparseable response as a run, not a skip (fail toward success logging)" do
    allow(api_client).to receive(:post).and_return(nil)

    result = job.execute("monthly")

    expect(job).to have_received(:log_info).with(/monthly maintenance completed successfully/)
    expect(result).to eq(skipped: false)
  end
end
