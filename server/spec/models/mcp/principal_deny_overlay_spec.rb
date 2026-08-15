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

  # NOTE: %w[] does not support inline comments — a line starting with "#"
  # inside the literal becomes literal words in the array, not a comment.
  # This DESTRUCTIVE/SAFE pair are plain test fixtures (not the production
  # deny list), but Mcp::Principal::DESTRUCTIVE_TOOL_PATTERNS had exactly
  # this defect: eval'ing it standalone held 107 entries where 15 were
  # intended, 92 of them stray words from two %w[]-inline annotations (see
  # "structural sanity" below, which now pins bare-pattern-only against the
  # real constant so this cannot silently recur). Per-entry rationale for
  # fixture additions lives up here instead of inline, for the same reason.
  #
  # system_upgrade_boot_image: arms an A/B boot slot the node reboots into,
  # on itself or a peer — at least as consequential as
  # system_reboot_instance, which is already denied. Became MCP-reachable
  # only when the action was added to PlatformApiToolRegistry (previously
  # declared, tested and unroutable).
  #
  # system_instance_hold / system_instance_release_hold (IMP-b2f80e6d1c65):
  # arm/disarm the operator ops hold. Release is the sharper risk
  # (InstanceOpsHoldService#release! does not require a user, unlike
  # #hold!) but both are denied for symmetry — same system.instances.control
  # tier as the *_stop_instance/*_reboot_instance pair above, and permitting
  # an instance to clear a hold a human placed would re-create the
  # unattended-start race the feature exists to prevent. Became
  # MCP-reachable only when these actions were added to
  # PlatformApiToolRegistry (previously declared, tested and unroutable).
  #
  # approve_deferred_operation / reject_deferred_operation and
  # create_/update_intervention_policy (IMP-e8adfcfcab9b): the human approval
  # gate itself. approve_ EXECUTES the operation a human was asked to
  # authorise, so an instance reaching it closes the loop on its own request;
  # reject_ is denied for the same arm/disarm symmetry as the hold pair above.
  # The policy writes are sharper still — an intervention policy decides
  # whether an action needs approval AT ALL, so one
  # create_intervention_policy(scope: "global", policy: "auto_approve") makes
  # every later gate vacuous. delete_intervention_policy was already denied by
  # *delete*; denying the delete while permitting the rewrite was incoherent.
  # These are exactly the actions whose authorization cannot be checked for an
  # instance — no User, so has_permission? has nothing to ask about — which is
  # why AgentAutonomyTool's per-action map waives the check for it and this
  # overlay is the layer that bounds it.
  DESTRUCTIVE = %w[
    platform.approve_deferred_operation
    platform.reject_deferred_operation
    platform.create_intervention_policy
    platform.update_intervention_policy
    platform.delete_intervention_policy
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
    platform.system_upgrade_boot_image
    platform.system_instance_hold
    platform.system_instance_release_hold
  ].freeze

  # system_instance_hold_status / system_module_publish_target /
  # system_module_publication_integrity (IMP-b2f80e6d1c65): read-only, same
  # tier as system_get_module/system_list_instances above; not paired with
  # an arm/disarm of a safety mechanism the way system_instance_hold/
  # release_hold are.
  #
  # list_deferred_operations / list_intervention_policies (IMP-e8adfcfcab9b):
  # the read halves of the two families denied above. Both are PLURAL, which is
  # what keeps them out of the *_deferred_operation and *intervention_policy
  # patterns — asserted here so a later "tidy-up" of those patterns into
  # *deferred_operation*/*intervention_polic* reds instead of silently taking
  # an instance's read surface with it.
  SAFE = %w[
    platform.list_deferred_operations
    platform.list_intervention_policies
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
    platform.system_instance_hold_status
    platform.system_module_publish_target
    platform.system_module_publication_integrity
  ].freeze

  # Structural sanity on the CONSTANT itself, not on behaviour — behaviour
  # specs below pass even with a %w[]-inline-comment defect present (the
  # stray words don't happen to fnmatch any real tool name today), which is
  # exactly why 92 stray entries from two annotations survived undetected
  # until an explicit count. This asserts the shape directly so a future
  # inline "# comment" inside DESTRUCTIVE_TOOL_PATTERNS fails loudly instead
  # of silently padding the array with denied-by-accident literal words.
  describe "DESTRUCTIVE_TOOL_PATTERNS array hygiene" do
    # DESTRUCTIVE_TOOL_PATTERNS is declared inside `class << self`, so it
    # lives on Mcp::Principal's singleton class, not on Mcp::Principal
    # itself — `described_class::DESTRUCTIVE_TOOL_PATTERNS` raises
    # NameError even though the constant is real and `destructive_tool?`
    # (defined in that same singleton-class body) resolves it lexically.
    let(:patterns) { described_class.singleton_class::DESTRUCTIVE_TOOL_PATTERNS }

    it "contains only bare fnmatch patterns — no stray words from an accidental %w[] comment" do
      patterns.each do |pattern|
        expect(pattern).not_to match(/\s/), "#{pattern.inspect} contains whitespace — likely a comment word leaked into the array"
        expect(pattern).not_to eq("#"), "a literal \"#\" entry means a comment line leaked into the array"
      end
    end

    # 16 since fb00c85ed added *prune* alongside the GitRunner prune action
    # (IMP-5df6d59aaa5c). That addition is correct — pruning is destroy-shaped
    # and must be denied to instance principals — but the commit did not update
    # this count, so the guard has been red on develop ever since. That is the
    # guard working: every change to the deny list is meant to be acknowledged
    # HERE, deliberately, rather than slipping in unreviewed. Bump this only
    # after confirming the new pattern belongs.
    #
    # 18 since IMP-e8adfcfcab9b added *_deferred_operation and
    # *intervention_policy — the approval gate itself. Acknowledged here after
    # checking collateral against the whole registry rather than by eye: those
    # two patterns match exactly the five intended actions across all 602
    # registered tool actions, and no others.
    it "matches the known, intentional pattern count exactly" do
      expect(patterns.size).to eq(18)
    end

    # The collateral check itself, kept mechanical: a pattern added later that
    # over-matches would be caught here rather than by reading fnmatch globs.
    it "denies exactly the intended actions across the whole tool registry" do
      newly_denied = ::Ai::Tools::PlatformApiToolRegistry.all_tools.keys.select do |name|
        %w[*_deferred_operation *intervention_policy].any? do |pattern|
          ::File.fnmatch(pattern, name, ::File::FNM_EXTGLOB)
        end
      end

      expect(newly_denied.sort).to eq(%w[
        approve_deferred_operation
        create_intervention_policy
        delete_intervention_policy
        reject_deferred_operation
        update_intervention_policy
      ])
    end
  end

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
