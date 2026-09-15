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

    # IMP-c7a173fd2198: the lease, the progress ledger and the rebase advisories were
    # changed with no check at all, so only the MCP door's own permission stood in front
    # of them and any other caller of the service reached them unchecked.
    it "claim refuses a reader and a manager of another account, leaving the lease free" do
      campaign = owner_driver.start(name: "Lease")[:campaign]
      [reader, foreign_manager].each do |actor|
        expect { driver_for(actor).claim(campaign, holder: "x") }.to raise_error(StandardError, refusal)
      end
      expect(campaign.reload.driver_lease_holder).to be_nil

      expect(owner_driver.claim(campaign, holder: "owner-sess")[:ok]).to be(true)
    end

    it "release refuses a reader and a manager of another account, leaving the lease held" do
      campaign = owner_driver.start(name: "Held")[:campaign]
      owner_driver.claim(campaign, holder: "owner-sess")
      [reader, foreign_manager].each do |actor|
        expect { driver_for(actor).release(campaign, holder: "owner-sess") }.to raise_error(StandardError, refusal)
      end
      expect(campaign.reload.driver_lease_holder).to eq("owner-sess")

      expect(owner_driver.release(campaign, holder: "owner-sess")).to eq({ ok: true })
    end

    it "record_increment! refuses a reader and a manager of another account, writing nothing to the ledger" do
      campaign = owner_driver.start(name: "Ledger")[:campaign]
      [reader, foreign_manager].each do |actor|
        expect { driver_for(actor).record_increment!(campaign, title: "forged", task_key: "forged") }
          .to raise_error(StandardError, refusal)
      end
      expect(campaign.ralph_loops.first.ralph_tasks.where(task_key: "forged")).to be_empty
      expect(campaign.campaign_decisions.count).to eq(0)

      owner_driver.record_increment!(campaign, title: "real", task_key: "real")
      expect(campaign.ralph_loops.first.ralph_tasks.where(task_key: "real")).to exist
    end

    it "notify_rebase_advisories refuses a reader and a manager of another account before advising anyone" do
      expect(Ai::Land::RebaseAdvisor).not_to receive(:new)
      [reader, foreign_manager].each do |actor|
        expect { driver_for(actor).notify_rebase_advisories(target_branch: "develop") }
          .to raise_error(StandardError, refusal)
      end
    end

    it "claim, release, record_increment! and notify_rebase_advisories refuse a caller with no user and no principal" do
      campaign = owner_driver.start(name: "Nobody")[:campaign]
      nobody = Ai::DevLoop::CampaignDriver.new(account: account)
      no_principal = /no user must name its principal/

      expect { nobody.claim(campaign, holder: "x") }.to raise_error(Ai::Campaigns::Authorization::Refused, no_principal)
      expect { nobody.release(campaign, holder: "x") }.to raise_error(Ai::Campaigns::Authorization::Refused, no_principal)
      expect { nobody.record_increment!(campaign, title: "t") }.to raise_error(Ai::Campaigns::Authorization::Refused, no_principal)
      expect { nobody.notify_rebase_advisories }.to raise_error(Ai::Campaigns::Authorization::Refused, no_principal)
      expect(campaign.reload.driver_lease_holder).to be_nil
    end

    # IMP-a658fc220367: a call with no user used to pass unchecked, trusting that its door
    # had bound the account. It must now name its principal, and the check asserts it.
    describe "a caller with no user" do
      let(:agent) { create(:ai_agent, account: account) }
      let(:foreign_agent) { create(:ai_agent, account: create(:account)) }

      it "is refused when it names no principal, leaving the campaign active" do
        campaign = owner_driver.start(name: "Unnamed")[:campaign]

        expect { Ai::DevLoop::CampaignDriver.new(account: account, user: nil).stop(campaign) }
          .to raise_error(Ai::Campaigns::Authorization::Refused, /no user must name its principal/)
        expect(campaign.reload.status).to eq("active")
      end

      it "is let through as an agent principal bound to the account touched" do
        campaign = owner_driver.start(name: "Agent-stopped")[:campaign]

        Ai::DevLoop::CampaignDriver.new(account: account, principal: agent).stop(campaign)
        expect(campaign.reload.status).to eq("completed")
      end

      it "is refused as an agent principal from another account, leaving the campaign active" do
        campaign = owner_driver.start(name: "Foreign agent")[:campaign]

        expect { Ai::DevLoop::CampaignDriver.new(account: account, principal: foreign_agent).stop(campaign) }
          .to raise_error(Ai::Campaigns::Authorization::Refused, /not bound to account #{account.id}/)
        expect(campaign.reload.status).to eq("active")
      end

      it "is let through as a declared system principal, and refused as an undeclared one" do
        expect(Ai::CampaignProposal.propose!(account: account, title: "t", objective: "o",
                                             principal: Ai::Campaigns::Authorization::DISCOVERY)).to be_persisted

        forged = Ai::Campaigns::Authorization::SystemPrincipal.new(name: "forged")
        expect { Ai::CampaignProposal.propose!(account: account, title: "t2", objective: "o2", principal: forged) }
          .to raise_error(Ai::Campaigns::Authorization::Refused)
        expect(account.ai_campaign_proposals.count).to eq(1)
      end

      it "refuses a system principal rebuilt with a declared name: only the declared object counts" do
        rebuilt = Ai::Campaigns::Authorization::SystemPrincipal.new(name: Ai::Campaigns::Authorization::DISCOVERY.name)

        expect { Ai::CampaignProposal.propose!(account: account, title: "t", objective: "o", principal: rebuilt) }
          .to raise_error(Ai::Campaigns::Authorization::Refused)
        expect(account.ai_campaign_proposals.count).to eq(0)
      end

      it "lets the declared in-process principal through" do
        campaign = owner_driver.start(name: "Internal-stopped")[:campaign]

        Ai::DevLoop::CampaignDriver.new(account: account, principal: Ai::Campaigns::Authorization::INTERNAL).stop(campaign)
        expect(campaign.reload.status).to eq("completed")
      end

      # A user or a campaign record also carries account_id, but is not a principal: a user
      # passed that way would skip its own permission check, and a record of the account
      # touched matches by construction.
      it "refuses a user, a campaign or a proposal passed as the principal" do
        campaign = owner_driver.start(name: "Not a principal")[:campaign]
        proposal = create(:ai_campaign_proposal, account: account)

        [reader, campaign, proposal].each do |not_a_principal|
          expect { Ai::DevLoop::CampaignDriver.new(account: account, principal: not_a_principal).stop(campaign) }
            .to raise_error(Ai::Campaigns::Authorization::Refused, /not a campaign principal/)
        end
        expect(campaign.reload.status).to eq("active")
      end

      it "still asks a named user for the permission even when a valid principal rides along" do
        campaign = owner_driver.start(name: "User wins")[:campaign]

        expect { Ai::DevLoop::CampaignDriver.new(account: account, user: reader, principal: agent).stop(campaign) }
          .to raise_error(Ai::Campaigns::Authorization::Refused, refusal)
        expect(campaign.reload.status).to eq("active")
      end
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
