# frozen_string_literal: true

require "rails_helper"
require "tmpdir"
require "open3"

# Exercises Ai::Land::RebaseAdvisor against a REAL git repo: detects when the target
# branch (develop) has advanced past an open campaign's branch and advises the driver
# (notify + persist advisory + activity-feed decision), deduped per target tip.
RSpec.describe Ai::Land::RebaseAdvisor, type: :integration do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:campaign) { create(:ai_campaign, account: account, created_by: user) }
  let(:branch) { "campaign/#{campaign.id}" }
  let!(:loop_record) { create(:ai_ralph_loop, account: account, campaign: campaign, branch: branch) }

  attr_reader :work

  def git!(*args)
    out, err, st = Open3.capture3("git", *args, chdir: work)
    raise "git #{args.join(' ')} failed: #{err}" unless st.success?

    out.strip
  end

  def write(file, content)
    File.write(File.join(work, file), content)
  end

  around do |example|
    Dir.mktmpdir do |root|
      @work = File.join(root, "work")
      Open3.capture3("git", "-c", "init.defaultBranch=develop", "init", @work)
      git!("config", "user.email", "test@example.com")
      git!("config", "user.name", "Test")
      write("base.txt", "base\n"); git!("add", "."); git!("commit", "-m", "init")
      git!("checkout", "-b", branch)
      write("feature.txt", "feature\n"); git!("add", "."); git!("commit", "-m", "feature")
      git!("checkout", "develop")
      example.run
    end
  end

  subject(:advisor) { described_class.new(account: account, repository_path: work) }

  describe "#stale_advisories" do
    it "returns nothing when the branch already contains develop's tip" do
      expect(advisor.stale_advisories).to be_empty
    end

    it "flags a campaign behind develop, with commit count + likely-conflict files" do
      write("base.txt", "develop change\n"); git!("add", "."); git!("commit", "-m", "dev1")
      write("feature.txt", "develop touched feature too\n"); git!("add", "."); git!("commit", "-m", "dev2")

      advs = advisor.stale_advisories
      expect(advs.size).to eq(1)
      adv = advs.first
      expect(adv.campaign).to eq(campaign)
      expect(adv.commits_behind).to eq(2)
      expect(adv.likely_conflicts).to include("feature.txt")
    end

    it "skips an excluded campaign" do
      write("base.txt", "x\n"); git!("add", "."); git!("commit", "-m", "dev")
      expect(advisor.stale_advisories(exclude: campaign)).to be_empty
    end
  end

  describe "#notify_stale!" do
    before do
      write("base.txt", "moved\n"); git!("add", "."); git!("commit", "-m", "dev advance")
    end

    it "notifies the driver, persists the advisory, logs a decision, and dedups by target SHA" do
      acted = nil
      expect { acted = advisor.notify_stale! }.to change {
        Notification.where(user: user).where("title LIKE ?", "Rebase needed%").count
      }.by(1)
      expect(acted.size).to eq(1)

      campaign.reload
      expect(campaign.configuration.dig("rebase_advisory", "commits_behind")).to eq(1)
      expect(campaign.configuration.dig("rebase_advisory", "target_sha")).to be_present
      expect(campaign.campaign_decisions.where(decision_type: "other")
                     .where("title LIKE ?", "Rebase needed%")).to exist

      # A second check for the SAME develop tip must not re-notify.
      expect { expect(advisor.notify_stale!).to be_empty }.not_to change(Notification, :count)
    end
  end
end
