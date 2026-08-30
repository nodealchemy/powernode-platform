# frozen_string_literal: true

require "rails_helper"

# Authentication#has_permission? used to short-circuit with `return true` on a
# `permissions` array in the decoded JWT payload, BEFORE any database read. Every
# permission gate in the app routes through that method (require_permission,
# authorize_action!, require_any_permission, can?, can_access?, and the
# ownership-OR-permission disjuncts in the business extension's controllers), so a
# token carrying that claim would have authorized off a snapshot taken at mint
# time, for the token's whole remaining lifetime.
#
# No PRODUCTION mint path populates the claim: Security::JwtService#build_user_payload
# and #build_worker_payload carry `permission_version` (a digest), not a permission
# list, and Auth::AccountSwitchService#generate_switched_tokens returns `permissions`
# in the RESPONSE BODY while its JWT payload carries only `delegation_id`. So on a
# live deployment the branch could not fire, and the invariant protecting every
# permission narrowing rested on that accident rather than on anything enforced.
#
# It was NOT unreachable here. spec/support/auth_helpers.rb#token_for minted
# `permissions: user.permission_names` into every test token, so this branch — not
# the database — answered most request specs, and a spec that revoked a permission
# after minting its headers would still have been granted it. That helper no longer
# mints the claim; the specs now exercise the production path.
#
# The branch was DELETED rather than guarded: with no reader, a future mint path
# that adds the claim cannot reopen anything, and there is no tripwire left to
# watch. These examples pin the deletion for the USER principal — a claim in the
# token is inert, and authorization is resolved live from the database on every
# check. The worker principal falls through the same deletion to
# current_worker.has_permission?; the delegation branch ABOVE it is untouched and
# is covered by delegated_session_authorization_spec.rb.
RSpec.describe "JWT permissions claim is not an authorization input", type: :controller do
  controller(ApplicationController) do
    skip_before_action :authenticate_request, raise: false

    before_action -> { require_permission("ai.agents.update") }, only: :manage

    def manage = head(:ok)
  end

  let(:account) { create(:account) }

  before do
    routes.draw { post "manage" => "anonymous#manage" }
  end

  # This actor is built with `permissions: [...]`, which mints a synthetic role
  # rather than using a seeded one. That is deliberate and load-bearing here: the
  # property under test is "the token's list is ignored and the DB is consulted",
  # so the example needs an actor whose DB-resolved answer is known and is the
  # OPPOSITE of what the claim asserts. Which real role holds ai.agents.update is
  # irrelevant to that; it is asserted directly in the sanity example below.
  context "when the token claims a permission the user does not hold" do
    let(:user) { create(:user, account: account, permissions: [ "ai.agents.read" ]) }

    before do
      controller.instance_variable_set(:@current_user, user)
      controller.instance_variable_set(:@current_account, account)
      controller.instance_variable_set(
        :@current_jwt_payload,
        { sub: user.id, permissions: [ "ai.agents.update", "ai.agents.read" ] }
      )
    end

    it "sanity: the database says the user does NOT hold ai.agents.update" do
      expect(user.has_permission?("ai.agents.update")).to be(false)
    end

    it "FORBIDS the action — the claim does not grant" do
      post :manage
      expect(response).to have_http_status(:forbidden)
    end

    it "returns false from has_permission? itself, not merely a 403 from some other guard" do
      expect(controller.send(:has_permission?, "ai.agents.update")).to be(false)
    end
  end

  # No-lockout: the legitimate audience for this gate is anyone the DATABASE says
  # holds the permission. Deleting a `return true` branch can only ever deny, so
  # this is the half that has to be proven, and it must hold whether or not the
  # (inert) claim happens to be present.
  context "when the user genuinely holds the permission" do
    let(:user) { create(:user, account: account, permissions: [ "ai.agents.update" ]) }

    before do
      controller.instance_variable_set(:@current_user, user)
      controller.instance_variable_set(:@current_account, account)
    end

    it "allows the action when the token carries no permissions claim" do
      controller.instance_variable_set(:@current_jwt_payload, { sub: user.id })
      post :manage
      expect(response).to have_http_status(:ok)
    end

    # Not a regression the deleted branch could have caused — it only ever
    # GRANTED, so an omitting claim never denied anyone under either version.
    # Kept as a pin that the claim is inert in BOTH directions, so a future
    # "consult the token when it is present" optimisation reddens here too.
    it "allows the action when an empty claim is present (inert in both directions)" do
      controller.instance_variable_set(
        :@current_jwt_payload,
        { sub: user.id, permissions: [] }
      )
      post :manage
      expect(response).to have_http_status(:ok)
    end
  end

  # The deleted branch sat directly above `return current_worker.has_permission?`,
  # so the worker principal (current_user nil, current_worker set) is the other
  # audience of this change and needs its own no-lockout example.
  context "worker principal" do
    # The :worker factory's own after(:create) assign_role('worker') is a silent
    # no-op — Worker#valid_worker_role? rejects the role_type 'user' role the
    # factory creates — so the role this example needs is attached directly.
    let(:worker) { create(:worker, account: account) }
    let(:worker_role) do
      Role.find_or_create_by!(name: "spec_worker_authz", role_type: "system") do |r|
        r.display_name = "Spec Worker Authz"
        r.description = "Worker role for jwt_permissions_claim_spec"
      end
    end

    before do
      controller.instance_variable_set(:@current_user, nil)
      controller.instance_variable_set(:@current_worker, worker)
      controller.instance_variable_set(:@current_account, account)
    end

    it "still authorizes a worker whose role grants the permission" do
      worker_role.role_permissions.find_or_create_by!(permission_name: "ai.agents.update")
      worker.worker_roles.create!(role: worker_role)
      controller.instance_variable_set(:@current_jwt_payload, { sub: worker.id })
      post :manage
      expect(response).to have_http_status(:ok)
    end

    it "FORBIDS a worker whose roles do not grant it, even with the claim" do
      controller.instance_variable_set(
        :@current_jwt_payload,
        { sub: worker.id, permissions: [ "ai.agents.update" ] }
      )
      post :manage
      expect(response).to have_http_status(:forbidden)
    end
  end
end
