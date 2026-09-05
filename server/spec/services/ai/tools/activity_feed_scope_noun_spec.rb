# frozen_string_literal: true

require "rails_helper"

# APO — the no-bare-fact rule, demonstrated on one offender.
# Design: docs/reference/platform-presentation-design-2026-09-05.md §2, row 2.
#
# THE INCIDENT, restated because this is the same query that caused it. The
# concierge reported no node instances in error while twelve were, having read
# a result key named `errors` that counts Ai::ExecutionEvent rows — AI agent
# execution failures — and presented it as fleet health. `get_system_health`
# had its key renamed after that. `get_activity_feed` reads the SAME
# `with_errors` execution-event query and still returned it as a bare `errors`,
# so the identical misreading was still available through a second door.
#
# The rule is that a name carries its scope: a count of errors must say what it
# counts. These examples assert the returned DATA, not a status code.
RSpec.describe "get_activity_feed scope nouns" do
  let(:account) { create(:account) }
  let(:user)    { create(:user, account: account, permissions: %w[ai.agents.read]) }
  let(:tool)    { Ai::Tools::ActivityMonitorTool.new(account: account, user: user) }

  let(:feed) { tool.execute(params: { action: "get_activity_feed", hours: 24 }) }
  let(:data) { feed[:success] ? (feed[:data] || feed) : feed }

  it "names the execution-event errors for what they are" do
    expect(data).to have_key(:agent_execution_errors)
    expect(data[:summary]).to have_key(:agent_execution_error_count)
  end

  it "no longer offers the bare noun a reader resolves to platform errors" do
    # CONTAINMENT plus PRESENCE: the absence claim only counts because the
    # renamed key above is asserted present. An absence assertion over a feed
    # that failed to build would pass while proving nothing.
    expect(data).not_to have_key(:errors)
    expect(data[:summary]).not_to have_key(:error_count)
  end

  it "still returns the same rows under the scoped name" do
    # `with_errors` keys on error_class, not on status — the scope the incident
    # ran through, so the fixture has to satisfy that column and not a
    # plausible-looking sibling.
    create(:ai_execution_event, account: account, event_type: "error",
                                status: "failed", error_class: "StandardError",
                                error_message: "boom")

    expect(data[:agent_execution_errors].size).to eq(1)
    expect(data[:summary][:agent_execution_error_count]).to eq(1)
  end

  it "says in its own description which errors it carries" do
    description = Ai::Tools::ActivityMonitorTool.action_definitions
                                                .fetch("get_activity_feed")[:description]

    expect(description).to match(/agent execution/i)
    expect(description).not_to match(/errors across the platform/i)
  end
end
