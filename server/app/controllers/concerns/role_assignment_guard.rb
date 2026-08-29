# frozen_string_literal: true

# RoleAssignmentGuard
#
# Single source of truth for the privilege-escalation defense on role
# assignment. A user may assign a role only if they are an admin, or the role
# is non-system AND every effective permission the role grants is one the
# current user already holds. Duplicating this check invites drift: if one copy
# gains a new admin-bypass permission or an extra guard and another is missed,
# the protection weakens on one endpoint but not the other. Keeping the admin
# bypass and the subset test here means all three call sites
# (RolesController#assign_to_user, RolesController#assignable, and
# Admin::UsersController#update) stay in lockstep.
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
  # pure delegation: same admin bypass, same system-role refusal, same subset
  # test, one implementation.
  def can_assign_role?(role)
    role.assignable_by?(current_user)
  end

  # System/regular admins bypass the escalation subset check and may assign any
  # (non-system, for non-admins) role. Delegates to the same predicate the model
  # rule uses, so the bypass set cannot diverge between the two.
  def role_assignment_admin?
    Role.assignment_admin?(current_user)
  end

  # Every effective permission `role` grants is one the user already holds.
  # `user_permissions` is passed in so callers filtering many roles can hoist
  # the (cached but non-trivial) permission_names lookup out of the loop.
  def role_permissions_subset_of_user?(role, user_permissions)
    role.permission_names.all? { |perm| user_permissions.include?(perm) }
  end
end
