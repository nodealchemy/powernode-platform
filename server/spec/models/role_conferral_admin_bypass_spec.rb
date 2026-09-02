# frozen_string_literal: true

require "rails_helper"

# IMP-1635cb7fa768 item 1 — THE ADMIN BYPASS CONFERRED MORE THAN THE HOLDER HAD.
#
# Role#assignable_by? is THE privilege-escalation rule for conferring a whole
# role. The conferral sites that ASK it are RolesController #assign_to_user /
# #assignable, Admin::UsersController#update, UsersController
# #assign_default_roles, InvitationsController's role_names guard,
# Accounts::DelegationService (create / update / add), Entitlements plan
# appliers, and the business extension's customer provisioning.
#
# That is a list of callers, NOT a proof of totality — the independent review of
# this diff found InvitationsController conferring roles through an unbounded
# `role_names` array, which is why it appears above and is pinned by
# spec/requests/api/v1/invitations_role_conferral_spec.rb. Sites that answer to
# a different rule by design are named in role_assignment_guard.rb's header.
#
# The predicate opened with an unconditional bypass — `return true if
# Role.assignment_admin?(user)`, i.e. any holder of system.admin OR admin.access
# — placed AHEAD of the subset test.
#
# The bypass therefore exempted exactly the case the guard exists to prevent: an
# `admin` role holder (which carries admin.access and NOT system.admin) could
# confer `super_admin`, whose single grant `system.admin` short-circuits
# User#has_permission? to true for every name. That is a one-call escalation
# from admin to grant-all, and iteration 517 (4da742156) made it reachable from
# the delegation channel too by correctly reusing this predicate.
#
# THE FIX IS AT THE PREDICATE, so both channels inherit it: the bypass now
# governs only the SYSTEM-ROLE refusal (an operator may still reach the
# service-account tier), and the subset test applies to everyone. A system.admin
# holder resolves permission_names to the whole catalog, so it keeps unrestricted
# reach without a bypass at all.
#
# ACTORS ARE REAL SEEDED ROLES, NEVER `permissions: [...]` synthetics. This
# class of defect is a fact about the catalog's own grants: a synthetic actor
# cannot observe the admin/manager lockout that iteration 517 discovered by
# execution, and the no-lockout examples below are worthless without it.
RSpec.describe "role conferral: the admin bypass", type: :model do
  let(:account) { create(:account) }

  def user_with_role(role_name)
    user = create(:user, account: account)
    user.roles = []
    user.add_role(role_name)
    user.reload
    user
  end

  let(:admin) { user_with_role("admin") }
  let(:super_admin) { user_with_role("super_admin") }
  let(:manager) { user_with_role("manager") }

  def global_role(name)
    Role.find_by!(name: name, account_id: nil)
  end

  # POSITIVE CONTROLS. Without these every refusal below could pass for the
  # wrong reason — an actor with no grants refuses everything, and a bypass that
  # was never engaged proves nothing about the bypass.
  describe "premises" do
    it "the admin actor holds admin.access and NOT system.admin" do
      expect(admin.has_permission?("admin.access")).to be(true),
        "the seeded admin role is not carrying admin.access; the escalation example would pass vacuously"
      expect(admin.roles.joins(:role_permissions).exists?(role_permissions: { permission_name: "system.admin" })).to be false
    end

    it "the bypass predicate is ENGAGED for that actor" do
      expect(Role.assignment_admin?(admin)).to be(true),
        "Role.assignment_admin? no longer answers true for an admin.access holder; this file is testing nothing"
    end

    it "super_admin is the grant-all role" do
      expect(global_role("super_admin").has_permission?("system.admin")).to be true
    end

    it "the super_admin actor resolves to the whole catalog" do
      expect(super_admin.permission_names).to eq(Permissions.all_permissions.keys.sort)
    end
  end

  describe "the escalation" do
    it "an admin.access holder cannot confer super_admin" do
      expect(global_role("super_admin").assignable_by?(admin)).to be(false),
        "an admin.access holder can confer system.admin — the guard is advisory"
    end

    it "an admin.access holder cannot confer system_worker either (same grant-all short-circuit)" do
      expect(global_role("system_worker").assignable_by?(admin)).to be false
    end

    it "a manager cannot confer super_admin" do
      expect(global_role("super_admin").assignable_by?(manager)).to be false
    end

    it "the refusal reaches the DELEGATION channel through the same predicate" do
      outsider = create(:user, account: create(:account))
      result = Accounts::DelegationService.new(admin, account).create_delegation(
        delegated_user_email: outsider.email,
        role_id: global_role("super_admin").id
      )

      expect(result[:success]).to be(false),
        "an admin minted a delegation carrying the grant-all role"
      expect(account.account_delegations.count).to eq(0)
    end
  end

  # NO LOCKOUT. Iteration 517's first attempt at the sibling fix looked correct
  # in isolation and made the platform's two broadest seeded roles undelegatable
  # by everyone including a system.admin holder. These are the counterweight.
  describe "no lockout for a legitimate operator" do
    it "a system.admin holder still confers super_admin" do
      expect(global_role("super_admin").assignable_by?(super_admin)).to be true
    end

    it "a system.admin holder still confers every seeded global role" do
      refused = Role.global.reject { |role| role.assignable_by?(super_admin) }.map(&:name)
      expect(refused).to be_empty,
        "a system.admin holder was locked out of #{refused.join(', ')}"
    end

    it "an admin still confers its own tier and everything under it" do
      %w[admin owner manager member developer content_manager ai_specialist].each do |name|
        expect(global_role(name).assignable_by?(admin)).to be(true),
          "an admin can no longer confer #{name}"
      end
    end

    it "a manager still confers the roles whose grants it holds" do
      expect(global_role("member").assignable_by?(manager)).to be true
    end

    it "nobody at all is assignable by a nil actor" do
      expect(global_role("member").assignable_by?(nil)).to be false
    end
  end
end
