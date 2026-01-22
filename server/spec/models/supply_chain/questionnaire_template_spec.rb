# frozen_string_literal: true

require "rails_helper"

RSpec.describe SupplyChain::QuestionnaireTemplate, type: :model do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }

  describe "associations" do
    it { is_expected.to belong_to(:account).optional }
    it { is_expected.to belong_to(:created_by).class_name("User").optional }
    it { is_expected.to have_many(:questionnaire_responses).class_name("SupplyChain::QuestionnaireResponse").dependent(:restrict_with_error) }
  end

  describe "validations" do
    subject { build(:supply_chain_questionnaire_template, account: account) }

    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:template_type) }
    it { is_expected.to validate_inclusion_of(:template_type).in_array(SupplyChain::QuestionnaireTemplate::TEMPLATE_TYPES) }
    it { is_expected.to validate_presence_of(:version) }

    describe "unique name within scope" do
      it "allows same name for different accounts" do
        create(:supply_chain_questionnaire_template, account: account, name: "Test Template", is_system: false)
        other_account = create(:account)
        template = build(:supply_chain_questionnaire_template, account: other_account, name: "Test Template", is_system: false)
        expect(template).to be_valid
      end

      it "prevents duplicate names within same account" do
        create(:supply_chain_questionnaire_template, account: account, name: "Test Template", is_system: false)
        template = build(:supply_chain_questionnaire_template, account: account, name: "Test Template", is_system: false)
        expect(template).not_to be_valid
        expect(template.errors[:name]).to include("has already been taken")
      end

      it "prevents duplicate names for system templates" do
        create(:supply_chain_questionnaire_template, name: "System Template", is_system: true, account: nil)
        template = build(:supply_chain_questionnaire_template, name: "System Template", is_system: true, account: nil)
        expect(template).not_to be_valid
      end
    end
  end

  describe "scopes" do
    let!(:system_template) { create(:supply_chain_questionnaire_template, is_system: true, account: nil) }
    let!(:custom_template) { create(:supply_chain_questionnaire_template, is_system: false, account: account) }
    let!(:active_template) { create(:supply_chain_questionnaire_template, is_active: true, account: account) }
    let!(:inactive_template) { create(:supply_chain_questionnaire_template, is_active: false, account: account) }
    let!(:soc2_template) { create(:supply_chain_questionnaire_template, template_type: "soc2", account: account) }
    let!(:iso_template) { create(:supply_chain_questionnaire_template, template_type: "iso27001", account: account) }

    it "filters system templates" do
      expect(described_class.system_templates).to include(system_template)
      expect(described_class.system_templates).not_to include(custom_template)
    end

    it "filters custom templates" do
      expect(described_class.custom_templates).to include(custom_template)
      expect(described_class.custom_templates).not_to include(system_template)
    end

    it "filters active templates" do
      expect(described_class.active).to include(active_template)
      expect(described_class.active).not_to include(inactive_template)
    end

    it "filters by type" do
      expect(described_class.by_type("soc2")).to include(soc2_template)
      expect(described_class.by_type("soc2")).not_to include(iso_template)
    end

    it "filters for account including system templates" do
      other_account = create(:account)
      other_template = create(:supply_chain_questionnaire_template, account: other_account)

      expect(described_class.for_account(account)).to include(custom_template, system_template)
      expect(described_class.for_account(account)).not_to include(other_template)
    end
  end

  describe "type predicates" do
    it "#system? returns true for system templates" do
      template = build(:supply_chain_questionnaire_template, is_system: true)
      expect(template.system?).to be true
    end

    it "#custom? returns true for non-system templates" do
      template = build(:supply_chain_questionnaire_template, is_system: false)
      expect(template.custom?).to be true
    end

    it "#active? returns true for active templates" do
      template = build(:supply_chain_questionnaire_template, is_active: true)
      expect(template.active?).to be true
    end

    it "#soc2? returns true for soc2 type" do
      template = build(:supply_chain_questionnaire_template, template_type: "soc2")
      expect(template.soc2?).to be true
    end

    it "#iso27001? returns true for iso27001 type" do
      template = build(:supply_chain_questionnaire_template, template_type: "iso27001")
      expect(template.iso27001?).to be true
    end

    it "#gdpr? returns true for gdpr type" do
      template = build(:supply_chain_questionnaire_template, template_type: "gdpr")
      expect(template.gdpr?).to be true
    end

    it "#hipaa? returns true for hipaa type" do
      template = build(:supply_chain_questionnaire_template, template_type: "hipaa")
      expect(template.hipaa?).to be true
    end

    it "#pci_dss? returns true for pci_dss type" do
      template = build(:supply_chain_questionnaire_template, template_type: "pci_dss")
      expect(template.pci_dss?).to be true
    end
  end

  describe "#section_count" do
    it "returns number of sections" do
      template = build(:supply_chain_questionnaire_template, sections: [{ id: "s1" }, { id: "s2" }])
      expect(template.section_count).to eq(2)
    end

    it "returns 0 for nil sections" do
      template = build(:supply_chain_questionnaire_template, sections: nil)
      template.save!
      expect(template.section_count).to eq(0)
    end
  end

  describe "#question_count" do
    it "returns number of questions" do
      template = build(:supply_chain_questionnaire_template, questions: [{ id: "q1" }, { id: "q2" }, { id: "q3" }])
      expect(template.question_count).to eq(3)
    end

    it "returns 0 for nil questions" do
      template = build(:supply_chain_questionnaire_template, questions: nil)
      template.save!
      expect(template.question_count).to eq(0)
    end
  end

  describe "#questions_by_section" do
    let(:template) do
      build(:supply_chain_questionnaire_template,
            sections: [{ "id" => "s1" }, { "id" => "s2" }],
            questions: [
              { "id" => "q1", "section_id" => "s1" },
              { "id" => "q2", "section_id" => "s1" },
              { "id" => "q3", "section_id" => "s2" }
            ])
    end

    it "groups questions by section" do
      grouped = template.questions_by_section
      expect(grouped["s1"].length).to eq(2)
      expect(grouped["s2"].length).to eq(1)
    end

    it "returns empty hash when no sections" do
      template.sections = []
      expect(template.questions_by_section).to eq({})
    end
  end

  describe "#get_section" do
    let(:template) do
      build(:supply_chain_questionnaire_template,
            sections: [
              { "id" => "s1", "name" => "Section One" },
              { "id" => "s2", "name" => "Section Two" }
            ])
    end

    it "returns section by ID" do
      section = template.get_section("s1")
      expect(section["name"]).to eq("Section One")
    end

    it "returns nil for unknown section" do
      expect(template.get_section("unknown")).to be_nil
    end
  end

  describe "#get_question" do
    let(:template) do
      build(:supply_chain_questionnaire_template,
            questions: [
              { "id" => "q1", "text" => "Question One" },
              { "id" => "q2", "text" => "Question Two" }
            ])
    end

    it "returns question by ID" do
      question = template.get_question("q1")
      expect(question["text"]).to eq("Question One")
    end

    it "returns nil for unknown question" do
      expect(template.get_question("unknown")).to be_nil
    end
  end

  describe "#add_section" do
    let(:template) { create(:supply_chain_questionnaire_template, account: account, sections: []) }

    it "adds a section" do
      template.add_section(id: "new_section", name: "New Section", weight: 1.5)
      expect(template.section_count).to eq(1)
      expect(template.sections.first).to include("id" => "new_section", "name" => "New Section")
    end

    it "assigns order based on position" do
      template.add_section(id: "s1", name: "First")
      template.add_section(id: "s2", name: "Second")
      expect(template.sections.last["order"]).to eq(1)
    end
  end

  describe "#add_question" do
    let(:template) { create(:supply_chain_questionnaire_template, account: account, sections: [{ "id" => "s1" }], questions: []) }

    it "adds a question" do
      template.add_question(section_id: "s1", text: "New Question?", type: "yes_no", required: true)
      expect(template.question_count).to eq(1)
      expect(template.questions.first).to include("text" => "New Question?", "type" => "yes_no")
    end

    it "assigns a UUID" do
      template.add_question(section_id: "s1", text: "Q?", type: "text")
      expect(template.questions.first["id"]).to be_present
    end
  end

  describe "#remove_question" do
    let(:template) do
      create(:supply_chain_questionnaire_template,
             account: account,
             questions: [{ "id" => "q1" }, { "id" => "q2" }])
    end

    it "removes the question" do
      template.remove_question("q1")
      expect(template.question_count).to eq(1)
      expect(template.questions.first["id"]).to eq("q2")
    end
  end

  describe "#activate! and #deactivate!" do
    let(:template) { create(:supply_chain_questionnaire_template, account: account, is_active: false) }

    it "activates the template" do
      template.activate!
      expect(template.is_active).to be true
    end

    it "deactivates the template" do
      template.update!(is_active: true)
      template.deactivate!
      expect(template.is_active).to be false
    end
  end

  describe "#duplicate" do
    let(:template) do
      create(:supply_chain_questionnaire_template,
             account: account,
             name: "Original",
             is_system: true,
             sections: [{ "id" => "s1" }],
             questions: [{ "id" => "q1" }])
    end

    it "creates a copy" do
      duplicate = template.duplicate
      expect(duplicate).to be_persisted
      expect(duplicate.id).not_to eq(template.id)
    end

    it "uses default name with (Copy)" do
      duplicate = template.duplicate
      expect(duplicate.name).to eq("Original (Copy)")
    end

    it "allows custom name" do
      duplicate = template.duplicate(new_name: "Custom Name")
      expect(duplicate.name).to eq("Custom Name")
    end

    it "sets is_system to false" do
      duplicate = template.duplicate
      expect(duplicate.is_system).to be false
    end

    it "copies sections and questions" do
      duplicate = template.duplicate
      expect(duplicate.section_count).to eq(template.section_count)
      expect(duplicate.question_count).to eq(template.question_count)
    end

    it "allows assigning to different account" do
      other_account = create(:account)
      duplicate = template.duplicate(for_account: other_account)
      expect(duplicate.account).to eq(other_account)
    end
  end

  describe "#summary" do
    let(:template) { create(:supply_chain_questionnaire_template, account: account) }

    it "returns expected keys" do
      summary = template.summary

      expect(summary).to include(
        :id,
        :name,
        :description,
        :template_type,
        :version,
        :is_system,
        :is_active,
        :section_count,
        :question_count,
        :created_at
      )
    end
  end

  describe "#full_template" do
    let(:template) { create(:supply_chain_questionnaire_template, account: account) }

    it "returns summary, sections, and questions" do
      full = template.full_template

      expect(full).to include(:summary, :sections, :questions)
    end
  end

  describe "class methods" do
    describe ".create_soc2_template" do
      it "creates a SOC2 template" do
        template = described_class.create_soc2_template
        expect(template).to be_persisted
        expect(template.template_type).to eq("soc2")
        expect(template.is_system).to be true
        expect(template.sections.length).to eq(9) # CC1-CC9
      end
    end

    describe ".create_iso27001_template" do
      it "creates an ISO 27001 template" do
        template = described_class.create_iso27001_template
        expect(template).to be_persisted
        expect(template.template_type).to eq("iso27001")
        expect(template.is_system).to be true
        expect(template.sections.length).to eq(14) # A5-A18
      end
    end
  end

  describe "JSONB sanitization" do
    it "initializes sections as empty array" do
      template = create(:supply_chain_questionnaire_template, account: account, sections: nil)
      expect(template.sections).to eq([])
    end

    it "initializes questions as empty array" do
      template = create(:supply_chain_questionnaire_template, account: account, questions: nil)
      expect(template.questions).to eq([])
    end

    it "initializes metadata as empty hash" do
      template = create(:supply_chain_questionnaire_template, account: account, metadata: nil)
      expect(template.metadata).to eq({})
    end
  end
end
