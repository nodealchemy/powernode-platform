# frozen_string_literal: true

# Description-coverage computation for the tool-description ratchet (Phase 6 of
# the 2026-09-25 prompt audit). Kept out of the spec so the two-way oracle can
# drive it with synthetic descriptions.
#
# WHAT A DESCRIPTION MUST DO. tools/list carries only sentence 1 of each
# description (Mcp::ToolCatalog.summarize), and a Claude Code session sees no
# more than that plus the parameters. So:
#   - sentence 1 fits the listing (<= 160 chars) and is not cut at an
#     abbreviation or an unclosed "(" / backtick;
#   - the whole description states a contract: 3+ sentences, or declared
#     contract metadata (limit:/paginated:/returns:/refuses:/see_also:) that
#     Ai::Tools::ContractDescription renders.
# Checked on the COMPOSED description (PlatformApiToolRegistry.tool_definitions),
# i.e. what a caller receives.
module ToolDescriptionCoverage
  SNAPSHOT_PATH = Rails.root.join("spec/fixtures/tool_descriptions/under_described_actions.txt")
  FIRST_SENTENCE_LIMIT = 160
  CONTRACT_KEYS = %i[limit paginated returns refuses see_also].freeze

  module_function

  def descriptions
    Ai::Tools::PlatformApiToolRegistry.tool_definitions.to_h { |d| [ d[:name].to_s, d[:description].to_s ] }
  end

  def contract_declared?(registry_key)
    class_name = Ai::Tools::PlatformApiToolRegistry.all_tools[registry_key]
    klass = class_name&.safe_constantize
    return false unless klass

    declaration = Ai::Tools::ContractDescription.declaration_for(klass, registry_key)
    declaration.present? && CONTRACT_KEYS.any? { |key| declaration[key].present? }
  end

  def sentences(text)
    text.strip.gsub(/\s+/, " ").split(Mcp::ToolCatalog::SENTENCE_END)
  end

  # @return [Array<String>] the rules `text` breaks (empty when it passes)
  def defects(text, contract_declared:)
    parts = sentences(text)
    first = parts.first.to_s
    out = []
    out << "sentence 1 over #{FIRST_SENTENCE_LIMIT} chars" if first.length > FIRST_SENTENCE_LIMIT
    out << "sentence 1 cut at an abbreviation" if first.match?(/\b(?:e\.g|i\.e|etc|vs)\.\z/)
    out << "sentence 1 leaves ( or ` open" if first.count("(") > first.count(")") || first.count("`").odd?
    out << "fewer than 3 sentences and no contract metadata" if parts.size < 3 && !contract_declared
    out
  end

  def under_described(descs = descriptions)
    descs.filter_map do |key, text|
      key unless defects(text, contract_declared: contract_declared?(key)).empty?
    end.sort
  end

  def snapshot_entries(path = SNAPSHOT_PATH)
    return [] unless File.exist?(path)

    File.readlines(path, chomp: true).map(&:strip).reject { |l| l.empty? || l.start_with?("#") }
  end

  def report(descs = descriptions, snapshot = snapshot_entries)
    failing = under_described(descs)
    {
      growth: failing - snapshot,
      rot: snapshot - failing
    }
  end

  HEADER = <<~TXT
    # FROZEN SNAPSHOT — MCP registry actions whose advertised description is
    # under-described (spec/support/tool_description_coverage.rb explains the rules).
    #
    # THIS LIST MAY ONLY SHRINK.
    #   * A registry action that fails the rules and is not listed fails
    #     spec/services/ai/tools/tool_description_coverage_spec.rb.
    #   * A listed action that now passes (or is gone) also fails, so fix it and
    #     delete its line.
    # Registry keys, sorted, one per line. Regenerate ONLY deliberately:
    #   bin/rails runner -e test 'require Rails.root.join("spec/support/tool_description_coverage"); ToolDescriptionCoverage.write_snapshot!'
  TXT

  def write_snapshot!(path = SNAPSHOT_PATH)
    File.write(path, HEADER + under_described.join("\n") + "\n")
  end
end
