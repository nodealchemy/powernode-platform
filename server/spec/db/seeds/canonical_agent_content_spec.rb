# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20260925130000_refresh_canonical_agent_content").to_s
require Rails.root.join("db/migrate/20260925150000_move_manifest_prompts_to_system_prompt").to_s
require Rails.root.join("db/migrate/20260927120000_exclude_pipeline_workers_from_claude_export").to_s

# Seeded canonical text reaches existing rows (every seed run, and the data
# migration for installs whose seeds never re-run) without overwriting what an
# operator edited (db/seeds/concerns/canonical_content.rb).
RSpec.describe "canonical agent content" do
  content = CoreSeeds::CanonicalAgentContent
  stamp_key = Ai::Agents::CanonicalContentRefresh::STAMP_KEY
  seed_files = %w[
    claude_agents_seed.rb monitoring_analytics_agents_seed.rb ai_utility_agents_seed.rb
    ai_concierge_seed.rb autonomy_data_seed.rb
  ].freeze

  def load_seed!(file)
    silence_warnings { load Rails.root.join("db", "seeds", file) }
  end

  define_method(:seed_all!) { seed_files.each { |file| load_seed!(file) } }

  let!(:concierge_skill) do
    create(:ai_skill, :global, slug: "powernode-concierge", name: "Powernode Concierge", is_system: true)
  end

  def global(slug) = Ai::Agent.global.find_by!(slug: slug)

  # A row as an install seeded before this mechanism left it: an earlier
  # seed's text and no stamp.
  def age!(slug, description:)
    agent = global(slug)
    agent.update_columns(description: description, mcp_metadata: agent.mcp_metadata.except(Ai::Agents::CanonicalContentRefresh::STAMP_KEY))
  end

  describe "the content file" do
    content::AGENTS.each do |slug, entry|
      it "gives #{slug} exactly one routing sentence and never lists the current text as previous" do
        sentences = entry[:description].split(/(?<=[.!?])\s+/)
        expect(sentences.count { |sentence| sentence.match?(/\AUse (?:this agent )?when\b/i) }).to eq(1)
        entry[:previous].each { |field, values| expect(values).not_to include(entry.fetch(field)) }
      end
    end
  end

  describe "seeding" do
    it "writes and stamps every catalog entry on a fresh database" do
      seed_all!

      content::AGENTS.each do |slug, entry|
        agent = global(slug)
        expect(agent.description).to eq(entry[:description]), slug
        expect(agent.mcp_metadata.dig(stamp_key, "description", "digest")).to be_present
      end
      expect(global("llm-judge").mcp_metadata["system_prompt"]).to eq(content::LLM_JUDGE_PROMPT)
    end

    it "updates a row still holding an earlier seed's text, create-only seeds included" do
      seed_all!
      age!("strategic-planner", description: content.previous("strategic-planner")[:description].first)
      age!("rag-reranker", description: content.previous("rag-reranker")[:description].first)

      seed_all!

      expect(global("strategic-planner").description).to eq(content.description("strategic-planner"))
      expect(global("rag-reranker").description).to eq(content.description("rag-reranker"))
    end

    it "keeps an operator's edits across a re-seed, including the utility prompt it used to overwrite" do
      seed_all!
      global("research-analyst").update!(description: "Our own research agent.")
      judge = global("llm-judge")
      judge.update!(mcp_metadata: judge.mcp_metadata.merge("system_prompt" => "Our own rubric."))
      global("powernode-assistant").update!(description: "Our own concierge.")

      expect { seed_all! }.to output(/kept operator-edited description/).to_stdout

      expect(global("research-analyst").description).to eq("Our own research agent.")
      expect(global("llm-judge").mcp_metadata["system_prompt"]).to eq("Our own rubric.")
      expect(global("powernode-assistant").description).to eq("Our own concierge.")
    end

    it "keeps the concierge's stamps when its seed rebuilds mcp_metadata" do
      seed_all!
      load_seed!("ai_concierge_seed.rb")

      expect(global("powernode-assistant").mcp_metadata.dig(stamp_key, "system_prompt", "digest")).to be_present
    end
  end

  describe "the data migration" do
    let(:migration) { RefreshCanonicalAgentContent.new }

    before do
      seed_all!
      age!("prd-generator", description: content.previous("prd-generator")[:description].first)
      age!("intent-classifier", description: "An operator's intent classifier.")
      judge = global("llm-judge")
      judge.update_columns(mcp_metadata: judge.mcp_metadata.except(stamp_key)
                                               .merge("system_prompt" => content::LLM_JUDGE_PROMPT_JSON_ERA))
    end

    it "carries new text to unedited rows, skips the edited one, and reverts on down" do
      expect { migration.migrate(:up) }.to output(/intent-classifier: kept operator-edited description/).to_stdout

      expect(global("prd-generator").description).to eq(content.description("prd-generator"))
      expect(global("llm-judge").mcp_metadata["system_prompt"]).to eq(content::LLM_JUDGE_PROMPT)
      expect(global("intent-classifier").description).to eq("An operator's intent classifier.")

      expect { migration.migrate(:down) }.to output.to_stdout

      expect(global("prd-generator").description).to eq(content.previous("prd-generator")[:description].first)
      expect(global("llm-judge").mcp_metadata["system_prompt"]).to eq(content::LLM_JUDGE_PROMPT_JSON_ERA)
      expect(global("intent-classifier").description).to eq("An operator's intent classifier.")
    end
  end

  describe "persona prompts moved out of the manifest" do
    moved = MoveManifestPromptsToSystemPrompt::MOVED
    let(:migration) { MoveManifestPromptsToSystemPrompt.new }

    def plant_dead_prompt!(agent, text)
      manifest = agent.mcp_tool_manifest.merge("configuration" => { "system_prompt" => text, "temperature" => 0.3 })
      agent.update_columns(mcp_tool_manifest: manifest, mcp_metadata: agent.mcp_metadata.except("system_prompt", Ai::Agents::CanonicalContentRefresh::STAMP_KEY))
    end

    it "seeds the prompt where it is read and never into the manifest" do
      seed_all!

      moved.each do |slug|
        agent = global(slug)
        expect(agent.system_prompt).to eq(content.fields(slug)[:system_prompt]), slug
        expect(agent.mcp_tool_manifest.dig("configuration", "system_prompt")).to be_nil, slug
      end
    end

    it "fills the canonical prompt, moves a clone's text where it is read, and strips the dead key" do
      seed_all!
      moved.each { |slug| plant_dead_prompt!(global(slug), "old persona for #{slug}") }
      clone = create(:ai_agent, account: create(:account), name: "Planner (ours)")
      plant_dead_prompt!(clone, "our planner persona")

      expect { migration.migrate(:up) }.to output.to_stdout

      moved.each do |slug|
        agent = global(slug)
        expect(agent.system_prompt).to eq(content.fields(slug)[:system_prompt]), slug
        expect(agent.mcp_tool_manifest["configuration"]).to eq("temperature" => 0.3), slug
      end
      expect(clone.reload.system_prompt).to eq("our planner persona")
      expect(clone.mcp_tool_manifest["configuration"]).not_to have_key("system_prompt")

      expect { migration.migrate(:down) }.to output.to_stdout

      moved.each { |slug| expect(global(slug).system_prompt).to be_nil, slug }
      expect(global("prd-generator").description).to eq(content.description("prd-generator"))
    end
  end

  # Operator decision (2026-09-25): the five JSON pipeline workers stay out of
  # the Claude Code export through a per-agent flag the seed and the data
  # migration set, never a slug list in the exporter.
  describe "the claude_code_export flag" do
    pipeline_workers = %w[rag-reranker llm-judge intent-classifier prd-generator rag-query-engine]
    flag = Ai::ClaudeExport::AgentSkeletonSync::EXPORT_FLAG
    let(:migration) { ExcludePipelineWorkersFromClaudeExport.new }

    it "is declared in the content file for exactly the five pipeline workers" do
      flagged = content::AGENTS.keys.select { |slug| content.mcp_flags(slug)[flag] == false }

      expect(flagged).to match_array(pipeline_workers)
    end

    it "is set by the seed on the five workers and on no other seeded agent" do
      seed_all!

      pipeline_workers.each { |slug| expect(global(slug).mcp_metadata[flag]).to be(false), slug }
      expect(global("powernode-assistant").mcp_metadata).not_to have_key(flag)
    end

    it "keeps an operator's own value on re-seed" do
      seed_all!
      judge = global("llm-judge")
      judge.update_columns(mcp_metadata: judge.mcp_metadata.merge(flag => true))

      seed_all!

      expect(global("llm-judge").mcp_metadata[flag]).to be(true)
    end

    it "reaches rows seeded before the flag existed, keeps an operator's value, and reverts on down" do
      seed_all!
      pipeline_workers.each { |slug| a = global(slug); a.update_columns(mcp_metadata: a.mcp_metadata.except(flag)) }
      reranker = global("rag-reranker")
      reranker.update_columns(mcp_metadata: reranker.mcp_metadata.merge(flag => true))

      expect { migration.migrate(:up) }.to output.to_stdout

      (pipeline_workers - [ "rag-reranker" ]).each { |slug| expect(global(slug).mcp_metadata[flag]).to be(false), slug }
      expect(global("rag-reranker").mcp_metadata[flag]).to be(true)

      expect { migration.migrate(:down) }.to output.to_stdout

      (pipeline_workers - [ "rag-reranker" ]).each { |slug| expect(global(slug).mcp_metadata).not_to have_key(flag), slug }
      expect(global("rag-reranker").mcp_metadata[flag]).to be(true)
    end
  end
end
