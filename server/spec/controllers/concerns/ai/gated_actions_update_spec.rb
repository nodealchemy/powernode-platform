# frozen_string_literal: true

require "rails_helper"

# IMP-1836bb0021b1 — `Ai::GatedActions#gate_update!`, the sibling of
# #gate_create! and the same ordering invariant read from the other end.
#
# The validate → reload → gate sequence was hand-inlined at three SDWAN call
# sites and about to be copied to more. Those copies encode two things a
# response-shape example cannot see:
#
#   * the record is validated BEFORE Ai::AutonomyGate is consulted, so an
#     unsaveable payload opens no audit row for an operation that could never
#     have run (the argument #gate_create!'s spec makes at length);
#   * the record is RELOADED afterwards, so the dry-run assignment cannot ride
#     along on any later save — step 1 is a check, not a write.
#
# `Page` stands in as a core model with a cheap validation; the helper knows
# nothing about it.
RSpec.describe Ai::GatedActions, "#gate_update!", type: :controller do
  controller(ApplicationController) do
    include ::Ai::GatedActions

    skip_before_action :authenticate_request, raise: false

    def update_thing
      @record = current_account.pages.find(params[:id])

      gate_update!(
        record: @record,
        attributes: { title: params[:title] },
        response_key: :page,
        serializer: ->(page) { { id: page.id, title: page.title } },
        action_category: "test.page_update",
        executor_class: "GatedActionsSpec::UpdatePage",
        params: { page_id: @record.id, attributes: { title: params[:title] } },
        source_type: "Page",
        source_id: @record.id,
        description: "Update page to #{params[:title]}"
      )
    end
  end

  let(:account) { create(:account) }
  let(:user)    { create(:user, account: account) }
  let!(:page)   { create(:page, account: account, user: user, title: "before") }

  before do
    routes.draw { patch "update_thing" => "anonymous#update_thing" }
    allow(controller).to receive(:current_account).and_return(account)
    allow(controller).to receive(:current_user).and_return(user)
  end

  def patch_title(title)
    patch :update_thing, params: { id: page.id, title: title }
  end

  describe "ordering: validation precedes the gate" do
    it "opens no gate row when the incoming attributes are invalid" do
      expect { patch_title("") }.not_to change(::Ai::DeferredOperation, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["error"]).to be_present
    end

    # Control: without it, "no gate row" is equally satisfied by an action that
    # never reaches the gate for ANY input.
    it "opens a gate row when they are valid" do
      expect { patch_title("after") }
        .to change { ::Ai::DeferredOperation.where(action_category: "test.page_update").count }.by(1)
    end

    it "does not consult Ai::AutonomyGate at all for an invalid payload" do
      expect(::Ai::AutonomyGate).not_to receive(:evaluate)

      patch_title("")

      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  # The dry-run assignment must not survive the helper. Observed on the RECORD
  # rather than on the response, because no response branch renders it: the
  # :pending branch renders the approval stub and the :proceed branch reloads
  # before serializing. An un-discarded change is invisible until something
  # else saves the instance — which is exactly why it needs pinning here.
  it "leaves no un-gated in-memory change on the record" do
    patch_title("after")

    record = controller.instance_variable_get(:@record)
    expect(record.changed?).to be(false), "the un-gated assignment survived the gate"
    expect(record.title).to eq("before")
    expect(page.reload.title).to eq("before"), "the row was written outside the executor"
  end

  # A validation failure is not a policy block. AutonomyGate#evaluate rescues
  # StandardError and returns :blocked, so without the on_blocked branch a
  # RecordInvalid arrives as a generic "Gate evaluation failed" 422 and the
  # client loses details.errors.
  describe "when the executor's write is invalid" do
    before do
      invalid = ::Page.new
      invalid.errors.add(:title, "has already been taken")
      allow(::Ai::AutonomyGate).to receive(:evaluate).and_return(
        ::Ai::AutonomyGate::Result.new(
          decision: :blocked,
          error: "Gate evaluation failed: Validation failed",
          exception: ActiveRecord::RecordInvalid.new(invalid)
        )
      )
    end

    it "renders the executor's own field-level errors" do
      patch_title("after")

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["details"]).to be_present
      expect(response.parsed_body.dig("details", "errors").to_s).to match(/already been taken/)
    end
  end

  # ...and a real policy block still reads as one.
  it "renders a policy block as a plain 422 with no field errors" do
    allow(::Ai::AutonomyGate).to receive(:evaluate).and_return(
      ::Ai::AutonomyGate::Result.new(decision: :blocked, error: "Action test.page_update is blocked by policy")
    )

    patch_title("after")

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body["error"]).to match(/blocked by policy/)
  end
end
