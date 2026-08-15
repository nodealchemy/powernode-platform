# frozen_string_literal: true

require "rails_helper"

# IMP-493b1f33c2de — `Ai::GatedActions#gate_create!`.
#
# The "build an unsaved candidate → validate → gate! → re-find the row the
# executor wrote → serialize" sequence was hand-copied at three call sites
# before this helper existed. What those copies encode is an ORDERING
# INVARIANT, not merely boilerplate:
#
#   the candidate is validated BEFORE Ai::AutonomyGate is consulted.
#
# Gate-first and gate-second are indistinguishable on every VALID request —
# same 201, same 202, same body — so response-shape examples cannot see the
# difference. They diverge only on INVALID ones, where gate-first mints an
# Ai::DeferredOperation (and, on the require_approval branch, an approval
# request) for an operation that could never have run, answers 202 instead of
# the caller's field-level 422, and defers the failure to approval time, where
# the executor raises in front of an approver instead of the caller.
#
# The three SDWAN adopters pin this per-resource in their own request specs.
# These examples pin it on the HELPER, so a core adopter that never touches
# SDWAN inherits a tested contract rather than a convention. `Page` is used as
# a stand-in resource purely because it is a core model with a cheap validation
# — the helper knows nothing about it.
RSpec.describe Ai::GatedActions, type: :controller do
  controller(ApplicationController) do
    include ::Ai::GatedActions

    skip_before_action :authenticate_request, raise: false

    def create_thing
      candidate = current_account.pages.new(
        title: params[:title], content: "candidate body", status: "draft",
        author_id: current_user.id
      )

      gate_create!(
        candidate: candidate,
        scope: current_account.pages,
        result_key: :page_id,
        response_key: :page,
        serializer: ->(page) { { id: page.id, title: page.title } },
        action_category: "test.page_create",
        executor_class: "GatedActionsSpec::CreatePage",
        params: { title: params[:title] },
        source_type: "Account",
        source_id: current_account.id,
        description: "Create page #{params[:title]}"
      )
    end
  end

  let(:account) { create(:account) }
  let(:user)    { create(:user, account: account) }

  before do
    routes.draw { post "create_thing" => "anonymous#create_thing" }
    allow(controller).to receive(:current_account).and_return(account)
    allow(controller).to receive(:current_user).and_return(user)
  end

  describe "ordering: validation precedes the gate" do
    # THE invariant. Stated on the row rather than on the response, because
    # the response alone cannot distinguish the two orderings on any input
    # the happy-path examples use.
    it "opens no gate row when the candidate is invalid" do
      expect { post :create_thing, params: { title: "" } }
        .not_to change(::Ai::DeferredOperation, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["error"]).to be_present
    end

    # Control for the example above: without this, "no gate row" is equally
    # satisfied by an action that never reaches the gate for ANY input.
    it "opens a gate row when the candidate is valid" do
      expect { post :create_thing, params: { title: "A valid page" } }
        .to change { ::Ai::DeferredOperation.where(action_category: "test.page_create").count }.by(1)
    end

    # Independent mechanism for the same invariant: the row-level example
    # above observes the gate's SIDE EFFECT, this one observes the call.
    it "does not consult Ai::AutonomyGate at all for an invalid candidate" do
      expect(::Ai::AutonomyGate).not_to receive(:evaluate)

      post :create_thing, params: { title: "" }

      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe ":proceed" do
    let!(:written) { create(:page, account: account, user: user, title: "Written by the executor") }

    before do
      allow(::Ai::AutonomyGate).to receive(:evaluate).and_return(
        ::Ai::AutonomyGate::Result.new(decision: :proceed, result: { data: { page_id: written.id } })
      )
    end

    it "re-finds the executor's row by result_key and renders it at 201 under response_key" do
      post :create_thing, params: { title: "A valid page" }

      expect(response).to have_http_status(:created)
      expect(response.parsed_body["data"]["page"]).to eq(
        "id" => written.id, "title" => "Written by the executor"
      )
    end
  end

  describe ":pending" do
    let(:deferred) do
      ::Ai::DeferredOperation.create!(
        account: account, action_category: "test.page_create",
        executor_class: "GatedActionsSpec::CreatePage", params: {}
      )
    end

    before do
      allow(::Ai::AutonomyGate).to receive(:evaluate).and_return(
        ::Ai::AutonomyGate::Result.new(decision: :pending, deferred_operation: deferred)
      )
    end

    # The executor — never the controller — writes the row on this branch, so
    # the helper must not run its re-find/serialize path here.
    it "answers 202 with the deferred-operation id and serializes no row" do
      post :create_thing, params: { title: "A valid page" }

      expect(response).to have_http_status(:accepted)
      expect(response.parsed_body["data"]["deferred_operation_id"]).to eq(deferred.id)
      expect(response.parsed_body["data"]).not_to have_key("page")
    end
  end
end
