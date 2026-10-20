# frozen_string_literal: true

# A conforming capability-skill entry (the normalized shape the seed gate and
# Ai::Skills::Contract read), for contract and gate specs to mutate.
module CapabilitySkillFixtures
  def conforming_capability_entry(slug: "sample-capability", owner_repo: "core", domain: "software-engineering", **overrides)
    entry = {
      "slug" => slug,
      "name" => slug.split("-").map(&:capitalize).join(" "),
      "category" => "testing_qa",
      "description" => "Use when a sample task needs the sample capability.",
      "tags" => %w[sample],
      "system_prompt" => <<~PROMPT.strip,
        ## Procedure
        1. Read the task and its acceptance criteria.
        2. Do the work in small verified steps.
        - [ ] Verify before reporting.
      PROMPT
      "metadata" => {
        "author" => "system",
        "owner_repo" => owner_repo,
        "domain" => domain,
        "capability" => slug,
        "triggers" => {
          "use_when" => [ "a sample task arrives" ],
          "not_for" => [],
          "keywords" => %w[sample],
          "applies_to" => %w[any],
          "stages" => %w[build]
        },
        "manifest" => { "verbs" => %w[search_knowledge], "knowledge_tags" => [], "gate_category" => "read", "read_only" => true },
        "hints" => { "min_tier" => "standard", "effort" => "medium", "long_context" => false, "tool_heavy" => false, "safety_critical" => false },
        "evals" => [
          { "task" => "Do the sample task", "expect_selected" => true },
          { "task" => "Do the sample task again", "expect_selected" => true }
        ]
      }
    }
    overrides.each { |key, value| entry[key.to_s] = value }
    entry
  end
end

RSpec.configure { |config| config.include CapabilitySkillFixtures }
