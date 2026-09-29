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

  def check(commit_sha = sha)
    described_class.call(account: account, loop_record: ralph_loop, commit_sha: commit_sha)
  end

  def merge_audit(account:, action: "dev_merge.succeeded", **outcome)
    create(:audit_log, account: account, action: action, resource_type: "Ai::DeferredOperation",
                       metadata: { "outcome" => outcome })
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

  it "is landed when a dev_merge.succeeded row names the sha as merged_sha" do
    merge_audit(account: account, merged_sha: sha)

    expect(client).not_to receive(:list_commits)
    expect(check).to have_attributes(landed: true, via: "dev_merge_audit", warning: nil)
  end

  it "is landed when a dev_merge.succeeded row names the sha as pointer_commit_sha" do
    merge_audit(account: account, merged_sha: "b" * 40, pointer_commit_sha: sha)

    expect(check).to have_attributes(landed: true, via: "dev_merge_audit")
  end

  it "matches an abbreviated sha against the audit row" do
    merge_audit(account: account, merged_sha: sha)

    expect(check(sha[0, 9])).to have_attributes(landed: true, via: "dev_merge_audit")
  end

  it "ignores a failed merge row and another account's succeeded row" do
    merge_audit(account: account, action: "dev_merge.failed", merged_sha: sha)
    merge_audit(account: create(:account), merged_sha: sha)
    allow(client).to receive(:list_commits).and_return([])

    expect(check.landed).to be false
  end

  it "is landed when the sha is reachable from develop on the git host" do
    allow(client).to receive(:list_commits).and_return(commits("c" * 40, sha))

    expect(client).to receive(:list_commits).with("owner", "platform", hash_including(sha: "develop", page: 1))
    expect(check).to have_attributes(landed: true, via: "git_host", warning: nil)
  end

  it "walks further pages until the sha is found" do
    page1 = commits(*Array.new(described_class::PAGE_SIZE) { |i| i.to_s(16).rjust(40, "0") })
    allow(client).to receive(:list_commits).with(anything, anything, hash_including(page: 1)).and_return(page1)
    allow(client).to receive(:list_commits).with(anything, anything, hash_including(page: 2)).and_return(commits(sha))

    expect(check).to have_attributes(landed: true, via: "git_host")
  end

  it "bounds the walk and reports unlanded with a warning naming the branch" do
    full = commits(*Array.new(described_class::PAGE_SIZE) { |i| i.to_s(16).rjust(40, "1") })
    allow(client).to receive(:list_commits).and_return(full)

    result = check

    expect(result.landed).to be false
    expect(result.warning).to match(/not reachable from develop/)
    expect(client).to have_received(:list_commits).exactly(described_class::MAX_PAGES).times
  end

  it "reports unlanded, never raising, when the git host errors" do
    allow(client).to receive(:list_commits).and_raise(Devops::Git::ApiClient::ApiError, "boom")

    result = check

    expect(result.landed).to be false
    expect(result.warning).to match(/could not be verified/)
  end

  it "reports unlanded when the loop has no repository in the account" do
    other = create(:ai_ralph_loop, account: account, repository_url: "https://git.example.test/nobody/nothing.git")

    result = described_class.call(account: account, loop_record: other, commit_sha: sha)

    expect(result.landed).to be false
    expect(result.warning).to match(/no git repository/)
  end

  it "rejects a non-hex value without touching the host" do
    expect(client).not_to receive(:list_commits)

    expect(check("not-a-sha").landed).to be false
  end
end
