# frozen_string_literal: true

require "rails_helper"

# IMP-dd2904d87d6d — the platform binding seed silently dropped any binding
# whose slug didn't resolve (`next unless skill`), under-provisioning
# specialist agents for months (Infrastructure Health Monitor received one of
# its five intended skills; seven bound slugs never existed at all). The seed
# now fails LOUD before writing anything, mirroring the system extension's
# SkillBindings.validate! pattern: every missing slug collected, one raise
# with the full list.
RSpec.describe "db/seeds/platform_skill_assignments_seed.rb", type: :seed do
  let!(:admin_account) { create(:account, name: "Powernode Admin") }

  # Every slug the seed's map binds (post-phantom-cleanup). Created directly
  # rather than via the full skills seeds — the validation only consults
  # Ai::Skill.global's slug/status.
  BOUND_SLUGS = %w[
    sre-incident-response devops-engineer security-analyst
    knowledge-system-curator data skill-management business-search
    productivity product-management powernode-dev
    design-skill-from-intent design-agent-team-from-intent
    marketing technical-researcher legal bio-research finance
    sales customer-support
  ].freeze

  def seed_global_skills!(except: [])
    (BOUND_SLUGS - except).each do |slug|
      create(:ai_skill, account: nil, slug: slug, status: "active",
             name: slug.tr("-", " ").capitalize, category: "productivity")
    end
  end

  def run_seed!
    load Rails.root.join("db", "seeds", "platform_skill_assignments_seed.rb")
  end

  it "assigns every mapped skill to a seeded agent" do
    seed_global_skills!
    agent = create(:ai_agent, account: admin_account, name: "Sales Operations Specialist")

    run_seed!

    expect(Ai::AgentSkill.where(ai_agent_id: agent.id).count).to eq(3)
  end

  it "fails loud with every missing slug listed, writing nothing" do
    seed_global_skills!(except: %w[legal finance])
    create(:ai_agent, account: admin_account, name: "Sales Operations Specialist")

    expect { run_seed! }.to raise_error(/legal.*|finance.*/) do |error|
      expect(error.message).to include("legal")
      expect(error.message).to include("finance")
    end
    expect(Ai::AgentSkill.count).to eq(0)
  end
end
