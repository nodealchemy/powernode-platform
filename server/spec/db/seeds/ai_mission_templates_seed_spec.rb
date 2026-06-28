# frozen_string_literal: true

require "rails_helper"

# Verifies the GLOBAL (system) mission-template seed — db/seeds/ai_mission_templates.rb.
# The seed file guards on Powernode::Seeds.baseline?, which is defined inline in
# db/seeds.rb and therefore not loaded in the test environment. We stub it so the
# single seed file can be exercised in isolation without running the full seed.
RSpec.describe "db/seeds/ai_mission_templates.rb", type: :seed do
  def run_seed!
    seeds = Module.new do
      def self.baseline? = true
      def self.demo? = false
    end
    stub_const("Powernode::Seeds", seeds)
    load Rails.root.join("db", "seeds", "ai_mission_templates.rb")
  end

  describe "content_production template" do
    let(:template) { Ai::MissionTemplate.find_by(source_key: "content-production", account_id: nil) }

    before { run_seed! }

    it "seeds a global, default content_production template" do
      expect(template).to be_present
      expect(template.account_id).to be_nil
      expect(template.template_type).to eq("system")
      expect(template.mission_type).to eq("content_production")
      expect(template.is_default).to be(true)
      expect(template.status).to eq("active")
    end

    it "defines the content pipeline phases in order" do
      expect(template.phase_keys).to eq(
        %w[brief script asset_generation composition render deliver completed]
      )
    end

    it "has no approval gates (linear pipeline driven by the orchestrator)" do
      expect(template.approval_gate_keys).to eq([])
      expect(template.rejection_mappings).to eq({})
    end

    it "passes the phases_format validation" do
      expect(template).to be_valid
    end
  end

  describe "idempotency" do
    it "upserts by source_key without duplicating on a second run" do
      run_seed!
      run_seed!
      expect(Ai::MissionTemplate.where(source_key: "content-production", account_id: nil).count).to eq(1)
    end
  end
end
