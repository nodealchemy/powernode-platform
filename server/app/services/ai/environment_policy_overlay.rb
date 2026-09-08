# frozen_string_literal: true

module Ai
  # The per-environment overlay on a resolved intervention policy (Environment
  # campaign, increment 3). Operator ruling 2026-09-08: infrastructure agents
  # are trusted for reversible actions and need a person for destructive ones
  # and for anything touching a control-plane node or prod.
  #
  # ONE DIRECTION ONLY. This overlay can ESCALATE a verdict to
  # `require_approval`; it never relaxes one. A `block` stays a block, a
  # `require_approval` stays parked, and an environment can never make an
  # operator's explicit refusal permissive. Three rules, any of which escalates:
  #
  #   1. the environment lists the category in `approval_required_categories`
  #      (globs, e.g. "system.task.*" or "*");
  #   2. the environment's default decision authority is `supervised`, in which
  #      case every gated operation there needs a person;
  #   3. the environment is protected (control plane, prod) and the category is
  #      a DESTRUCTIVE family — terminate, delete, destroy, reap, rollback,
  #      reboot, stop, drain, recycle, boot-image drift, migration apply — per
  #      the `autonomy.destructive_categories` SiteSetting (comma-separated
  #      globs), falling back to DEFAULT_DESTRUCTIVE_GLOBS when unset.
  #
  # The default globs are ANCHORED ON THE VERB (`*[._]delete`, not `*delete*`):
  # a category is "<noun>.<verb>" or "<noun>_<verb>", and an unanchored
  # substring also matched observation and signal kinds that merely mention
  # the verb (`system.boot_image_stale`, `system.pool.terminate_failed`,
  # `platform.resilience.drain_started`), which would have parked the FILING
  # of a signal in the control plane, not the action.
  #
  # The verdict carries WHY (`environment_escalation`) so the approval card and
  # the audit row can say "parked because prod is protected", not just "parked".
  module EnvironmentPolicyOverlay
    ESCALATED_POLICY = "require_approval"
    DESTRUCTIVE_SETTING_KEY = "autonomy.destructive_categories"
    DEFAULT_DESTRUCTIVE_GLOBS = %w[
      *[._]delete *[._]destroy *[._]terminate *[._]reap *[._]reboot *[._]stop
      *[._]drain *[._]recycle *[._]rollback *[._]rollback_* *[._]revert *[._]revert_*
      *[._]boot_image_drift *[._]migrations.apply *[._]migrate
    ].freeze
    # Verdicts the overlay may raise. `silent` is NOT here: the gate and both
    # fleet gates treat it as a refusal ("never"), and rewriting an operator's
    # quiet never into require_approval would hand it to the default chain's
    # every-active-user audience — a fail-open.
    RELAXED_POLICIES = %w[auto_approve notify_and_proceed].freeze

    module_function

    # @param policy_match [Hash] the hash Ai::InterventionPolicyService#resolve built
    # @param environment [Ai::Environment, nil]
    # @param action_category [String]
    # @return [Hash] the same hash, escalated when a rule fires, with
    #   :environment and :environment_escalation keys added
    def apply(policy_match, environment:, action_category:)
      return policy_match if environment.nil?

      reason = escalation_reason(environment, action_category)
      annotated = policy_match.merge(environment: environment, environment_escalation: reason)
      return annotated if reason.nil? || !RELAXED_POLICIES.include?(policy_match[:policy].to_s)

      annotated.merge(policy: ESCALATED_POLICY, notifications_suppressed: false)
    end

    # nil when no rule fires; otherwise a short machine-readable reason.
    def escalation_reason(environment, action_category)
      category = action_category.to_s
      if glob_match?(Array(environment.approval_required_categories), category)
        "environment #{environment.slug} requires approval for #{category}"
      elsif environment.default_decision_authority.to_s == "supervised"
        "environment #{environment.slug} is supervised: every gated operation needs a person"
      elsif environment.protected? && glob_match?(destructive_globs, category)
        "environment #{environment.slug} is protected and #{category} is destructive"
      end
    end

    def destructive_globs
      raw = ::SiteSetting.get(DESTRUCTIVE_SETTING_KEY)
      list = raw.is_a?(Array) ? raw : raw.to_s.split(",")
      globs = list.map { |g| g.to_s.strip }.reject(&:empty?)
      globs.empty? ? DEFAULT_DESTRUCTIVE_GLOBS : globs
    rescue StandardError
      DEFAULT_DESTRUCTIVE_GLOBS
    end

    # Plain fnmatch: `*` spans dots (no FNM_PATHNAME) and there is no brace
    # expansion — FNM_EXTGLOB's `{a,b}` is exponential in nested repeats, and a
    # SiteSetting is not a place to accept that.
    def glob_match?(globs, category)
      globs.any? { |glob| ::File.fnmatch(glob.to_s, category) }
    end
  end
end
