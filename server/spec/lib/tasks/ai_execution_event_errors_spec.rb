# frozen_string_literal: true

require "rails_helper"

# ai:scrub_execution_event_errors — run on EVERY boot of a module-composed hub
# by rails-start.sh (db:seed is first-boot only there), and by hand.
RSpec.describe "ai:scrub_execution_event_errors rake task" do
  let(:account) { create(:account) }
  let(:secret) { %w[hunter 2].join }

  def event!(message)
    Ai::ExecutionEvent.create!(account: account, source_type: "Ai::ApprovalRequest", source_id: SecureRandom.uuid,
                               event_type: "approval_execution", status: "failed", error_message: message)
  end

  def run_task(env: {})
    previous = env.keys.index_with { |k| ENV[k] }
    env.each { |k, v| ENV[k] = v }
    app = Rake.application
    Rake.application = Rake::Application.new
    Rake.application.rake_require("tasks/ai_execution_event_errors", [ Rails.root.join("lib").to_s ], [])
    Rake::Task.define_task(:environment)
    out = StringIO.new
    original = $stdout
    $stdout = out
    Rake::Task["ai:scrub_execution_event_errors"].invoke
    out.string
  ensure
    $stdout = original
    previous.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
    Rake.application = app
  end

  it "scrubs, records the done marker, and is a no-op on the next boot" do
    row = event!("x password=#{secret}")

    run_task
    expect(row.reload.error_message).not_to include(secret)
    expect(SiteSetting.get(Ai::ExecutionEventErrorScrub::DONE_MARKER)).to eq("true")

    later = event!("y password=#{secret}")
    output = run_task
    expect(later.reload.error_message).to include(secret)
    expect(output).to include("already done")
  end

  it "runs again past the marker with FORCE=1" do
    run_task
    later = event!("y password=#{secret}")

    run_task(env: { "FORCE" => "1" })

    expect(later.reload.error_message).not_to include(secret)
  end

  it "stays within a time budget and leaves the marker unset when it was cut short" do
    event!("x password=#{secret}")
    event!("y password=#{secret}")
    stub_const("Ai::ExecutionEventErrorScrub::BATCH_SIZE", 1)

    output = run_task(env: { "BUDGET" => "0" })

    expect(SiteSetting.get(Ai::ExecutionEventErrorScrub::DONE_MARKER)).to be_blank
    expect(output).to include("complete=false")
  end

  it "never raises, so a boot hook cannot fail the boot" do
    allow_any_instance_of(Ai::ExecutionEventErrorScrub).to receive(:call).and_raise(StandardError, "boom")

    expect { run_task }.not_to raise_error
  end
end
