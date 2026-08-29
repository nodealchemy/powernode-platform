# frozen_string_literal: true

require 'rails_helper'

# IMP-161c10c09e9d (b) — the escalation half.
#
# Api::V1::UsersController#assign_default_roles reads `default_roles` off the
# governing entitlements plan and feeds each NAME straight into User#add_role.
# There was no subset/escalation check on that path, unlike
# Api::V1::RolesController#assign_to_user, which asks
# RoleAssignmentGuard#can_assign_role? first. `admin` is a GLOBAL role
# (account_id nil), so a plan carrying default_roles: ["admin"] turned every
# `admin.user.create` holder into a global-admin factory.
#
# Reachability: the plan comes from Powernode::ExtensionRegistry.provider(
# :entitlements), which is nil in core mode — so this is LATENT on a core-mode
# deployment and LIVE wherever an entitlements provider is registered. The
# provider is stubbed here so the core rule is tested on its own terms, with no
# extension loaded (core must not name one).
#
# Actors are built from REAL SEEDED role traits, never `permissions: []`: a
# synthetic role cannot fail a rule about what the real seeded roles contain.
RSpec.describe 'Api::V1::Users default-role escalation', type: :request do
  let(:account) { create(:account) }

  # The first user of the account, which is how `owner` is acquired in
  # production (User#assign_default_role). `owner` holds admin.user.create.
  let!(:actor) { create(:user, :owner, account: account) }

  let(:admin_role) { Role.find_by(name: 'admin', account_id: nil) }

  def stub_entitlements_plan(default_roles)
    # `limits` is read by Entitlements::UsageLimitService.can_add_user?, which
    # runs before the role assignment; 9999 is its unlimited threshold.
    plan = double('plan', default_roles: default_roles, limits: { 'max_users' => 9999 })
    provider = double('entitlements_provider', plan_for: plan)
    allow(Powernode::ExtensionRegistry).to receive(:provider).and_call_original
    allow(Powernode::ExtensionRegistry).to receive(:provider).with(:entitlements).and_return(provider)
  end

  def create_user_as(headers_user, email:)
    post '/api/v1/users',
         params: { user: { email: email, name: 'Default Roles Probe', password: 'Str0ng!Passw0rd1' } },
         headers: auth_headers_for(headers_user),
         as: :json
  end

  # Sanity: the actor genuinely holds the seeded global owner role and the
  # create permission. If this goes red the rest of the file stops testing what
  # it claims to (the `permissions: []` failure mode, inverted).
  it 'builds an actor that genuinely holds the global owner role and admin.user.create' do
    expect(actor.roles.map(&:name)).to include('owner')
    expect(actor.roles.find_by(name: 'owner').account_id).to be_nil
    expect(actor.has_permission?('admin.user.create')).to be true
  end

  # The seeded facts this whole defect rests on. Asserted against the DATABASE
  # rows, not the catalog source, because the rows are what production applies.
  it 'seeds `admin` as a GLOBAL role the owner may not confer directly' do
    expect(admin_role).to be_present
    expect(admin_role.account_id).to be_nil
    expect(admin_role.permission_names.all? { |p| actor.permission_names.include?(p) }).to be false
  end

  describe 'a plan whose default_roles name a role the actor may not confer' do
    before { stub_entitlements_plan(%w[admin]) }

    # THE ROW, not the status: the escalation is the user_roles row, and the
    # request returns 201 either way.
    it 'does not confer the global admin role on the created user' do
      create_user_as(actor, email: 'zz-escalation-probe@example.com')

      created = User.find_by(email: 'zz-escalation-probe@example.com')
      expect(created).to be_present
      expect(created.roles.map(&:name)).not_to include('admin')
      expect(created.has_permission?('admin.access')).to be false
    end

    # No lockout: the create itself still succeeds and the user still receives
    # the core default role. Dropping an unassignable plan role must not deny
    # the operation — the plan is operator config, not caller input.
    it 'still creates the user with the core default role' do
      expect {
        create_user_as(actor, email: 'zz-escalation-nolockout@example.com')
      }.to change(User, :count).by(1)

      created = User.find_by(email: 'zz-escalation-nolockout@example.com')
      expect(created.roles.map(&:name)).to include('member')
    end
  end

  describe 'a plan whose default_roles are within the actor authority' do
    # `developer` is a real seeded role whose permissions the seeded `owner`
    # role fully contains, so the subset rule permits it. This is the flow that
    # must keep working.
    before { stub_entitlements_plan(%w[developer]) }

    it 'still confers the plan default role' do
      create_user_as(actor, email: 'zz-escalation-allowed@example.com')

      created = User.find_by(email: 'zz-escalation-allowed@example.com')
      expect(created).to be_present
      expect(created.roles.map(&:name)).to include('developer')
    end
  end

  describe 'an admin actor' do
    let!(:admin_actor) { create(:user, :admin, account: create(:account)) }

    before { stub_entitlements_plan(%w[manager]) }

    # The operator path must survive: admin.access bypasses the subset test in
    # RoleAssignmentGuard, exactly as it does on RolesController#assign_to_user.
    it 'still confers a plan default role it could assign directly' do
      create_user_as(admin_actor, email: 'zz-escalation-admin-actor@example.com')

      created = User.find_by(email: 'zz-escalation-admin-actor@example.com')
      expect(created).to be_present
      expect(created.roles.map(&:name)).to include('manager')
    end
  end
end
