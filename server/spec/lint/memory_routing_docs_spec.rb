# frozen_string_literal: true

require "rails_helper"

# Memory is routed to platform knowledge (IMP-2e6af0abff3a). The contract lives
# in code — Ai::DevLoop::LoopGuardrails::HEAD, Ai::Agent::BASE_GUARDRAILS and
# Ai::Guidance::GuidanceKnowledgeSeeder.for_memory — and the docs that route a
# reader to it must state the SAME tags, key and access level. The tokens are
# DERIVED from the guardrail constants, not restated here, so a change to the
# contract fails this spec until the docs follow.
RSpec.describe "memory routing docs agree with the memory guardrail contract" do
  root = Rails.root.join("..")
  conventions = root.join("docs/contributing/conventions")

  claude_md = File.read(root.join("CLAUDE.md"))
  lifecycle = File.read(conventions.join("knowledge-lifecycle.md"))
  mcp_first = File.read(conventions.join("mcp-first-workflow.md"))
  deployment = File.read(conventions.join("deployment-knowledge.md"))

  memory_line = lambda do |text_lines|
    text_lines.find { |l| l.include?("search_knowledge tags [memory]") } ||
      raise("no memory guardrail line found — this spec would be vacuous")
  end

  # recall tag, slug tag, record key, record tag, access level
  contract_of = lambda do |line|
    {
      recall_tag: line[/search_knowledge tags \[(\w+)\]/, 1],
      slug_tag: line[/via tag (memory-<slug>)/, 1],
      key: line[/create_knowledge key (\S+)/, 1],
      record_tag: line[/tags \[(memory-<type>)\]/, 1],
      access_level: line[/access_level (\w+)/, 1]
    }
  end

  loop_contract = contract_of.call(memory_line.call(Ai::DevLoop::LoopGuardrails::HEAD))
  agent_contract = contract_of.call(memory_line.call(Ai::Agent::BASE_GUARDRAILS.lines))

  it "derives a complete contract, identical in both guardrail constants and the seeder" do
    expect(loop_contract.values).to all(be_present)
    expect(agent_contract).to eq(loop_contract)
    # The seeder's key/tag scheme: tag_prefix "memory" -> key "memory:<slug>",
    # tags memory / memory-<type> / memory-<slug>, access_level account.
    expect(loop_contract[:recall_tag]).to eq("memory")
    expect(loop_contract[:key]).to eq("memory:<slug>")
    expect(loop_contract[:access_level]).to eq("account")
  end

  describe "CLAUDE.md" do
    let(:routing_row) do
      claude_md.lines.find { |l| l.start_with?("| Decision / incident / preference") } ||
        raise("routing row missing from CLAUDE.md")
    end

    it "routes decisions/incidents/preferences to platform knowledge tag memory-*, not a local MEMORY.md" do
      expect(routing_row).to match(/platform knowledge/)
      expect(routing_row).to include("`memory-*`")
      expect(routing_row).not_to include("MEMORY.md")
    end

    it "states the enforceability split as the table's routing rule" do
      section = claude_md[/## Where guidance lives.*?(?=\n## )/m]
      expect(section).to match(/enforceab/i)
      expect(section).to match(/hook, spec or gate/)
    end

    it "carries the memory contract in the Memory & Knowledge section" do
      section = claude_md[/## Memory & Knowledge.*?(?=\n---)/m]
      bullet = section.lines.find { |l| l.start_with?("- **Memory**") } || raise("memory bullet missing")
      expect(bullet).to include("tags:[\"#{loop_contract[:recall_tag]}\"]")
      expect(bullet).to include(loop_contract[:slug_tag])
      expect(bullet).to include("key #{loop_contract[:key]}")
      expect(bullet).to include("tags:[\"#{loop_contract[:record_tag]}\"]")
      expect(bullet).to include("access_level #{loop_contract[:access_level]}")
      expect(bullet).to match(/never global/)
      expect(bullet).to match(/never a local memory file/)
    end

    it "gives the restart window for boot-time migrations, not the stale 30s" do
      expect(claude_md).not_to include("502 for ~30s")
      expect(claude_md).to match(/~3 min/)
      expect(claude_md).to include("systemctl show -p NRestarts")
    end
  end

  it "knowledge-lifecycle.md has a Memories row carrying the contract" do
    row = lifecycle.lines.find { |l| l.start_with?("| Memories") } || raise("Memories row missing")
    expect(row).to include(loop_contract[:record_tag])
    expect(row).to include(loop_contract[:slug_tag])
    expect(row).to include(loop_contract[:key])
    expect(row).to include(loop_contract[:access_level])
    expect(row).to match(/never `?global`?/)
  end

  it "mcp-first-workflow.md recalls memory at session start" do
    session_start = mcp_first[/## Session Start.*?(?=\n## )/m]
    expect(session_start).to include("search_knowledge")
    expect(session_start).to include("tags:[\"#{loop_contract[:recall_tag]}\"]")
  end

  it "deployment-knowledge.md says memories share its access model and private is not an ACL" do
    expect(deployment).to match(/memor(y|ies)/i)
    expect(deployment).to match(/`private` is a label, not an ACL/)
  end
end
