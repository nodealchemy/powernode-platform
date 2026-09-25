# frozen_string_literal: true

require "rails_helper"

# C7: these services call complete_structured, so the API enforces the schema
# (Anthropic output_config.format, OpenAI response_format json_schema strict).
# A "respond ONLY with valid JSON" line in the prompt adds nothing.
RSpec.describe "reasoning SYSTEM_PROMPTs under structured output" do # rubocop:disable RSpec/DescribeClass
  [
    Ai::Reasoning::ChainOfThoughtService,
    Ai::Reasoning::StarReasoningService,
    Ai::Reasoning::ReflectionService,
    Ai::Reasoning::OutputEvaluatorService
  ].each do |service|
    it "#{service.name} carries no JSON-only instruction" do
      expect(service::SYSTEM_PROMPT).not_to match(/ONLY with valid JSON/i)
    end
  end
end
