# frozen_string_literal: true

require "rails_helper"
require "tmpdir"
require "open3"

# Integration: exercises Ai::Land::LandService against a REAL git repo + bare
# remote (the unit specs stub git). Proves stage! pushes + records SHAs, merge!
# actually merges the campaign branch into develop, rollback! reverts it, and a
# conflicting branch parks instead of merging.
RSpec.describe "Campaign auto-land (real git)", type: :integration do
  let(:account) { create(:account) }
  let(:campaign) { create(:ai_campaign, account: account) }
  let(:source_branch) { "campaign/#{campaign.id}" }

  attr_reader :work

  def git!(*args, dir: work)
    out, err, st = Open3.capture3("git", *args, chdir: dir)
    raise "git #{args.join(' ')} failed: #{err}" unless st.success?

    out.strip
  end

  def write(file, content)
    File.write(File.join(work, file), content)
  end

  def land_for(target: "develop")
    Ai::CampaignLand.create!(
      campaign: campaign, account: account, status: "staging",
      source_branch: source_branch, target_branch: target
    )
  end

  around do |example|
    Dir.mktmpdir do |root|
      remote = File.join(root, "remote.git")
      @work = File.join(root, "work")
      Open3.capture3("git", "-c", "init.defaultBranch=develop", "init", "--bare", remote)
      Open3.capture3("git", "clone", remote, @work)
      git!("config", "user.email", "test@example.com")
      git!("config", "user.name", "Test")
      git!("checkout", "-b", "develop")
      write("base.txt", "base\n")
      git!("add", "."); git!("commit", "-m", "init")
      git!("push", "-u", "origin", "develop")
      example.run
    end
  end

  def make_campaign_branch(file: "feature.txt", content: "feature\n")
    git!("checkout", "-b", source_branch, "develop")
    write(file, content)
    git!("add", "."); git!("commit", "-m", "feature commit")
    git!("checkout", "develop")
  end

  let(:service) { Ai::Land::LandService.new(land, repository_path: work) }

  describe "happy path" do
    let(:land) { land_for }
    before { make_campaign_branch }

    it "stages, merges into develop, and can roll back" do
      service.stage!
      land.reload
      expect(land.status).to eq("staged_ci")
      expect(land.base_sha).to be_present
      expect(land.staged_sha).to be_present
      # source branch was pushed to origin
      expect(git!("ls-remote", "--heads", "origin", source_branch)).to include(source_branch)

      service.merge!
      land.reload
      expect(land.status).to eq("verifying")
      expect(land.merged_sha).to be_present
      # develop now contains the feature file
      git!("checkout", "develop"); git!("reset", "--hard", "origin/develop") rescue nil
      expect(File.exist?(File.join(work, "feature.txt"))).to be(true)

      service.rollback!
      expect(land.reload.status).to eq("rolled_back")
      # the revert removed the feature file again on develop
      git!("checkout", "develop"); git!("reset", "--hard", "origin/develop")
      expect(File.exist?(File.join(work, "feature.txt"))).to be(false)
    end
  end

  describe "conflict" do
    let(:land) { land_for }

    it "parks instead of merging when the branch conflicts with develop" do
      # campaign edits base.txt one way...
      make_campaign_branch(file: "base.txt", content: "campaign-change\n")
      # ...develop edits the same file another way (diverged)
      write("base.txt", "develop-change\n")
      git!("add", "."); git!("commit", "-m", "develop diverges")
      git!("push", "origin", "develop")

      service.stage!
      service.merge!

      expect(land.reload.status).to eq("parked")
      expect(campaign.parked_questions.count).to be >= 1
    end
  end
end
