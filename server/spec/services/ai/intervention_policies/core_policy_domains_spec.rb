# frozen_string_literal: true

require "rails_helper"

# Core's own intervention-policy domains. Without them every core category
# (dev.*, docs.*, release.*, and the agent-outreach verbs) fell into the
# panel's catch-all "Other policies" section, because only extensions
# registered domains with Ai::ClaudeExport::PolicyDomains.
RSpec.describe Ai::InterventionPolicies::CorePolicyDomains do
  let(:domains) { Ai::ClaudeExport::PolicyDomains }

  it "is registered with PolicyDomains at boot, once per domain" do
    registered = domains.registered.map(&:first)

    described_class::PREFIXES.each_key do |domain|
      expect(registered.count(domain)).to eq(1), "#{domain} registered #{registered.count(domain)} times"
    end
  end

  it "files the core categories that used to land in Other policies" do
    {
      "dev.campaign_propose"       => "governance",
      "dev.governance_materialize" => "improvement_loop",
      "dev.prompt_refine"          => "improvement_loop",
      "dev.skill_refine"           => "improvement_loop",
      "dev.task_claim"             => "improvement_loop",
      "dev.task_complete"          => "improvement_loop",
      "docs.update"                => "improvement_loop",
      "dev.multi_file_change"      => "improvement_loop",
      "ralph.repository_write"     => "improvement_loop",
      "campaign.resume"            => "improvement_loop",
      "ai.intervention_policy.write" => "governance",
      "ai.environment.write"       => "governance",
      "platform.site_setting.write" => "governance",
      "*"                          => "governance",
      "release.build_dispatch"     => "release",
      "release.deploy_platform"    => "release",
      "release.promote"            => "release",
      "release.rollback"           => "release",
      "approval"                   => "agent_outreach",
      "escalation"                 => "agent_outreach",
      "feedback"                   => "agent_outreach",
      "issue_alert"                => "agent_outreach",
      "proposal"                   => "agent_outreach",
      "status_update"              => "agent_outreach"
    }.each do |category, domain|
      expect(domains.domain_for(category)).to eq(domain), "#{category} -> #{domains.domain_for(category).inspect}"
    end
  end

  it "leaves no core static category in the catch-all" do
    # project.* is core-owned but deliberately claimed by the system extension's
    # "project" domain (ruling at System::Governance::PolicyDomainTable::PREFIXES),
    # so it is excluded here: this spec must hold in a core-only checkout.
    core_statics = Ai::InterventionPolicy::STATIC_CATEGORIES.reject { |category| category.start_with?("project.") }
    unclaimed = core_statics.reject do |category|
      described_class::PREFIXES.values.flatten.any? { |pre| category.start_with?(pre) }
    end
    expect(unclaimed).to be_empty
  end

  it "registers no core prefix that overlaps another registered domain's prefix" do
    # Core registers first, so an overlap would silently shadow (or be shadowed
    # by) an extension's domain under first-match-wins.
    core = described_class::PREFIXES
    others = domains.registered.reject { |(domain, _)| core.key?(domain) }.flat_map(&:last)
    overlaps = core.values.flatten.product(others).select { |a, b| a.start_with?(b) || b.start_with?(a) }
    expect(overlaps).to be_empty
  end

  it "claims no extension-owned namespace" do
    prefixes = described_class::PREFIXES.values.flatten
    expect(prefixes.grep(/\A(system|sdwan|project)\./)).to be_empty
  end
end
