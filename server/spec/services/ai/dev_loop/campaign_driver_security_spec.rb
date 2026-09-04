# frozen_string_literal: true

require "rails_helper"

# Security hardening (gap-audit #1, #8): campaign delegation must only wire the caller's
# OWN account's agent/mission onto a loop (cross-account IDOR guard), and a platform_*
# delegation must carry the executor ref it needs (no wedged loops).
RSpec.describe Ai::DevLoop::CampaignDriver, "delegation security" do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:driver) { described_class.new(account: account, user: user) }
  let(:campaign) { driver.start(name: "SecCampaign")[:campaign] }
  let(:loop_record) { campaign.ralph_loops.first }

  describe "#delegate target validation" do
    it "rejects a platform_agent target whose agent is not in the account" do
      expect { driver.delegate(campaign, driver_kind: "platform_agent", target: { agent_id: SecureRandom.uuid }) }
        .to raise_error(ArgumentError, /agent not found in this account/)
      expect(loop_record.reload.driver_kind).to eq("claude_code") # unchanged — raised before mutation
    end

    it "rejects a foreign-account mission (cross-account IDOR) and wires nothing" do
      foreign = create(:ai_mission) # different account
      expect { driver.delegate(campaign, driver_kind: "platform_mission", target: { mission_id: foreign.id }) }
        .to raise_error(ArgumentError, /mission not found in this account/)
      expect(loop_record.reload.mission_id).to be_nil
    end

    it "accepts a platform_mission target owned by the account" do
      mine = create(:ai_mission, account: account)
      driver.delegate(campaign, driver_kind: "platform_mission", target: { mission_id: mine.id })
      expect(loop_record.reload.mission_id).to eq(mine.id)
    end

    # platform_agent: an empty target RESOLVES to the Platform Developer
    # canonical when one exists (HIER-P2B-ENG; pinned in
    # spec/services/ai/tools/dev_loop_tool_platform_developer_spec.rb) and
    # still raises when none does — the default never wedges a loop on nil.
    it "rejects platform_agent / platform_mission with an empty target (no wedged loop)" do
      expect(Ai::Agent.for_account(account.id).exists?(slug: Ai::RalphLoop::PLATFORM_AGENT_DEFAULT_SLUG)).to be(false)
      expect { driver.delegate(campaign, driver_kind: "platform_agent", target: {}) }
        .to raise_error(ArgumentError, /requires target.agent_id/)
      expect { driver.delegate(campaign, driver_kind: "platform_mission", target: {}) }
        .to raise_error(ArgumentError, /requires target.mission_id/)
    end

    it "rejects a foreign-account team (platform_team — agent 'group' unified into teams)" do
      foreign_team = create(:ai_agent_team)
      expect { driver.delegate(campaign, driver_kind: "platform_team", target: { team_id: foreign_team.id }) }
        .to raise_error(ArgumentError, /team not found in this account/)
    end

    it "accepts a platform_team target owned by the account" do
      team = create(:ai_agent_team, account: account)
      driver.delegate(campaign, driver_kind: "platform_team", target: { team_id: team.id })
      expect(loop_record.reload.driver_target).to eq("team_id" => team.id)
    end
  end

  describe "RalphLoop mission ownership backstop" do
    it "is invalid when wired to a mission from another account" do
      foreign = create(:ai_mission)
      loop_record.mission_id = foreign.id
      expect(loop_record).not_to be_valid
      expect(loop_record.errors[:mission]).to be_present
    end
  end
end
