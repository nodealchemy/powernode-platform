# frozen_string_literal: true

require "rails_helper"

# The cron door onto the server's approval sweep, which since IMP-0213523480d1
# also settles approved requests whose post-commit dispatch never started.
# The job only reports; a settled strand is an operator signal, so it is
# logged at warn rather than dropped with the routine expiry count.
RSpec.describe AiApprovalExpiryJob, type: :job do
  let(:job) { described_class.new }
  let(:api_client) { instance_spy(BackendApiClient) }
  let(:sweep_path) { "/api/v1/internal/ai/approval_requests/expire_overdue" }

  before do
    allow(job).to receive(:api_client).and_return(api_client)
    allow(job).to receive(:log_warn)
    allow(api_client).to receive(:post)
      .and_return({ "success" => true, "data" => { "expired_count" => 0,
                                                   "stranded_failed_count" => 0,
                                                   "stranded_redispatched_count" => 0 } })
  end

  it "POSTs the internal approval sweep path" do
    job.execute({})

    expect(api_client).to have_received(:post).with(sweep_path)
  end

  it "stays quiet when no dispatch was stranded" do
    job.execute({})

    expect(job).not_to have_received(:log_warn)
  end

  it "warns with the counts when the sweep settled stranded dispatches" do
    allow(api_client).to receive(:post)
      .and_return({ "success" => true, "data" => { "expired_count" => 0,
                                                   "stranded_failed_count" => 2,
                                                   "stranded_redispatched_count" => 1 } })

    job.execute({})

    expect(job).to have_received(:log_warn).with(a_string_including("2 failed, 1 re-dispatched"))
  end

  it "tolerates a server that does not report stranded counts" do
    allow(api_client).to receive(:post)
      .and_return({ "success" => true, "data" => { "expired_count" => 3 } })

    expect { job.execute({}) }.not_to raise_error
    expect(job).not_to have_received(:log_warn)
  end
end
