# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Skills::Contract do
  let(:entry) { conforming_capability_entry }

  def errors_for(mutate = nil)
    candidate = entry.deep_dup
    mutate&.call(candidate)
    described_class.validate(candidate)
  end

  it "accepts a conforming capability skill" do
    expect(errors_for).to eq([])
  end

  describe "limits" do
    it "rejects a description over 200 characters" do
      expect(errors_for(->(e) { e["description"] = "Use when #{'x' * 200}" })).to include(a_string_matching(/description is \d+ chars/))
    end

    it "rejects a description that does not start with \"Use when\"" do
      expect(errors_for(->(e) { e["description"] = "Handles sample tasks." })).to include(a_string_matching(/must start with "Use when"/))
    end

    it "rejects a prompt over 1,200 tokens" do
      expect(errors_for(->(e) { e["system_prompt"] = "- step\n#{'word ' * 1_200}" })).to include(a_string_matching(/max 1200/))
    end

    it "rejects a prompt that is prose rather than a procedure or checklist" do
      expect(errors_for(->(e) { e["system_prompt"] = "You are a helpful expert in everything." })).to include(a_string_matching(/procedure or checklist/))
    end

    it "rejects ids in the prompt" do
      expect(errors_for(->(e) { e["system_prompt"] += "\n- see IMP-0123abcd4567" })).to include(a_string_matching(/improvement id/))
      expect(errors_for(->(e) { e["system_prompt"] += "\n- node 019f7cb5-3858-7a2e-9c1d-1234567890ab" })).to include(a_string_matching(/UUID/))
      expect(errors_for(->(e) { e["system_prompt"] += "\n- host 10.0.0.12" })).to include(a_string_matching(/IPv4/))
    end
  end

  describe "metadata" do
    it "requires triggers with use_when, keywords and applies_to" do
      errors = errors_for(->(e) { e["metadata"]["triggers"] = { "use_when" => [], "not_for" => [] } })
      expect(errors).to include(a_string_matching(/use_when/), a_string_matching(/keywords/), a_string_matching(/applies_to is required/))
    end

    it "rejects unknown project kinds and stages" do
      errors = errors_for(lambda do |e|
        e["metadata"]["triggers"]["applies_to"] = %w[spaceship]
        e["metadata"]["triggers"]["stages"] = %w[launch]
      end)
      expect(errors).to include(a_string_matching(/applies_to has unknown values spaceship/), a_string_matching(/stages has unknown values launch/))
    end

    it "requires the manifest's read_only to agree with its gate category" do
      expect(errors_for(->(e) { e["metadata"]["manifest"]["gate_category"] = "mutate" })).to include(a_string_matching(/read_only must be true exactly/))
    end

    it "requires known tier and effort hints" do
      errors = errors_for(->(e) { e["metadata"]["hints"].merge!("min_tier" => "galactic", "effort" => "extreme") })
      expect(errors).to include(a_string_matching(/min_tier/), a_string_matching(/effort/))
    end

    it "allows only requires, composes and refines relations" do
      expect(errors_for(->(e) { e["metadata"]["relations"] = { "supersedes" => %w[old-skill] } }))
        .to include(a_string_matching(/unsupported types supersedes/))
    end

    it "requires at least two positive evals" do
      expect(errors_for(->(e) { e["metadata"]["evals"] = [ { "task" => "x", "expect_selected" => true } ] }))
        .to include(a_string_matching(/at least 2/))
    end

    it "requires a domain the owner declares" do
      expect(errors_for(->(e) { e["metadata"]["domain"] = "storage" })).to include(a_string_matching(/not a core domain/))
    end

    it "rejects an unknown owner_repo" do
      expect(errors_for(->(e) { e["metadata"]["owner_repo"] = "somewhere" })).to include(a_string_matching(/owner_repo/))
    end
  end

  describe "generic vs platform-dev facet" do
    it "keeps this repository's paths out of a generic skill" do
      expect(errors_for(->(e) { e["system_prompt"] += "\n- run scripts/wt.sh remove" }))
        .to include(a_string_matching(/generic skill must not carry this repository/))
    end

    it "lets a powernode-platform-dev skill name them, and pins it to the platform project kind" do
      dev = conforming_capability_entry(domain: "powernode-platform-dev")
      dev["metadata"]["triggers"]["applies_to"] = %w[powernode-platform]
      dev["system_prompt"] += "\n- run scripts/wt.sh remove"
      expect(described_class.validate(dev)).to eq([])

      dev["metadata"]["triggers"]["applies_to"] = %w[any]
      expect(described_class.validate(dev)).to include(a_string_matching(/must apply to exactly \[powernode-platform\]/))
    end

    it "keeps the platform project kind for platform-dev skills only" do
      expect(errors_for(->(e) { e["metadata"]["triggers"]["applies_to"] = %w[powernode-platform] }))
        .to include(a_string_matching(/only powernode-platform-dev skills/))
    end
  end

  describe "extension domains" do
    around do |example|
      registry = described_class.instance_variable_get(:@registered_domains).dup
      example.run
    ensure
      described_class.instance_variable_set(:@registered_domains, registry)
    end

    it "accepts a domain an extension registered for its own owner id only" do
      described_class.register_domains(owner: "extensions/sample", domains: %w[sample-domain])
      ext = conforming_capability_entry(owner_repo: "extensions/sample", domain: "sample-domain")
      expect(described_class.validate(ext)).to eq([])

      core = conforming_capability_entry(domain: "sample-domain")
      expect(described_class.validate(core)).to include(a_string_matching(/not a core domain/))
    end
  end

  describe "at save (Ai::Skill)" do
    def build_skill(entry)
      Ai::Skill.new(entry.slice("slug", "name", "category", "description", "tags", "system_prompt", "metadata").merge(status: "active"))
    end

    it "rejects a capability skill that breaks the contract" do
      skill = build_skill(entry.deep_dup.tap { |e| e["description"] = "No prefix here." })
      expect(skill).not_to be_valid
      expect(skill.errors[:metadata].join).to include("Use when")
    end

    it "accepts a conforming capability skill" do
      expect(build_skill(entry)).to be_valid
    end

    context "when the owning extension is disabled (its domains unregistered)" do
      let(:orphan) do
        conforming_capability_entry(owner_repo: "extensions/absent-ext", domain: "absent-domain").tap do |e|
          e["metadata"]["triggers"]["applies_to"] = %w[infrastructure]
        end
      end
      let!(:skill) do
        build_skill(orphan).tap { |s| s.assign_attributes(account_id: nil, is_system: true) }.tap(&:save!)
      end

      it "still records usage and toggles (state-only saves are not re-judged)" do
        expect { skill.record_usage!(outcome: "success", account: create(:account)) }.not_to raise_error
        expect { skill.update!(is_enabled: false) }.not_to raise_error
      end

      it "still rejects a content edit that breaks the contract" do
        expect(skill.update(description: "No prefix here.")).to be(false)
      end

      it "is rejected by the seed gate, which stays strict" do
        expect(described_class.validate(orphan)).to include(a_string_matching(/not a extensions\/absent-ext domain/))
      end
    end

    it "does not re-judge a state-only save of a row that no longer conforms" do
      skill = build_skill(entry).tap { |s| s.assign_attributes(account_id: nil, is_system: true) }
      skill.save!
      skill.update_columns(description: "Legacy prose that predates the contract.")
      expect { skill.update!(last_used_at: Time.current) }.not_to raise_error
    end

    it "leaves a skill that declares no capability (legacy) outside the contract" do
      expect(build(:ai_skill, description: "Legacy prose.", metadata: { "domain" => "platform" })).to be_valid
    end
  end
end
