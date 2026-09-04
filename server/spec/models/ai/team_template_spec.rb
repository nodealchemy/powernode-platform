# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::TeamTemplate do
  let(:account) { create(:account) }

  describe "#create_team!" do
    it "materialises an Ai::AgentTeam from the template (the clone-to-customise path)" do
      template = create(:ai_team_template, :system_template, name: "Crew", slug: "crew",
                        role_definitions: [ { "name" => "Lead", "type" => "manager" } ],
                        default_config: { "coordination_strategy" => "manager_led" })

      team = template.create_team!(account: account, name: "My Crew")

      expect(team).to be_a(Ai::AgentTeam)
      expect(team.account).to eq(account)
      expect(team.template_id).to eq(template.id)
      expect(team.coordination_strategy).to eq("manager_led")
      expect(team.ai_team_roles.pluck(:role_name)).to eq([ "Lead" ])
      expect(team).not_to be_canonical
    end
  end

  describe "#create_team! default name" do
    # REVIEW FIX (HIER-P4): the documented clone-to-customise path defaults the
    # team name to the TEMPLATE's, and Ai::AgentTeam validates name uniqueness
    # per account — so cloning a canonical template whose materialisation
    # already sits in the account raised RecordInvalid. The REST door
    # (Ai::Teams::CrudService#create_team_from_template, reached from
    # POST /api/v1/ai/teams with template_id) passes name: nil by default.
    it "does not collide with a team of the template's own name" do
      template = create(:ai_team_template, :system_template, name: "Platform Engineering",
                        slug: "platform-engineering", source_key: "platform-engineering",
                        role_definitions: [ { "name" => "Lead", "type" => "manager" } ])
      create(:ai_agent_team, account: account, name: "Platform Engineering")

      clone = nil
      expect { clone = template.create_team!(account: account) }.not_to raise_error
      expect(clone.name).to eq("Platform Engineering (2)")
      expect(clone.template_id).to eq(template.id)
      expect(clone).not_to be_canonical
    end

    it "keeps the template name when it is free" do
      template = create(:ai_team_template, :system_template, name: "Solo Crew", slug: "solo-crew")

      expect(template.create_team!(account: account).name).to eq("Solo Crew")
    end
  end

  describe "canonical templates" do
    it "are the global, is_system, source_key-managed ones" do
      canonical = create(:ai_team_template, :system_template, slug: "canon", source_key: "canon")
      create(:ai_team_template, :system_template, slug: "keyless", source_key: nil)
      create(:ai_team_template, account: account, slug: "mine", source_key: "mine")

      expect(described_class.canonical).to eq([ canonical ])
      expect(canonical).to be_canonical
    end
  end
end
