# frozen_string_literal: true

require "rails_helper"

# The composer must honor the brief's preferred_template (IMP 019fe3a7-266d).
#
# resolve_default_template takes the account's OLDEST template unconditionally;
# on ops-hub that is "base" (blank boot_mode => cloud_init => no agent), which
# made the composed plan incapable of completing the runtime handshake while
# its prose named the right template (run 20260808a F3). With preferred_template
# now captured on the brief (see intent_capture_template_selection_spec.rb),
# the composer resolves it against the account's templates — by name or id,
# case-insensitively — and only falls back to the oldest-template default, with
# a warning, when the brief names nothing or names it unresolvably.
RSpec.describe Ai::Provisioning::PlanComposerService, "template selection", type: :service do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:mission) { create(:ai_mission, account: account, created_by: user, mission_type: "infrastructure") }

  subject(:service) { described_class.new(account: account, mission: mission) }

  before { skip "system extension not loaded" unless defined?(::System::NodeTemplate) }

  # Creation order matters: `older` is created FIRST so it is what
  # resolve_default_template returns — mirroring ops-hub, where the oldest
  # template is the unusable one.
  let!(:older) { create(:system_node_template, account: account, name: "pn-base-image", config: {}) }
  let!(:uefi) do
    create(:system_node_template, account: account, name: "powernode-ops-cell",
                                  config: { "boot_mode" => "uefi_disk" })
  end

  before do
    ::System::NodeTemplate.where(account_id: account.id)
                          .where.not(id: [older.id, uefi.id]).destroy_all
  end

  def resolve(brief)
    service.send(:resolve_template, brief)
  end

  it "premise: the default (oldest) template is the unusable one" do
    expect(service.send(:resolve_default_template)).to eq(older)
  end

  it "resolves the brief's preferred_template by name, beating the oldest-first default" do
    expect(resolve({ "preferred_template" => "powernode-ops-cell" })).to eq(uefi)
  end

  it "matches case-insensitively" do
    expect(resolve({ "preferred_template" => "POWERNODE-OPS-CELL" })).to eq(uefi)
  end

  it "resolves by template id" do
    expect(resolve({ "preferred_template" => uefi.id })).to eq(uefi)
  end

  it "falls back to the default — loudly — when the named template resolves to nothing" do
    expect(Rails.logger).to receive(:warn).with(/matches no template/).at_least(:once)
    allow(Rails.logger).to receive(:warn).and_call_original
    expect(resolve({ "preferred_template" => "golden-image-9" })).to eq(older)
  end

  it "keeps the oldest-first default when the brief names nothing" do
    expect(resolve({})).to eq(older)
  end

  it "stamps the chosen template's id into provisioning step inputs" do
    inputs = {}
    brief = { "preferred_template" => "powernode-ops-cell", "scale" => { "initial" => 1 } }
    service.send(:merge_resolved_inputs!, inputs, brief, "provision_full_stack")
    expect(inputs["template_id"]).to eq(uefi.id)
  end

  it "attaches the role module to the CHOSEN template, not the default" do
    # attach_role_module_to_template! previously hardcoded
    # resolve_default_template — attaching the workload module to a template
    # the plan doesn't use.
    expect(service).to receive(:resolve_template)
      .with(hash_including("preferred_template" => "powernode-ops-cell"))
      .and_return(uefi)
    service.send(:attach_role_module_to_template!,
                 { "preferred_template" => "powernode-ops-cell", "use_case" => "database" })
  end
end
