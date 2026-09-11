# frozen_string_literal: true

require "rails_helper"

# The shared campaign authorization, asserted at the SERVICES every door calls. The
# review finding: an account-switch session's permission, delegated from ANOTHER
# account, acted on the user's OWN account's campaigns. The doors' own 403 is pinned
# in the request specs; these examples see only the service check, because each one
# calls the service directly with no door in front of it.
RSpec.describe "Ai::Campaigns::Authorization" do
  let(:account) { create(:account) }
  let!(:owner) { create(:user, account: account, permissions: %w[ai.campaigns.read ai.campaigns.manage]) }
  let(:reader) { create(:user, account: account, permissions: %w[ai.campaigns.read]) }
  let(:foreign_manager) { create(:user, account: create(:account), permissions: %w[ai.campaigns.read ai.campaigns.manage]) }
  let(:owner_driver) { Ai::DevLoop::CampaignDriver.new(account: account, user: owner) }
  let(:refusal) { /does not hold 'ai\.campaigns\.manage' in account #{account.id}/ }

  def driver_for(actor) = Ai::DevLoop::CampaignDriver.new(account: account, user: actor)

  def completed_campaign
    campaign = owner_driver.start(name: "Completed", stop_conditions: { max_failed: 1 })[:campaign]
    owner_driver.record_increment!(campaign, title: "broken", status: "failed")
    campaign.reload
  end

  describe ".permitted?" do
    it "answers from the user's own roles in the account touched, and never for another account" do
      expect(Ai::Campaigns::Authorization.permitted?(user: owner, account: account)).to be(true)
      expect(Ai::Campaigns::Authorization.permitted?(user: reader, account: account)).to be(false)
      expect(Ai::Campaigns::Authorization.permitted?(user: foreign_manager, account: account)).to be(false)
      expect(Ai::Campaigns::Authorization.permitted?(user: nil, account: account)).to be(false)
    end
  end

  describe "CampaignDriver" do
    it "start refuses a reader and a manager of another account, creating nothing" do
      [reader, foreign_manager].each do |actor|
        expect { driver_for(actor).start(name: "Refused") }.to raise_error(StandardError, refusal)
      end
      expect(account.ai_campaigns.count).to eq(0)

      expect(owner_driver.start(name: "Allowed")[:campaign]).to be_persisted
    end

    it "stop refuses a reader and a manager of another account, leaving the campaign active" do
      campaign = owner_driver.start(name: "Live")[:campaign]
      [reader, foreign_manager].each do |actor|
        expect { driver_for(actor).stop(campaign) }.to raise_error(StandardError, refusal)
      end
      expect(campaign.reload.status).to eq("active")

      owner_driver.stop(campaign)
      expect(campaign.reload.status).to eq("completed")
    end

    it "delegate refuses a reader and a manager of another account, leaving the lease free" do
      campaign = owner_driver.start(name: "Route")[:campaign]
      [reader, foreign_manager].each do |actor|
        expect { driver_for(actor).delegate(campaign, driver_kind: "claude_code", holder: "x") }
          .to raise_error(StandardError, refusal)
      end
      expect(campaign.reload.driver_lease_holder).to be_nil

      owner_driver.delegate(campaign, driver_kind: "claude_code", holder: "owner-sess")
      expect(campaign.reload.driver_lease_holder).to eq("owner-sess")
    end

    it "answer_question refuses a reader and a manager of another account, leaving the question open" do
      campaign = owner_driver.start(name: "Ask")[:campaign]
      question = campaign.park_question!(question: "Pricing?")
      [reader, foreign_manager].each do |actor|
        expect { driver_for(actor).answer_question(campaign, question_id: question.id, answer: "a") }
          .to raise_error(StandardError, refusal)
      end
      expect(question.reload.status).to eq("open")

      owner_driver.answer_question(campaign, question_id: question.id, answer: "owner")
      expect(question.reload.status).to eq("answered")
    end

    it "resume refuses a reader and a manager of another account, leaving the campaign completed" do
      campaign = completed_campaign
      [reader, foreign_manager].each do |actor|
        expect { driver_for(actor).resume(campaign, reason: "x", stop_conditions: { max_failed: 6 }) }
          .to raise_error(StandardError, refusal)
      end
      expect(campaign.reload.status).to eq("completed")

      owner_driver.resume(campaign, reason: "owner", stop_conditions: { max_failed: 6 })
      expect(campaign.reload.status).to eq("active")
    end

    # Documented pass-through: an agent or instance MCP principal arrives with no user,
    # already bound to this account by its own door.
    it "lets a caller with no user through, bound to the driver's account" do
      campaign = owner_driver.start(name: "Agent-stopped")[:campaign]
      Ai::DevLoop::CampaignDriver.new(account: account, user: nil).stop(campaign)
      expect(campaign.reload.status).to eq("completed")
    end
  end

  describe "Ai::CampaignProposal" do
    let(:proposal) { create(:ai_campaign_proposal, account: account, status: "proposed") }

    it "propose! refuses a reader or a manager of another account named as the actor, creating nothing" do
      [reader, foreign_manager].each do |actor|
        expect { Ai::CampaignProposal.propose!(account: account, title: "t", objective: "o", actor: actor) }
          .to raise_error(StandardError, refusal)
      end
      expect(account.ai_campaign_proposals.count).to eq(0)

      expect(Ai::CampaignProposal.propose!(account: account, title: "t", objective: "o", actor: owner)).to be_persisted
    end

    it "queue! refuses a reader or a manager of another account" do
      [reader, foreign_manager].each { |actor| expect { proposal.queue!(actor) }.to raise_error(StandardError, refusal) }
      expect(proposal.reload.status).to eq("proposed")

      proposal.queue!(owner)
      expect(proposal.reload.status).to eq("queued")
    end

    it "approve! refuses a reader or a manager of another account" do
      [reader, foreign_manager].each { |actor| expect { proposal.approve!(actor) }.to raise_error(StandardError, refusal) }
      expect(proposal.reload.status).to eq("proposed")

      proposal.approve!(owner)
      expect(proposal.reload.status).to eq("approved")
    end

    it "reject! refuses a reader or a manager of another account" do
      [reader, foreign_manager].each do |actor|
        expect { proposal.reject!(actor, reason: "no") }.to raise_error(StandardError, refusal)
      end
      expect(proposal.reload.status).to eq("proposed")

      proposal.reject!(owner, reason: "owner")
      expect(proposal.reload.status).to eq("rejected")
    end

    # Secreview LOW: update_fields! changed a proposal with no shared check at all.
    it "update_fields! refuses a reader or a manager of another account named as the actor, changing nothing" do
      original_title = proposal.title
      [reader, foreign_manager].each do |actor|
        expect { proposal.update_fields!(actor: actor, title: "Rewritten") }.to raise_error(StandardError, refusal)
      end
      expect(proposal.reload.title).to eq(original_title)

      proposal.update_fields!(actor: owner, title: "Owner rewrite")
      expect(proposal.reload.title).to eq("Owner rewrite")
    end

    it "SpawnService (through CampaignDriver#start) refuses a reader, spawning nothing" do
      approved = create(:ai_campaign_proposal, :approved, account: account)

      expect { Ai::CampaignProposals::SpawnService.new(account: account, user: reader).spawn!(approved) }
        .to raise_error(StandardError, refusal)
      expect(approved.reload.status).to eq("approved")
      expect(account.ai_campaigns.count).to eq(0)
    end
  end
end
