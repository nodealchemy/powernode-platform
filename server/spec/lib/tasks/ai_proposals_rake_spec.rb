# frozen_string_literal: true

require "rails_helper"

RSpec.describe "ai:proposals:backfill_expired" do
  let(:account) { create(:account) }
  let(:agent) { create(:ai_agent, account: account) }

  def run_task(env: {})
    previous_application = Rake.application
    previous_env = env.keys.index_with { |k| ENV[k] }
    original = $stdout
    begin
      env.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
      $stdout = StringIO.new
      Rake.application = Rake::Application.new
      Rake.application.rake_require("tasks/ai_proposals", [ Rails.root.join("lib").to_s ], [])
      Rake::Task.define_task(:environment)
      Rake::Task["ai:proposals:backfill_expired"].invoke
      $stdout.string
    ensure
      $stdout = original
      previous_env.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
      Rake.application = previous_application
    end
  end

  let!(:lapse) do
    row = account.ai_agent_proposals.create!(ai_agent_id: agent.id, title: "lapsed", proposal_type: "feature",
                                             priority: "low", review_deadline: 3.days.ago)
    row.update_columns(status: "withdrawn", updated_at: 1.day.ago)
    row
  end

  it "is a dry run unless APPLY=1" do
    out = run_task(env: { "APPLY" => nil })
    expect(out).to include("DRY RUN")
    expect(lapse.reload.status).to eq("withdrawn")
  end

  it "does not treat APPLY=0 or APPLY=true as consent" do
    run_task(env: { "APPLY" => "0" })
    run_task(env: { "APPLY" => "true" })
    expect(lapse.reload.status).to eq("withdrawn")
  end

  it "applies with APPLY=1" do
    run_task(env: { "APPLY" => "1" })
    expect(lapse.reload.status).to eq("expired")
  end
end
