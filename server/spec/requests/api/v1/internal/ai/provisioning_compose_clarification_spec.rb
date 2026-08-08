# frozen_string_literal: true

require "rails_helper"

# Regression coverage for the CLARIFICATION payload on the INTERNAL compose_plan
# endpoint (IMP 019fe1d8).
#
# Ai::Provisioning::PlanComposerService#compose! deliberately returns
# `{ clarification_needed: true, message:, available_providers: }` — not a plan —
# when the account has 2+ providers and the brief carries no usable
# preferred_provider (plan_composer_service.rb#resolve_provider_choice).
#
# The PUBLIC REST path guards for that shape
# (concerns/ai/missions/plan_composition_actions.rb). The INTERNAL path — the one
# every system_provisioning mission actually runs through, via
# AiProvisioningComposePlanJob — did not: it passed the Hash straight into
# persist_plan_pointer / `plan&.id`, raising
#   NoMethodError: undefined method `id' for {...}:Hash
# which the blanket rescue turned into a 422. The worker job then exhausted its
# retries and the mission was left dead in compose_plan.
#
# Reproduced live on ops-hub 2026-08-08 (mission 019fe1d5-4958-79a4-bd59-d479ed515a9d)
# during the platform-autonomy-dryrun P1 baseline: ops-hub has exactly two
# providers, so this fired on every attempt.
RSpec.describe "Internal AI provisioning compose_plan clarification handling", type: :request do
  include_context "internal api auth"

  let(:mission_account) { create(:account) }
  let(:mission_user) { create(:user, account: mission_account) }

  # A provisioning-shaped brief with NO preferred_provider — the exact shape that
  # makes resolve_provider_choice ask which provider to use.
  let(:ambiguous_brief) do
    {
      "intent" => "provision a 3-node Powernode stack",
      "use_case" => "database",
      "scale" => { "initial" => 3, "target" => 3, "growth_profile" => "steady" },
      "regions" => %w[dna rna],
      "preferred_provider" => nil
    }
  end

  let(:mission) do
    create(
      :ai_mission,
      account: mission_account,
      created_by: mission_user,
      mission_type: "infrastructure",
      custom_phases: [{ "key" => "compose_plan", "label" => "Compose plan", "order" => 0 }],
      configuration: { "brief" => ambiguous_brief }
    )
  end

  # The literal shape PlanComposerService returns. Symbol keys, as produced.
  let(:clarification_payload) do
    {
      clarification_needed: true,
      message: "I see you have multiple cloud providers configured (Local QEMU, Proxmox). " \
               "Which would you like to use?",
      available_providers: [
        { id: "019f6cb3-d96b-76b2-9063-992884b6edee", name: "local-qemu", type: "local_qemu" },
        { id: "019f73b2-8bc5-7511-90f9-2d2409a85f55", name: "IPNode PVE", type: "proxmox" }
      ]
    }
  end

  before do
    composer = instance_double(::Ai::Provisioning::PlanComposerService)
    allow(::Ai::Provisioning::PlanComposerService).to receive(:new).and_return(composer)
    allow(composer).to receive(:compose!).and_return(clarification_payload)
  end

  def post_compose
    post "/api/v1/internal/ai/provisioning/missions/#{mission.id}/compose_plan",
         headers: service_headers
  end

  it "does not crash trying to read .id off the clarification Hash" do
    post_compose

    expect(response.body).not_to include("undefined method")
    expect(response.body).not_to include("Compose plan failed")
  end

  # Contract: mirror the PUBLIC path (plan_composition_actions.rb) exactly —
  # render_error with the composer's own message and the payload (minus the
  # marker key) under `details`. Consistency between the two paths is the point;
  # a bespoke success-shaped clarification contract for the internal path only
  # would be a larger design change than this defect warrants.
  it "surfaces the composer's clarification message instead of a NoMethodError" do
    post_compose

    body = JSON.parse(response.body)
    expect(body["success"]).to be false
    expect(body["error"]).to match(/multiple cloud providers/i)
    expect(body.dig("details", "available_providers").length).to eq(2)
    # No plan was composed, so no plan_id may be advertised anywhere.
    expect(body.dig("data", "plan_id")).to be_nil
  end

  it "does not persist a plan pointer on the mission" do
    post_compose

    expect(mission.reload.configuration.dig("plan", "plan_id")).to be_nil
  end

  it "leaves the response non-retryable rather than a transient server error" do
    post_compose

    # The worker job retries on failure; a clarification is a terminal,
    # operator-actionable state, not something a retry can resolve.
    expect(response.status).not_to eq(500)
    expect(response.status).to be < 500
  end
end
