# frozen_string_literal: true

require "rails_helper"

# server/lib/tasks/mcp_sessions.rake mcp:dedupe_client_agents — reports MCP
# client agents duplicated per (client name, user) and merges them only when
# CONFIRM=yes (finding #25).
RSpec.describe "mcp:dedupe_client_agents" do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:provider) { create(:ai_provider, account: account) }
  let!(:agents) do
    (1..5).map do |n|
      create(:ai_agent, :mcp_client, account: account, creator: user, provider: provider,
                                     name: "Claude Code (headersHelper) ##{n}",
                                     mcp_metadata: { "oauth_application_name" => "Claude Code (headersHelper)" })
    end
  end

  # Rake::Application keeps this off the global Rake state (mirrors
  # spec/lib/tasks/learnings_backfill_spec.rb).
  def run_task(env = {})
    previous_application = Rake.application
    previous_env = env.keys.to_h { |k| [ k, ENV[k] ] }
    output = StringIO.new
    original_stdout = $stdout
    env.each { |k, v| ENV[k] = v }
    Rake.application = Rake::Application.new
    Rake.application.rake_require("tasks/mcp_sessions", [ Rails.root.join("lib").to_s ], [])
    Rake::Task.define_task(:environment)
    $stdout = output
    Rake::Task["mcp:dedupe_client_agents"].invoke
    output.string
  ensure
    $stdout = original_stdout
    previous_env&.each { |k, v| ENV[k] = v }
    Rake.application = previous_application
  end

  it "reports count, first 3 and last 1 and deletes nothing by default" do
    out = run_task("ACCOUNT_ID" => account.id)

    expect(out).to include("Duplicates to merge: 4")
    expect(out).to include("first: Claude Code (headersHelper) #2")
    expect(out).to include("last:  Claude Code (headersHelper) #5")
    expect(out).to include("Dry run: nothing changed")
    expect(Ai::Agent.where(id: agents.map(&:id)).count).to eq(5)
  end

  it "reports across every account when ACCOUNT_ID is not given" do
    other_account = create(:account)
    other_user = create(:user, account: other_account)
    other_provider = create(:ai_provider, account: other_account)
    2.times do |i|
      create(:ai_agent, :mcp_client, account: other_account, creator: other_user, provider: other_provider,
                                     name: "Cursor ##{i + 1}", mcp_metadata: { "oauth_application_name" => "Cursor" })
    end

    out = run_task("ACCOUNT_ID" => nil)

    expect(out).to include("Claude Code (headersHelper) / user #{user.id}: keep Claude Code (headersHelper) #1")
    expect(out).to include("Cursor / user #{other_user.id}: keep Cursor #1")
    expect(out).to include("Duplicates to merge: 5")
    expect(Ai::Agent.where(agent_type: "mcp_client").count).to eq(7)
  end

  it "prints what a merge would drop for each duplicate" do
    create(:ai_agent_budget, agent: agents.last, account: account)

    out = run_task("ACCOUNT_ID" => account.id)

    expect(out).to match(/Claude Code \(headersHelper\) #5 .*drops ai_agent_budgets\.agent_id=1$/)
    expect(out).to match(/Claude Code \(headersHelper\) #4 .*drops none/)
  end

  it "merges into #1 only with CONFIRM=yes" do
    out = run_task("ACCOUNT_ID" => account.id, "CONFIRM" => "yes")

    expect(out).to include("Merged 4 agent(s).")
    expect(Ai::Agent.where(id: agents.map(&:id)).pluck(:name)).to eq([ "Claude Code (headersHelper) #1" ])
  end
end
