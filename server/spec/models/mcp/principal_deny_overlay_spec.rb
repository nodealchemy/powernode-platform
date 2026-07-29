# frozen_string_literal: true

require "rails_helper"

# For an INSTANCE principal the grant glob is currently the ONLY control on a
# destructive tool. Verified 2026-07-29, both layers below it are bypassed:
#
#   * ai/tools/mcp_platform_tool_registrar.rb — `return if instance_authorized`
#     skips BOTH `user.has_permission?(required)` and the MCP-token permission
#     intersection.
#   * system_fleet_tool.rb#action_permitted? — `return true if @user.nil?`,
#     commented "internal/system bypass". Its assumption that "MCP-invoked
#     callers always carry @user" predates instance principals and is false for
#     them, so ACTION_PERMISSIONS["system_destroy_instance"] =>
#     "system.instances.control" is never consulted.
#
# So one over-broad pattern — `platform.system_*`, or a careless `platform.*` —
# yields an unattributed, unapproved, unaudited destroy. These specs pin a
# static deny overlay that no grant can override, restoring defence in depth.
RSpec.describe Mcp::Principal, "destructive-tool deny overlay" do
  let(:account)  { create(:account) }
  let(:instance) { double("NodeInstance", id: SecureRandom.uuid, account: account) }

  # The worst case the overlay exists for: a maximally permissive grant.
  def principal_granted(*patterns)
    described_class.tool_grant_resolver = ->(_i) { patterns }
    described_class.new(kind: :instance, account: account, node_instance: instance,
                        subject_id: instance.id)
  end

  after { described_class.reset! }

  DESTRUCTIVE = %w[
    platform.system_destroy_instance
    platform.system_terminate_instance
    platform.system_delete_node
    platform.system_delete_module
    platform.docker_delete_container
    platform.kubernetes_decommission_cluster
    platform.system_drain_instance
    platform.emergency_halt
    platform.delete_agent
    platform.system_rotate_vault_transit_pepper
    platform.system_sdwan_revoke_access_grant
  ].freeze

  SAFE = %w[
    platform.code_blast_radius
    platform.search_knowledge
    platform.dev_next_task
    platform.dispatch_gitea_workflow
    platform.system_list_instances
    platform.system_get_module
    platform.create_learning
    platform.get_skill
    platform.list_skills
    platform.skill_health
  ].freeze

  context "with a wildcard grant covering everything" do
    subject(:principal) { principal_granted("platform.*") }

    it "denies every destructive tool despite the grant matching" do
      DESTRUCTIVE.each do |tool|
        expect(principal.may_invoke?(tool)).to be(false), "expected #{tool} to be denied"
      end
    end

    it "still allows non-destructive tools" do
      SAFE.each do |tool|
        expect(principal.may_invoke?(tool)).to be(true), "expected #{tool} to be allowed"
      end
    end
  end

  # The realistic near-miss: someone grants a whole family to make fleet work
  # convenient and sweeps destroy/terminate in with it.
  it "denies destructive tools under a plausible over-broad family grant" do
    principal = principal_granted("platform.system_*")

    expect(principal.may_invoke?("platform.system_destroy_instance")).to be(false)
    expect(principal.may_invoke?("platform.system_terminate_instance")).to be(false)
    expect(principal.may_invoke?("platform.system_list_instances")).to be(true)
  end

  # An explicit literal grant is the strongest possible statement of intent —
  # and must still lose. Otherwise the overlay is advisory, not a control.
  it "denies a destructive tool even when granted by exact name" do
    principal = principal_granted("platform.system_destroy_instance")

    expect(principal.may_invoke?("platform.system_destroy_instance")).to be(false)
  end

  # Users are human-attributable and flow through has_permission? plus the
  # token intersection plus approval chains. The overlay must not touch them,
  # or it would break every operator action.
  it "does not restrict user principals" do
    user = create(:user, account: account)
    principal = described_class.for_user(user)

    DESTRUCTIVE.each do |tool|
      expect(principal.may_invoke?(tool)).to be(true), "expected user to retain #{tool}"
    end
  end

  it "filters destructive tools out of an advertised catalogue" do
    principal = principal_granted("platform.*")
    listed = principal.filter_tools(
      (DESTRUCTIVE + SAFE).map { |n| { "name" => n } }
    ).map { |t| t["name"] }

    expect(listed).to match_array(SAFE)
    expect(listed).not_to include(*DESTRUCTIVE)
  end

  # Matching must not depend on the caller stripping the prefix.
  it "denies with or without the platform. prefix" do
    principal = principal_granted("platform.*", "*")

    expect(principal.may_invoke?("system_destroy_instance")).to be(false)
    expect(principal.may_invoke?("platform.system_destroy_instance")).to be(false)
  end

  it "is case-insensitive to avoid a trivial bypass" do
    principal = principal_granted("platform.*")

    expect(principal.may_invoke?("platform.System_Destroy_Instance")).to be(false)
  end
end
