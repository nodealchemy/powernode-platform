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
    productivity product-management powernode-dev api-design
    design-skill-from-intent design-agent-team-from-intent
    marketing technical-researcher legal bio-research finance
    sales customer-support
    ai-agent-architect agent-autonomy extension-developer documentation-writer
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

  # A fresh demo install creates ACCOUNT copies of the three autonomy canonicals
  # (ai_example_templates_seed's showcase instances) BEFORE the baseline binding
  # pass, and resolve_for (account override first) bound those copies instead —
  # so the GLOBAL canonical rows, the ones the Claude Code export and every
  # clone read, carried no skills and no declared tier.
  it "binds the global autonomy canonicals and declares their tier despite account copies; a re-seed changes nothing" do
    seed_global_skills!
    # A provider exists before the first pass, so the canonicals' owner
    # back-fill (CoreSeeds::CanonicalAgentOwner) completes in that pass and the
    # re-seed below measures THIS fix, not a column that legitimately fills in
    # once a provider appears.
    create(:ai_provider, account: admin_account, provider_type: "openai", is_active: true)
    load_autonomy_seed = -> { silence_warnings { load Rails.root.join("db", "seeds", "autonomy_data_seed.rb") } }
    load_autonomy_seed.call

    expected_skills = {
      "infrastructure-health-monitor" => %w[devops-engineer security-analyst sre-incident-response],
      "process-automation-optimizer" => %w[product-management productivity],
      "visual-design-assistant" => %w[marketing product-management]
    }
    canonicals = expected_skills.keys.index_with { |slug| Ai::Agent.global.find_by!(slug: slug) }
    copies = canonicals.transform_values { |canonical| create(:ai_agent, account: admin_account, name: canonical.name) }

    run_seed!

    canonicals.each do |slug, canonical|
      bound = Ai::AgentSkill.where(ai_agent_id: canonical.id, is_active: true)
                            .joins(:skill).pluck("ai_skills.slug").sort
      expect(bound).to eq(expected_skills[slug]), "#{slug}: the global canonical is bound to #{bound.inspect}"
    end
    %w[process-automation-optimizer visual-design-assistant].each do |slug|
      tier = canonicals[slug].reload.mcp_metadata.dig("model_config", "model_requirements", "tier")
      expect(tier).to eq("reasoning"), "#{slug}: the global canonical declares tier #{tier.inspect}"
    end
    copies.each do |slug, copy|
      expect(Ai::AgentSkill.where(ai_agent_id: copy.id).count).to eq(expected_skills[slug].size)
    end

    bindings = -> { Ai::AgentSkill.order(:id).pluck(:id, :ai_agent_id, :ai_skill_id, :is_active, :priority) }
    rows = lambda do
      Ai::Agent.where(id: canonicals.values.map(&:id)).order(:id)
               .pluck(:id, :updated_at, :version, :mcp_metadata, :ai_provider_id, :description)
    end
    bindings_before = bindings.call
    rows_before = rows.call
    load_autonomy_seed.call
    run_seed!
    expect(bindings.call).to eq(bindings_before)
    expect(rows.call).to eq(rows_before)
  end
end
