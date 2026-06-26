# frozen_string_literal: true

require "rails_helper"

# A switched/account-delegation session carries a delegation_id in its JWT but NO
# permissions array. Previously has_permission? had no delegation-aware path, so it
# fell through to current_user.has_permission? — which resolves the user's OWN
# global/primary-account roles (NOT scoped by current_account). Net effect: a user
# delegated NARROWLY into account B carried their own (possibly broad) permissions
# into B's request context — the delegation's effective_permissions were never
# enforced. The fix: when the token carries a delegation_id, authorize against the
# LIVE Account::Delegation's effective_permissions and do NOT fall through to the
# user's own roles. Honors revocation/expiry immediately.
RSpec.describe "delegated session authorization", type: :controller do
  controller(ApplicationController) do
    skip_before_action :authenticate_request, raise: false

    before_action -> { require_permission("ai.agents.manage") }, only: :manage
    before_action -> { require_permission("ai.agents.read") }, only: :read

    def manage = head(:ok)
    def read = head(:ok)
  end

  let(:home_account) { create(:account) }
  let(:target_account) { create(:account) }
  # The user holds ai.agents.manage in their OWN account...
  let(:user) { create(:user, account: home_account, permissions: [ "ai.agents.manage" ]) }
  # ...but is delegated into target_account with only ai.agents.read.
  let(:delegation) { create(:account_delegation, account: target_account, delegated_user: user) }

  before do
    routes.draw do
      post "manage" => "anonymous#manage"
      get "read" => "anonymous#read"
    end
    # Simulate a switched/delegated session into target_account.
    controller.instance_variable_set(:@current_user, user)
    controller.instance_variable_set(:@current_account, target_account)
    controller.instance_variable_set(:@current_jwt_payload, { delegation_id: delegation.id })
    # The delegation grants ONLY ai.agents.read in the target account.
    allow_any_instance_of(Account::Delegation)
      .to receive(:effective_permissions).and_return([ "ai.agents.read" ])
  end

  it "sanity: the user's OWN roles grant ai.agents.manage (the leak this guards)" do
    expect(user.has_permission?("ai.agents.manage")).to be(true)
  end

  it "authorizes an action the delegation grants (ai.agents.read)" do
    get :read
    expect(response).not_to have_http_status(:forbidden)
  end

  it "FORBIDS an action the delegation does NOT grant, even though the user's own roles do" do
    post :manage
    expect(response).to have_http_status(:forbidden)
  end

  it "denies everything once the delegation is inactive/revoked" do
    allow_any_instance_of(Account::Delegation).to receive(:active?).and_return(false)
    get :read
    expect(response).to have_http_status(:forbidden)
  end

  it "denies when the delegation_id no longer resolves to a record" do
    controller.instance_variable_set(:@current_jwt_payload, { delegation_id: SecureRandom.uuid })
    get :read
    expect(response).to have_http_status(:forbidden)
  end

  it "denies when the delegation belongs to a DIFFERENT user (defense in depth)" do
    other_user = create(:user, account: home_account)
    foreign_delegation = create(:account_delegation, account: target_account, delegated_user: other_user)
    controller.instance_variable_set(:@current_jwt_payload, { delegation_id: foreign_delegation.id })
    # Even though it's active and would grant the permission, it does not delegate
    # to the current_user, so the session must not borrow its scope.
    get :read
    expect(response).to have_http_status(:forbidden)
  end
end
