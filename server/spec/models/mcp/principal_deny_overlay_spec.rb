# frozen_string_literal: true

require "rails_helper"

# For an INSTANCE principal the grant glob is currently the ONLY control on a
# destructive tool. Verified 2026-07-29, the layers below it are bypassed:
#
#   * ai/tools/mcp_platform_tool_registrar.rb — `return if instance_authorized`
#     skips `user.has_permission?(required)`. (This bullet used to name a
#     second thing skipped, an "MCP-token permission intersection". No such
#     control existed — the branch read a `token:` kwarg no caller passed, and
#     was deleted in IMP-a18f5a8ed393.)
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
  #
  # system_replace_instance (IMP-4d6423bf4eb3, operator ruling R5 of
  # 2026-09-03): the additive half of a DR replace. Alone it terminates
  # nothing — it claims a warm pool member and moves volumes, SDWAN
  # membership and VIPs onto it — which is why it was left out of the overlay
  # when the pair shipped, with `reap: true` (the terminate it can raise)
  # refused for an instance principal in the tool's gate context instead. The
  # ruling closes that asymmetry at the overlay too: an instance principal
  # driving a replace consumes a pool member, re-homes another instance's
  # workload and can retire the failed one as a follow-on, all of it
  # human-unattributable, so the whole verb is denied the same way its
  # destructive half is, and the gate-context refusal becomes defence in
  # depth rather than the only principal-based brake. It was never the only
  # brake outright: the reap arm is gated on system.instance_reap, declared
  # require_approval, so the terminate parked for an operator anyway — but
  # that is an operator-tunable policy, not a bound on who may ask, which is
  # what an overlay pattern is for. Collateral checked below against the
  # whole registry: the pattern matches exactly this one action.
  #
  # dev_merge_increment (IMP-e82f619dde7a): lands a reviewed increment on
  # develop, release/* or master and pushes it to every configured remote. An
  # instance that could invoke it could land code on the platform's own
  # branches, so the anchored *dev_merge* pattern denies it whatever the grant.
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
    platform.system_replace_instance
    platform.system_sdwan_rotate_peer_key
    platform.dev_merge_increment
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
    #
    # 19 since IMP-4d6423bf4eb3 added *replace_instance* (ruling R5): the
    # additive half of a DR replace is denied to instance principals alongside
    # the reap it can raise. Collateral pinned below — one action, no others.
    #
    # 22 since the E2 review (M2) added three LITERAL names —
    # remove_team_member, detach_skill_from_agent, data_source_unsubscribe —
    # each of which destroys rows and had been publishing destructiveHint:
    # false. Collateral pinned below: exactly those three registry keys.
    #
    # 24 since archive_by_predicate and retire_by_predicate (IMP-3c9a6dc8f0a9)
    # were declared destructive with no overlay entry: bulk verbs over up to
    # a whole account's knowledge or learnings in one call. LITERAL, like the
    # three above. Collateral pinned below: exactly those two registry keys.
    #
    # 25 since IMP-9ce0ed39c557 added *system_out_of_band_exec* — the
    # governed out-of-band SSH exec verb (System::Executors::OutOfBandExec,
    # gated under system.instance.out_of_band_exec). Out-of-band root command
    # execution on a fleet node must never be self-grantable by an instance
    # principal — the same reasoning *replace_instance* and *reap_* already
    # apply to other node-lifecycle primitives, just for arbitrary code
    # execution instead. Collateral pinned below: exactly one registry key.
    # 26 since IMP-88e82d59b7f2 added *system_restart_unit* — the governed
    # unit-restart verb (gated under system.task.restart), a disruptive
    # lifecycle act in the class of *_stop_instance / *_reboot_instance that an
    # instance principal must never aim at a peer. Collateral pinned below:
    # exactly one registry key.
    # 27 since IMP-9951cbf20bb0 added *unit_dropin* — the governed runtime
    # systemd drop-in verb, which rewrites how a unit runs as root on a node
    # (capabilities, writable paths, limits) and so must never be aimed at a
    # peer by an instance principal. Collateral pinned below: exactly one
    # registry key.
    # 28 since IMP-2e7816b5ee95 added *system_sdwan_rotate_peer_key* — the
    # governed in-place WireGuard key rotation (gated under
    # sdwan.peer_key_rotate). The broad *rotate* pattern already matches it
    # today; the anchored entry is there so the verb stays denied if *rotate*
    # is ever narrowed, the same belt-and-braces *system_restart_unit* takes
    # for a verb an instance must never aim at a peer. Collateral pinned
    # below: exactly one registry key.
    # 29 since IMP-e82f619dde7a added *dev_merge* — the governed merge of a
    # reviewed increment onto develop / release/* / master, pushed to every
    # configured remote (gated under dev.merge). An mTLS node cert that could
    # invoke it could land code on the platform's own branches. No broader
    # pattern matches it. Collateral pinned below: exactly one registry key.
    # 30 since IMP-a41ceb3cdd64 added *system_clear_ssh_host_key* — the governed,
    # human-only clear of a node's recorded SSH host key (gated under
    # system.instance.ssh_host_key_clear). Clearing re-opens the window in which a
    # node's next reported key is trusted, so an instance principal must never aim
    # it at a peer. Collateral pinned below: exactly one registry key.
    it "matches the known, intentional pattern count exactly" do
      expect(patterns.size).to eq(30)
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

    # Same mechanical collateral check for *replace_instance* (IMP-4d6423bf4eb3).
    # The pattern is deliberately narrower than a `*replace*` — which would
    # sweep in any future replace-shaped read or config verb — and is pinned
    # here to the single DR action it exists for.
    it "denies exactly system_replace_instance with the *replace_instance* pattern" do
      expect(patterns).to include("*replace_instance*")

      denied = ::Ai::Tools::PlatformApiToolRegistry.all_tools.keys.select do |name|
        ::File.fnmatch("*replace_instance*", name, ::File::FNM_EXTGLOB)
      end

      expect(denied).to eq(%w[system_replace_instance])
    end

    # A literal matches only itself, so the real assertion here is the other
    # direction: each literal NAMES A REGISTERED KEY. A typo'd or renamed
    # literal would deny nothing at all while reading as a control.
    it "denies exactly the three E2-review literals, each a real registry key" do
      literals = %w[remove_team_member detach_skill_from_agent data_source_unsubscribe]
      expect(patterns).to include(*literals)

      denied = ::Ai::Tools::PlatformApiToolRegistry.all_tools.keys.select do |name|
        literals.any? { |pattern| ::File.fnmatch(pattern, name, ::File::FNM_EXTGLOB) }
      end

      expect(denied.sort).to eq(literals.sort)
    end

    it "denies exactly the two bulk predicate literals, each a real registry key" do
      literals = %w[archive_by_predicate retire_by_predicate]
      expect(patterns).to include(*literals)

      denied = ::Ai::Tools::PlatformApiToolRegistry.all_tools.keys.select do |name|
        literals.any? { |pattern| ::File.fnmatch(pattern, name, ::File::FNM_EXTGLOB) }
      end

      expect(denied.sort).to eq(literals.sort)
    end

    # Same mechanical collateral check as *replace_instance* above. Substring-
    # anchored (not bare-word) because the verb name itself is long and
    # specific enough that nothing else in the registry could contain it —
    # pinned here rather than asserted from prose.
    it "denies exactly system_out_of_band_exec with the *system_out_of_band_exec* pattern" do
      expect(patterns).to include("*system_out_of_band_exec*")

      denied = ::Ai::Tools::PlatformApiToolRegistry.all_tools.keys.select do |name|
        ::File.fnmatch("*system_out_of_band_exec*", name, ::File::FNM_EXTGLOB)
      end

      expect(denied).to eq(%w[system_out_of_band_exec])
    end

    it "denies exactly system_restart_unit with the *system_restart_unit* pattern" do
      expect(patterns).to include("*system_restart_unit*")

      denied = ::Ai::Tools::PlatformApiToolRegistry.all_tools.keys.select do |name|
        ::File.fnmatch("*system_restart_unit*", name, ::File::FNM_EXTGLOB)
      end

      expect(denied).to eq(%w[system_restart_unit])
    end

    it "denies exactly system_sdwan_rotate_peer_key with the *system_sdwan_rotate_peer_key* pattern" do
      expect(patterns).to include("*system_sdwan_rotate_peer_key*")

      denied = ::Ai::Tools::PlatformApiToolRegistry.all_tools.keys.select do |name|
        ::File.fnmatch("*system_sdwan_rotate_peer_key*", name, ::File::FNM_EXTGLOB)
      end

      expect(denied).to eq(%w[system_sdwan_rotate_peer_key])
    end

    it "denies exactly dev_merge_increment with the *dev_merge* pattern" do
      expect(patterns).to include("*dev_merge*")

      denied = ::Ai::Tools::PlatformApiToolRegistry.all_tools.keys.select do |name|
        ::File.fnmatch("*dev_merge*", name, ::File::FNM_EXTGLOB)
      end

      expect(denied).to eq(%w[dev_merge_increment])
    end

    it "denies exactly system_apply_unit_dropin with the *unit_dropin* pattern" do
      expect(patterns).to include("*unit_dropin*")

      denied = ::Ai::Tools::PlatformApiToolRegistry.all_tools.keys.select do |name|
        ::File.fnmatch("*unit_dropin*", name, ::File::FNM_EXTGLOB)
      end

      expect(denied).to eq(%w[system_apply_unit_dropin])
    end

    it "denies exactly system_clear_ssh_host_key with the *system_clear_ssh_host_key* pattern" do
      expect(patterns).to include("*system_clear_ssh_host_key*")

      denied = ::Ai::Tools::PlatformApiToolRegistry.all_tools.keys.select do |name|
        ::File.fnmatch("*system_clear_ssh_host_key*", name, ::File::FNM_EXTGLOB)
      end

      expect(denied).to eq(%w[system_clear_ssh_host_key])
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

  # Users are human-attributable and flow through has_permission? plus approval
  # chains. The overlay must not touch them, or it would break every operator
  # action. (There is no token-level narrowing for a user either.)
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
