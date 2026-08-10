# frozen_string_literal: true

require "rails_helper"

# IMP-5df6d59aaa5c — the MCP surface over GitRunner inventory. list is
# read-shaped (class REQUIRED_PERMISSION git.runners.read); prune is
# destructive and additionally requires git.runners.manage IN the call for
# the apply path, failing closed for a nil-user non-internal caller
# (instance principals must never prune).
RSpec.describe Ai::Tools::GitRunnerInventoryTool do
  include PermissionTestHelpers # role-backed permission grants (included by type only for request/controller/model)

  let(:account) { create(:account) }
  let(:manager) { user_with_permissions("git.runners.read", "git.runners.manage", account: account) }
  let(:reader)  { user_with_permissions("git.runners.read", account: account) }

  def tool(user: manager, internal: false)
    described_class.new(account: account, user: user, internal: internal)
  end

  def fleet_runner(name_suffix)
    create(:git_runner, account: account, name: "fleet-#{name_suffix}", status: "offline")
  end

  describe "list_git_runners" do
    it "lists the account's runners with status counts" do
      fleet_runner("a")
      create(:git_runner, :online, account: account, name: "runner1")
      create(:git_runner, name: "fleet-foreign", status: "offline") # other account

      result = tool.execute(params: { action: "list_git_runners" })

      expect(result[:success]).to be(true)
      expect(result.dig(:data, :runners).size).to eq(2)
      expect(result.dig(:data, :stats)).to include(total: 2, online: 1, offline: 1)
    end
  end

  describe "prune_stale_git_runners" do
    it "dry-runs by default: states the count and a sample, deletes nothing" do
      4.times { |i| fleet_runner("s#{i}") }

      result = tool.execute(params: { action: "prune_stale_git_runners" })

      expect(result[:success]).to be(true)
      expect(result.dig(:data, :dry_run)).to be(true)
      expect(result.dig(:data, :candidate_count)).to eq(4)
      expect(result.dig(:data, :sample)).to be_an(Array)
      expect(Devops::GitRunner.count).to eq(4)
    end

    it "applies only with apply: true and the manage permission" do
      fleet_runner("doomed")

      result = tool.execute(params: { action: "prune_stale_git_runners", apply: true })

      expect(result[:success]).to be(true)
      expect(result.dig(:data, :dry_run)).to be(false)
      expect(result.dig(:data, :deleted_count)).to eq(1)
      expect(Devops::GitRunner.count).to eq(0)
    end

    it "refuses apply for a user without git.runners.manage" do
      fleet_runner("safe")

      result = tool(user: reader).execute(params: { action: "prune_stale_git_runners", apply: true })

      expect(result[:success]).to be(false)
      expect(result[:error]).to match(/git\.runners\.manage/)
      expect(Devops::GitRunner.count).to eq(1)
    end

    it "fails closed on apply for a nil-user, non-internal caller (instance principal shape)" do
      fleet_runner("safe")

      result = tool(user: nil).execute(params: { action: "prune_stale_git_runners", apply: true })

      expect(result[:success]).to be(false)
      expect(Devops::GitRunner.count).to eq(1)
    end

    it "allows apply for an explicit internal caller" do
      fleet_runner("doomed")

      result = tool(user: nil, internal: true).execute(params: { action: "prune_stale_git_runners", apply: true })

      expect(result[:success]).to be(true)
      expect(Devops::GitRunner.count).to eq(0)
    end
  end

  describe "registry + advertisement wiring" do
    it "routes both actions through the registry allowlist" do
      expect(Ai::Tools::PlatformApiToolRegistry.all_tools["list_git_runners"]).to eq("Ai::Tools::GitRunnerInventoryTool")
      expect(Ai::Tools::PlatformApiToolRegistry.all_tools["prune_stale_git_runners"]).to eq("Ai::Tools::GitRunnerInventoryTool")
    end
  end

  describe "instance-principal destructive overlay" do
    it "classifies the prune action as destroy-shaped (deny overlay applies)" do
      expect(Mcp::Principal.destructive_tool?("prune_stale_git_runners")).to be(true)
    end
  end
end
