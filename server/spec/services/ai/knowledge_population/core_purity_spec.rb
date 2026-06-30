# frozen_string_literal: true

require "rails_helper"

# IMP-d9245299cbb2 — the core knowledge-population generators embedded business-extension domain
# text as generated content: business-feature concept descriptions ("Multi-tenancy",
# "Subscription Management", "Business Features … Billing, BaaS, reseller, AI publisher") and
# `BaaS:: → baas_` FK-prefix examples. Core seeds knowledge about itself, not about the private
# business extension. This guard fails if any of these files reintroduces a business-domain term.
RSpec.describe "Ai::KnowledgePopulation core purity" do
  files = %w[
    app/services/ai/knowledge_population/graph_builder_service.rb
    app/services/ai/knowledge_population/document_generator_service.rb
    app/services/ai/knowledge_population/populator_service.rb
  ]

  # Specific business-extension strings/examples (case-insensitive). Deliberately narrow so it
  # only catches the known leak, not unrelated public extensions (Marketing/SupplyChain/etc.).
  forbidden = [
    "BaaS", "baas_", "Business Features", "Subscription Management",
    "Subscription and Billing", "subscription lifecycle", "reseller", "AI publisher",
    "Multi-tenancy"
  ]

  files.each do |rel|
    it "#{rel} embeds no business-extension domain text" do
      content = File.read(Rails.root.join(rel))
      hits = forbidden.select { |term| content.match?(/#{Regexp.escape(term)}/i) }
      expect(hits).to be_empty,
        "#{rel} embeds business-domain term(s) #{hits.inspect} — core knowledge-population must not describe the business extension"
    end
  end
end
