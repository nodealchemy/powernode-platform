# frozen_string_literal: true

require "rails_helper"

# IMP-1635cb7fa768 item 1, REVIEW FINDING — THE INVITATION CHANNEL CONFERS ROLES
# WITHOUT THE ESCALATION GUARD.
#
# Item 1 was fixed at the predicate (Role#assignable_by?) so that every conferral
# site inherits the correction. The independent review of that diff found a
# conferral site that never asked the predicate at all: Api::V1::Invitations
# Controller does not `include RoleAssignmentGuard`. #create and #update permit
# `role_names: []` verbatim, Invitation#validate_role_names checks EXISTENCE only
# (`role_names - Role.pluck(:name)`, unscoped by account and with no subset
# test), and #accept then applies each name through User#add_role, which attaches
# any global role including `super_admin`.
#
# Reachability: #create is gated by `team.invite` OR `users.create`, and the
# seeded `manager` role holds both. So POST /api/v1/invitations with
# `role_names: ["super_admin"]` is a one-call escalation from manager to
# grant-all — strictly wider than the admin bypass item 1 closed, and reachable
# by a NON-admin.
#
# The actor is the INVITER, checked at invite time: an invitation is a promise to
# confer, and the person who makes it is the one whose authority bounds it.
# Re-checking only at #accept would leave the promise mintable and would answer
# to whoever happens to redeem it (an unauthenticated caller with a token).
#
# ACTORS ARE REAL SEEDED ROLES, never `permissions: [...]` synthetics — same
# reason as spec/models/role_conferral_admin_bypass_spec.rb: the no-lockout
# examples are worthless if the actor's grants are invented rather than seeded.
RSpec.describe "API::V1::Invitations role conferral", type: :request do
  before do
    allow(WorkerJobService).to receive(:enqueue_job).and_return({ "status" => "queued" })
    allow(WorkerJobService).to receive(:enqueue_notification_email).and_return({ "status" => "queued" })
  end

  let(:account) { create(:account) }

  def user_with_role(role_name)
    user = create(:user, account: account)
    user.roles = []
    user.add_role(role_name)
    user.reload
    user
  end

  let(:manager) { user_with_role("manager") }
  let(:admin) { user_with_role("admin") }
  let(:super_admin) { user_with_role("super_admin") }

  def invite(actor, role_names)
    post "/api/v1/invitations",
         params: { invitation: {
           email: "invitee-#{SecureRandom.hex(4)}@example.com",
           first_name: "In",
           last_name: "Vitee",
           role_names: role_names
         } },
         headers: auth_headers_for(actor),
         as: :json
  end

  # POSITIVE CONTROLS. Without these a refusal below could pass for the wrong
  # reason — a forbidden actor, a rejected email, a role that does not exist.
  describe "premises" do
    it "the manager actor may send invitations at all" do
      expect(manager.has_permission?("users.create") || manager.has_permission?("team.invite")).to be(true),
        "the seeded manager cannot invite; the escalation example would pass vacuously"
    end

    it "the manager actor may NOT confer super_admin by the shared predicate" do
      expect(Role.find_by!(name: "super_admin", account_id: nil).assignable_by?(manager)).to be false
    end

    it "super_admin is a real seeded global role, so existence validation admits it" do
      expect(Role.exists?(name: "super_admin", account_id: nil)).to be true
    end
  end

  describe "the escalation" do
    it "a manager cannot mint an invitation carrying super_admin" do
      expect { invite(manager, [ "super_admin" ]) }.not_to change(Invitation, :count)

      expect(response).to have_http_status(:unprocessable_content),
        "a manager minted an invitation conferring system.admin"
    end

    it "an admin cannot mint one either (the predicate has no admin exemption)" do
      expect { invite(admin, [ "super_admin" ]) }.not_to change(Invitation, :count)
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "a manager cannot mint one carrying a worker role" do
      expect { invite(manager, [ "system_worker" ]) }.not_to change(Invitation, :count)
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "a manager cannot WIDEN an existing invitation into super_admin" do
      invitation = create(:invitation, account: account, inviter: manager, role_names: [ "member" ])

      patch "/api/v1/invitations/#{invitation.id}",
            params: { invitation: { role_names: [ "super_admin" ] } },
            headers: auth_headers_for(manager),
            as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(invitation.reload.role_names).to eq([ "member" ]),
        "the widened role names were persisted"
    end

    it "a manager cannot confer ANOTHER account's custom role" do
      foreign = create(:role, account: create(:account), name: "foreign_ops", role_type: "user")

      expect { invite(manager, [ foreign.name ]) }.not_to change(Invitation, :count)
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  # NO LOCKOUT. The guard must not break the ordinary invite.
  describe "no lockout for a legitimate operator" do
    it "a manager still invites a member" do
      expect { invite(manager, [ "member" ]) }.to change(Invitation, :count).by(1)
      expect(response).to have_http_status(:created)
    end

    it "an invitation with no role_names still takes the member default" do
      post "/api/v1/invitations",
           params: { invitation: { email: "plain@example.com", first_name: "P", last_name: "L" } },
           headers: auth_headers_for(manager),
           as: :json

      expect(response).to have_http_status(:created)
      expect(Invitation.find(JSON.parse(response.body)["data"]["id"]).role_names).to eq([ "member" ])
    end

    it "an admin still invites a manager" do
      expect { invite(admin, [ "manager" ]) }.to change(Invitation, :count).by(1)
      expect(response).to have_http_status(:created)
    end

    it "a system.admin holder still invites a super_admin" do
      expect { invite(super_admin, [ "super_admin" ]) }.to change(Invitation, :count).by(1)
      expect(response).to have_http_status(:created)
    end

    it "an unchanged update that does not touch role_names still succeeds" do
      invitation = create(:invitation, account: account, inviter: manager, role_names: [ "member" ])

      patch "/api/v1/invitations/#{invitation.id}",
            params: { invitation: { first_name: "Renamed" } },
            headers: auth_headers_for(manager),
            as: :json

      expect(response).to have_http_status(:success)
      expect(invitation.reload.first_name).to eq("Renamed")
    end
  end

  # The accept path applies the names the invitation carries. It must resolve
  # them inside the INVITATION's account: `Role.find_by(name:)` is unscoped, and
  # two accounts may each own a custom role of the same name (the shadow
  # validation only forbids shadowing a GLOBAL name), so an unscoped lookup can
  # attach a foreign account's role to a brand-new user.
  describe "accept resolves role names inside the invitation's account" do
    it "does not attach another account's like-named custom role" do
      foreign_account = create(:account)
      foreign = create(:role, account: foreign_account, name: "ops_lead", role_type: "user")
      local = create(:role, account: account, name: "ops_lead", role_type: "user")

      invitation = create(:invitation, account: account, inviter: manager, role_names: [ "ops_lead" ])
      raw_token = invitation.token

      post "/api/v1/invitations/accept",
           params: { token: raw_token, password: "Zq7#mVtr9Lw2Xk", password_confirmation: "Zq7#mVtr9Lw2Xk" },
           as: :json

      expect(response).to have_http_status(:created)
      # (User also carries whatever default role its own creation assigns, so
      # this asserts on the CONFERRED pair rather than on the whole set.)
      user = User.find(JSON.parse(response.body)["data"]["user"]["id"])
      expect(user.roles.map(&:id)).to include(local.id)
      expect(user.roles.map(&:id)).not_to include(foreign.id)
    end
  end
end
