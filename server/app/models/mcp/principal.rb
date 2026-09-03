# frozen_string_literal: true

module Mcp
  # The authenticated principal behind an MCP request — either a platform User
  # (OAuth) or a fleet NodeInstance (mTLS). Unifies the two so the auth concern,
  # session handling, and tool-catalog scoping read ONE interface instead of
  # branching user-vs-instance throughout sensitive auth code.
  #
  # Core must not depend on the system extension, so an instance is resolved via
  # an injectable resolver (set by the extension engine — the same DI seam as
  # Security::MtlsTrust.own_ca_provider). The resolver maps a verified client-cert
  # CN (= NodeInstance.id) to an instance-like object exposing #id, #account, and
  # (optionally) #declared_capabilities.
  class Principal
    class << self
      attr_writer :instance_resolver

      # Lambda(cn) -> instance-like | nil. Defaults to "no instances resolvable"
      # so a stock core install (no extension) simply never authenticates an
      # instance principal — fail-closed.
      def instance_resolver
        @instance_resolver ||= ->(_cn) { nil }
      end

      def reset!
        @instance_resolver = nil
        @tool_grant_resolver = nil
      end

      # Lambda(node_instance) -> Array<String> of allowed tool-name glob patterns
      # (e.g. "platform.system_*_read", "platform.health"). Injected by the
      # extension's instance-grant model. Default: DENY ALL — an instance with no
      # resolver or no grant gets no tools.
      attr_writer :tool_grant_resolver

      def tool_grant_resolver
        @tool_grant_resolver ||= ->(_instance) { [] }
      end

      # Tools an INSTANCE principal may never invoke, whatever it was granted.
      #
      # WHY A STATIC OVERLAY AND NOT JUST CAREFUL GRANTS. For an instance the
      # grant glob is otherwise the ONLY control, because the layers beneath
      # it are bypassed for a principal with no User:
      #
      #   * Ai::Tools::McpPlatformToolRegistrar#enforce_permission! does
      #     `return if instance_authorized`, skipping
      #     `user.has_permission?(required)`.
      #
      #     This bullet used to name a second thing skipped here — an "MCP-token
      #     permission intersection". There was no such control. The registrar
      #     carried a `token:` kwarg no caller ever passed, so the branch reading
      #     it was dead on every path; it was deleted in IMP-a18f5a8ed393. Do not
      #     count it as a layer, and do not re-add one without building it: MCP
      #     tokens are Doorkeeper access tokens, which carry OAuth `scopes`, not
      #     Powernode permissions, so a real intersection needs a scope→permission
      #     mapping that does not exist. Such a mapping must cover all EIGHT
      #     scopes Doorkeeper ACCEPTS (read, write, admin, billing, users,
      #     webhooks, workflows, files — config/initializers/doorkeeper.rb:124),
      #     not just the four ADVERTISED at well_known_controller.rb:48; a token
      #     minted with `admin` would otherwise fall straight through it.
      #   * Tool bodies used to read `@user.nil?` as an "internal/system
      #     bypass". That premise — MCP-invoked callers always carry a user —
      #     predates instance principals and is false for them, so the
      #     per-action permission map was never consulted for one. All seven
      #     tools carrying an ACTION_PERMISSIONS map now use the same explicit
      #     three-rung ladder instead (internal? / instance_authorized? / a nil
      #     user fails closed): SystemFleetTool (75ed9154) plus SdwanTool,
      #     SystemAcmeTool, SystemArchitectureCatalogTool, SystemIngressTool,
      #     SystemPackageRepositoryTool and SystemStorageOwnerTool (ef3059da).
      #     None still infers internal from a nil user. SystemFleetTool takes
      #     an explicit `internal:` flag, and the registrar marks grant-gated
      #     instance calls via `instance_authorized=` (IMP-9030413bc292). That
      #     closes the *unmarked* bypass, not the tier skip — a marked instance
      #     call still skips the per-action map, by design, treating the
      #     per-tool grant as its authorization. That treatment holds only
      #     because the executed action is pinned to the granted name: the grant
      #     is checked against the TOOL NAME, and a multi-action tool would
      #     otherwise run whatever action the CALLER supplied, letting a benign
      #     grant reach a destroy-shaped sibling. McpPlatformToolRegistrar
      #     #enforce_action_scope! rejects an instance's caller-supplied action
      #     that disagrees with the invoked tool name (IMP-e8138c2714fb) — if
      #     that check is ever removed, this overlay is bypassable again.
      #   * DEPTH. may_invoke? sees only the FIRST tool name, so for a while
      #     this overlay stopped at the first hop: a tool that delegates to a
      #     skill executor forwarded only `user:`, an instance principal has no
      #     User, and the executor read that nil user as "in-process caller" and
      #     handed every tool it nested the internal bypass — unchecked by name,
      #     destroy-shaped or not. Executors now carry the instance provenance
      #     and Ai::Tools::BaseTool#execute re-applies this overlay to the action
      #     each nested tool actually runs (IMP-0e6b216de843). Grant globs are
      #     deliberately not re-checked below the first hop — the operator grants
      #     a composer, and THIS overlay is what bounds what that composer may do
      #     on an instance's behalf.
      #
      # Net effect without this overlay: one over-broad pattern —
      # "platform.system_*", or a careless "platform.*" — is an unattributed,
      # unapproved, unaudited destroy. Deny wins over any grant, including an
      # exact-name one, so the blast radius of a grant mistake is bounded by
      # code rather than by reviewer attention.
      #
      # Destructive work belongs to a USER principal: human-attributable, run
      # through has_permission?, and eligible for Ai::ApprovalChain gating.
      # This overlay does not touch users. (A user principal gets no token-level
      # narrowing either — see the note above.)
      #
      # Patterns are matched against the tool name with any "platform." prefix
      # stripped, case-insensitively. Deliberately shape-based rather than an
      # enumerated list: core must not know the extension's tool catalogue, and
      # a new destroy-shaped tool must be denied the day it ships, not the day
      # someone remembers to add it here.
      #
      # NOTE: %w[] does not support inline comments — a "#..." line inside the
      # literal below is not a comment, it becomes literal words that are
      # silently added as extra (wrong, though so far harmless — none happen
      # to fnmatch a real tool name) deny patterns. Confirmed by eval'ing this
      # exact array standalone: it held 107 entries where 15 were intended,
      # 92 of them stray words from the two annotations below. Every
      # per-pattern rationale therefore lives up here as real comments, not
      # inline. Keep it that way — the array itself must contain ONLY bare
      # patterns.
      #
      # *upgrade_boot_image* — arms an A/B boot slot that the node then
      # REBOOTS into, so it is at least as consequential as *_reboot_instance
      # above — denying the reboot while permitting the thing that causes one
      # is incoherent. It also retargets what the node runs after that
      # reboot, on itself or on a peer in the same account. Reachable by MCP
      # only since the action was added to PlatformApiToolRegistry (it had
      # been declared, tested and unroutable); this keeps that fix from
      # widening what an instance principal can reach.
      #
      # *_hold (IMP-b2f80e6d1c65) denies system_instance_hold and
      # system_instance_release_hold — arm/disarm of the operator ops hold,
      # both system.instances.control tier, same as *_stop_instance/
      # *_reboot_instance above. system_instance_release_hold is the sharper
      # risk: InstanceOpsHoldService#release! does not require a user (only
      # #hold! does), so nothing downstream stops an instance principal from
      # clearing a hold a human operator placed — exactly re-creating the
      # unattended-start race the feature exists to prevent (2026-07-27: a
      # start 30s after stop truncated a blob under a dual mount).
      # system_instance_hold shares the tier and the same arm/disarm pair, so
      # it is denied for symmetry even though #hold! itself fails closed on a
      # nil user today — the overlay does not rely on that holding. The
      # pattern matches only the trailing "_hold", so
      # system_instance_hold_status (system.instances.read, unrestricted like
      # the tool's other read actions) is unaffected.
      # *_deferred_operation and *intervention_policy (IMP-e8adfcfcab9b) — the
      # human approval gate itself, in both directions. approve_deferred_operation
      # EXECUTES the operation a human was asked to authorise, so an instance
      # principal reaching it closes the loop on its own request; reject_ is
      # denied for the same arm/disarm symmetry as *_hold above, since discarding
      # an operator's pending decision is equally a decision that was not theirs.
      # create_/update_intervention_policy is the sharper risk and the reason
      # this is shape-based rather than a single name: an intervention policy is
      # what DECIDES whether an action needs approval at all, so
      # create_intervention_policy(scope: "global", policy: "auto_approve")
      # disables gating account-wide — one call that makes every later gate
      # vacuous. delete_intervention_policy was already covered by *delete*;
      # denying only the delete while permitting the rewrite was the incoherence.
      #
      # These are precisely the actions whose authorization CANNOT be checked
      # for an instance: it has no User, so has_permission? has nothing to ask
      # about, which is why AgentAutonomyTool's per-action map (added by the
      # same task) waves an instance through. The overlay is the layer that
      # bounds it. Verified against the whole registry: these two patterns match
      # exactly the five intended actions and no others, and the plural read
      # actions (list_deferred_operations, list_intervention_policies) do not
      # match, so an instance keeps its read surface.
      #
      # *replace_instance* (IMP-4d6423bf4eb3, operator ruling R5, 2026-09-03)
      # denies system_replace_instance, the ADDITIVE half of a DR replace.
      # Alone it terminates nothing — it claims a warm pool member and moves
      # the failed instance's volumes, SDWAN membership and VIPs onto it —
      # which is why the pair shipped with only *reap_* here and the
      # `reap: true` terminate it can raise refused for an instance principal
      # in SystemFleetTool's gate context. That left the two halves
      # asymmetric: an instance principal could consume a pool member and
      # re-home another instance's workload, human-unattributably, and the
      # gate-context refusal was the only PRINCIPAL-BASED brake on the
      # terminate riding along. Not the only brake outright, stated precisely
      # because the weaker claim is the one that justifies this pattern: the
      # reap arm goes through Ai::AutonomyGate under system.instance_reap,
      # declared require_approval (and an unmatched category resolves there
      # too), so the terminate parked for an operator on every path. That
      # verdict is operator-tunable and says nothing about WHO asked, which is
      # the gap an overlay pattern closes. Denying the whole verb makes both
      # the reap-through-replace refusal and the reap policy defence in depth
      # instead of the sole controls. Deliberately narrower than a
      # `*replace*` so a future replace-shaped read or config verb is not
      # swept in; verified against the whole registry to match exactly this
      # one action (principal_deny_overlay_spec pins that).
      DESTRUCTIVE_TOOL_PATTERNS = %w[
        *_deferred_operation
        *intervention_policy
        *destroy*
        *terminate*
        *decommission*
        *delete*
        *purge*
        *prune*
        *revoke*
        *rotate*
        *drain_*
        *reap_*
        *recycle*
        emergency_*
        *_stop_instance
        *_reboot_instance
        *upgrade_boot_image*
        *_hold
        *replace_instance*
      ].freeze

      # True when the tool is destroy-shaped and therefore off-limits to every
      # instance principal.
      def destructive_tool?(tool_name)
        name = tool_name.to_s.downcase.sub(/\Aplatform\./, "")
        return false if name.empty?

        DESTRUCTIVE_TOOL_PATTERNS.any? do |pattern|
          ::File.fnmatch(pattern, name, ::File::FNM_EXTGLOB)
        end
      end

      def for_user(user)
        new(kind: :user, account: user.account, user: user, subject_id: user.id)
      end

      # Cross-plane (federation) principal: an authenticated remote FederationPartner
      # invoking a tool on THIS plane. Bound to the LOCAL account that owns the
      # partner row, and default-deny like an instance — scoped to the partner's
      # allowed_capabilities and never destroy-shaped (see #may_invoke?).
      def for_federation_partner(partner)
        new(kind: :federation, account: partner.account, subject_id: partner.id, federation_partner: partner)
      end

      # @return [Principal, nil] nil when the CN resolves to no live instance
      #   (or no resolver is injected) — callers fall through to the OAuth path.
      def for_instance_cn(cn)
        instance = instance_resolver.call(cn)
        return nil if instance.nil?

        account = instance.try(:account)
        return nil if account.nil?

        new(kind: :instance, account: account, node_instance: instance, subject_id: instance.try(:id))
      end
    end

    attr_reader :kind, :account, :user, :node_instance, :federation_partner, :subject_id

    def initialize(kind:, account:, subject_id:, user: nil, node_instance: nil, federation_partner: nil)
      @kind = kind
      @account = account
      @subject_id = subject_id
      @user = user
      @node_instance = node_instance
      @federation_partner = federation_partner
    end

    def user?
      kind == :user
    end

    def instance?
      kind == :instance
    end

    def federation?
      kind == :federation
    end

    # Non-user principals (instance, federation) are DEFAULT-DENY and scoped to a
    # tool allowlist. The MCP controller gates every door on this, so a restricted
    # principal cannot reach tools/resources/prompts it was not granted.
    def restricted?
      instance? || federation?
    end

    # nil-safe tool authorization. Users are unrestricted (existing permission
    # behavior). Instances are DEFAULT-DENY: a tool is invocable only when it
    # matches one of the instance's granted patterns (from the injected
    # resolver) AND is not destroy-shaped (see DESTRUCTIVE_TOOL_PATTERNS).
    def may_invoke?(tool_name)
      return true if user?

      name = tool_name.to_s
      return false if self.class.destructive_tool?(name)

      granted_tool_patterns.any? { |p| ::File.fnmatch(p, name, ::File::FNM_EXTGLOB) }
    end

    # Filter a tool list (array of {"name"=>...} hashes or strings) to the
    # invocable subset. Users get the full list; instances get only granted tools.
    def filter_tools(tools)
      return tools if user?

      tools.select { |t| may_invoke?(tool_name_of(t)) }
    end

    def granted_tool_patterns
      return Array(self.class.tool_grant_resolver.call(node_instance)).map(&:to_s) if instance?
      return Array(federation_partner&.allowed_capabilities).map(&:to_s) if federation?

      []
    end

    private

    def tool_name_of(tool)
      tool.is_a?(Hash) ? (tool["name"] || tool[:name]) : tool
    end
  end
end
