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

  describe "what the caller's arguments control" do
    let!(:written) { create(:page, account: account, user: user, title: "Written by the executor") }

    def stub_proceed_with(page_id)
      allow(::Ai::AutonomyGate).to receive(:evaluate).and_return(
        ::Ai::AutonomyGate::Result.new(decision: :proceed, result: { data: { page_id: page_id } })
      )
    end

    it "re-finds the executor's row by result_key and renders it at 201 under response_key" do
      stub_proceed_with(written.id)

      post :create_thing, params: { title: "A valid page" }

      expect(response).to have_http_status(:created)
      # The title differs from the posted one, so this can only pass by
      # rendering the row the RESULT named — never the candidate.
      expect(response.parsed_body["data"]["page"]).to eq(
        "id" => written.id, "title" => "Written by the executor"
      )
    end

    # Without this, every example here is equally satisfied by a helper that
    # ignores `scope:` and re-finds through the bare model — which is the whole
    # of the parameter's tenancy value to an adopter.
    it "re-finds through the caller's scope, not the bare model" do
      outsider = create(:page, title: "Another account's row")
      stub_proceed_with(outsider.id)

      post :create_thing, params: { title: "A valid page" }

      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body.to_s).not_to include("Another account's row")
    end

    # The helper builds no row of its own: the executor inside the gate is the
    # only writer, and the candidate is a validation probe.
    it "writes nothing itself on the proceed path" do
      stub_proceed_with(written.id)

      expect { post :create_thing, params: { title: "A valid page" } }
        .not_to change(Page, :count)
    end

    # The gate kwargs are pure passthrough, so nothing else in the suite would
    # notice the helper dropping one — and `description:` is the sentence each
    # adopter deliberately matches to its executor's approval card.
    it "forwards the caller's gate arguments verbatim" do
      expect(::Ai::AutonomyGate).to receive(:evaluate).with(
        hash_including(
          action_category: "test.page_create",
          executor_class: "GatedActionsSpec::CreatePage",
          params: { title: "A valid page" },
          source_type: "Account",
          source_id: account.id,
          description: "Create page A valid page"
        )
      ).and_return(
        ::Ai::AutonomyGate::Result.new(decision: :proceed, result: { data: { page_id: written.id } })
      )

      post :create_thing, params: { title: "A valid page" }

      expect(response).to have_http_status(:created)
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
