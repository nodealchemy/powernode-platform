# frozen_string_literal: true

# RoleAssignmentGuard
#
# Single source of truth for the privilege-escalation defense on role
# assignment. A user may assign a role only if every effective permission the
# role grants is one they already hold, and — for a role_type "system" role —
# only if they are an admin as well. Admin standing decides whether the SYSTEM
# tier is reachable at all; it has never been a licence to confer more than the
# caller holds, and since IMP-1635cb7fa768 it no longer reads like one.
# Duplicating this check invites drift: if one copy gains an extra exemption and
# another is missed, the protection weakens on one endpoint but not the other.
# Keeping the rule in one place means the controller call sites
# (RolesController#assign_to_user, RolesController#assignable,
# Admin::UsersController#update, UsersController#assign_default_roles and
# InvitationsController's role_names guard) stay in lockstep.
#
# INCLUDING THIS CONCERN IS WHAT MAKES A CONTROLLER OBEY THE RULE, so the list
# above is a list of controllers that opted IN, not a proof that no conferral
# escapes. InvitationsController was such an escape for as long as it existed:
# it conferred roles at #accept from a `role_names` array nothing bounded, which
# no amount of correctness in this file would have caught. Before trusting the
# rule to be total, enumerate the writers, not the includers:
#
#   command grep -rn 'add_role\|assign_role\|roles <<\|user_roles.create' \
#     --include=*.rb server/app server/lib worker/app extensions
#
# Sites that deliberately do NOT answer to this rule, and why: Setup::
# FirstAdminService (bootstrap — there is no actor to bound), User's own
# owner/member defaults on account creation (fixed, non-escalating), and the
# WORKER channel (Worker#assign_role / Role#grant_to_worker), which provisions
# service accounts and is gated on its own permissions rather than on a human
# actor's grants.
#
# Requires `current_user` (provided by ApplicationController).
module RoleAssignmentGuard
  extend ActiveSupport::Concern

  private

  # True if current_user may assign `role` to a user without escalating
  # privilege beyond what they already hold.
  #
  # The rule itself now lives on Role#assignable_by? so NON-controller conferral
  # sites can reuse it rather than restate it (plan `default_roles` appliers,
  # services, extension models — none of which have a `current_user`). This is a
  # pure delegation: same system-role refusal, same subset test, one
  # implementation.
  def can_assign_role?(role)
    role.assignable_by?(current_user)
  end

  # Every effective permission `role` grants is one the user already holds.
  # `user_permissions` is passed in so callers filtering many roles can hoist
  # the (cached but non-trivial) permission_names lookup out of the loop.
  def role_permissions_subset_of_user?(role, user_permissions)
    role.permission_names.all? { |perm| user_permissions.include?(perm) }
  end
end
