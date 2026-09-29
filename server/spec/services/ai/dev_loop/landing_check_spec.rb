# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::DevLoop::LandingCheck do
  let(:account) { create(:account) }
  let(:repository) { create(:git_repository, account: account, full_name: "owner/platform", owner: "owner", name: "platform") }
  let(:ralph_loop) do
    create(:ai_ralph_loop, account: account, repository_url: "https://git.example.test/owner/platform.git")
  end
  let(:sha) { "a" * 40 }
  let(:client) { instance_double(Devops::Git::GiteaApiClient) }

  before do
    repository
    allow(Devops::Git::ApiClient).to receive(:for).and_return(client)
  end

  def check(commit_sha = sha, loop_record: ralph_loop)
    described_class.call(account: account, loop_record: loop_record, commit_sha: commit_sha)
  end

  # A dev_merge.succeeded row as the internal DevMergesController writes it: the caller's
  # `repository` and `pointer_bump.parent_repository` as typed, the shas under `outcome`.
  def merge_audit(account:, repository: "owner/platform", parent: nil, action: "dev_merge.succeeded", **outcome)
    metadata = { "repository" => repository, "outcome" => outcome }
    metadata["pointer_bump"] = { "parent_repository" => parent, "submodule_path" => "ext/x" } if parent
    create(:audit_log, account: account, action: action, resource_type: "Ai::DeferredOperation", metadata: metadata)
  end

  def commits(*shas)
    shas.map { |s| { "sha" => s } }
  end

  it "reports no-sha as undetermined rather than unlanded" do
    result = check("")

    expect(result.landed).to be_nil
    expect(result.via).to eq("no_commit_sha")
    expect(result.warning).to match(/no commit_sha/)
  end

  describe "the audit row" do
    it "lands the full sha as the merged sha of this loop's repository, by full_name or by id" do
      merge_audit(account: account, merged_sha: sha)
      expect(client).not_to receive(:list_commits)
      expect(check).to have_attributes(landed: true, via: "dev_merge_audit", warning: nil)

      AuditLog.delete_all
      merge_audit(account: account, repository: repository.id, merged_sha: sha)
      expect(check.landed).to be true
    end

    it "lands the full sha as the pointer-bump commit of this loop's repository" do
      merge_audit(account: account, repository: "owner/ext", parent: "owner/platform", merged_sha: "b" * 40, pointer_commit_sha: sha)

      expect(check).to have_attributes(landed: true, via: "dev_merge_audit")
    end

    it "does not count a row for another repository, another account, a failed merge, or the wrong sha column" do
      merge_audit(account: account, repository: "owner/elsewhere", merged_sha: sha)
      merge_audit(account: create(:account), merged_sha: sha)
      merge_audit(account: account, action: "dev_merge.failed", merged_sha: sha)
      # the pointer commit belongs to the PARENT: naming this repository as the merged repository does not count
      merge_audit(account: account, pointer_commit_sha: sha)
      allow(client).to receive(:list_commits).and_return([])

      expect(check.landed).to be false
    end
  end

  describe "an abbreviated sha" do
    it "is never matched by prefix, and is unverified rather than unlanded" do
      merge_audit(account: account, merged_sha: sha)
      expect(client).not_to receive(:list_commits)

      result = check(sha[0, 12])

      expect(result.landed).to eq("unverified")
      expect(result.warning).to match(/abbreviated/)
    end
  end

  describe "the git host" do
    it "lands a sha reachable from develop" do
      expect(client).to receive(:list_commits).with("owner", "platform", hash_including(sha: "develop", page: 1))
                                              .and_return(commits("c" * 40, sha))

      expect(check).to have_attributes(landed: true, via: "git_host", warning: nil)
    end

    it "does not match a commit that merely starts with the sha" do
      allow(client).to receive(:list_commits).and_return(commits("#{sha[0, 12]}#{'0' * 28}"), [])

      expect(check.landed).to be false
    end

    it "walks further pages, and only stops on an empty one (the host may cap the page size)" do
      page1 = commits(*Array.new(3) { |i| i.to_s(16).rjust(40, "0") })
      allow(client).to receive(:list_commits).with(anything, anything, hash_including(page: 1)).and_return(page1)
      allow(client).to receive(:list_commits).with(anything, anything, hash_including(page: 2)).and_return(commits(sha))

      expect(check).to have_attributes(landed: true, via: "git_host")
    end

    it "answers false with a warning naming the branch when the host answered and the sha is not there" do
      allow(client).to receive(:list_commits).and_return(commits("1" * 40), [])

      result = check

      expect(result.landed).to be false
      expect(result.warning).to match(/not reachable from develop/)
    end

    it "bounds the walk in pages and reports the host's answer (false), not unverified" do
      full = commits(*Array.new(described_class::PAGE_SIZE) { |i| i.to_s(16).rjust(40, "1") })
      allow(client).to receive(:list_commits).and_return(full)

      expect(check.landed).to be false
      expect(client).to have_received(:list_commits).exactly(described_class::MAX_PAGES).times
    end

    it "is unverified, never raising, when the host errors" do
      allow(client).to receive(:list_commits).and_raise(Devops::Git::ApiClient::ApiError, "boom")

      result = check

      expect(result.landed).to eq("unverified")
      expect(result.warning).to match(/could not be verified/)
    end

    it "is unverified when the walk exceeds its overall deadline" do
      stub_const("Ai::DevLoop::LandingCheck::HOST_DEADLINE", 0.2)
      allow(client).to receive(:list_commits) { sleep 2 }

      result = check

      expect(result.landed).to eq("unverified")
      expect(result.via).to eq("host_timeout")
    end
  end

  it "is unverified when no repository resolves for the loop (the dev-improve loop has no repository_url)" do
    other = create(:ai_ralph_loop, account: account, repository_url: nil)
    expect(client).not_to receive(:list_commits)

    result = check(loop_record: other)

    expect(result.landed).to eq("unverified")
    expect(result.via).to eq("no_repository")
  end

  it "does not resolve another account's repository" do
    other_account = create(:account)
    other_loop = create(:ai_ralph_loop, account: other_account, repository_url: "https://git.example.test/owner/theirs.git")
    create(:git_repository, account: other_account, full_name: "owner/theirs", owner: "owner", name: "theirs")
    allow(client).to receive(:list_commits).and_return([])

    expect(described_class.call(account: account, loop_record: other_loop, commit_sha: sha).landed).to eq("unverified")
  end

  it "rejects a non-hex value as not landed without touching the host" do
    expect(client).not_to receive(:list_commits)

    expect(check("not-a-sha").landed).to be false
  end
end
