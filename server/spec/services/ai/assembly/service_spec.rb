# frozen_string_literal: true

require "rails_helper"

# assemble_task (skills-first agents, PRE-2): the minimal assembler. A task and
# an agent slug in; the skills that own the task, the learnings those skills
# carry, and the tier / model / effort to run at out; one durable record per
# call on ai_routing_decisions (request_type "task_assembly"), fetched back
# idempotently by assembly_id.
RSpec.describe Ai::Assembly::Service, type: :service do
  let!(:account) { create(:account) }
  let(:core_seed) { Rails.root.join("db", "seeds", "ai_capability_skills_seed.rb") }
  let(:dev_task) { "Work a dev-improve task that adds a migration and a spec" }
  let(:review_task) { "Review this campaign increment against its acceptance criteria" }
  let(:onboard_task) { "Help me onboard: I want to set up Powernode for my team" }

  before do
    use_recorded_skill_embeddings!
    seed_with_baseline!(core_seed, *extension_capability_seed_paths)
  end

  def assemble(task, agent_slug: "platform-engineer", context: "claude_code", **extra)
    described_class.new(account: account).call(task: task, agent_slug: agent_slug, context: context, **extra)
  end

  def slugs_of(result) = result[:skills].map { |s| s[:slug] }

  describe "candidates" do
    it "returns the skills that own the task, each with its prompt and verb manifest, at most five" do
      result = assemble(dev_task)

      expect(slugs_of(result) & %w[dev-loop-execution rails-backend-conventions test-authoring]).not_to be_empty
      expect(result[:skills].size).to be <= 5
      result[:skills].each do |skill|
        expect(skill).to include(:slug, :name, :system_prompt, :manifest, :score)
        expect(skill[:system_prompt]).to be_present
        expect(skill[:manifest]).to include("verbs")
      end
    end

    it "stays inside the agent's domain ceiling: the reviewer never gets front-door skills, the concierge no platform-dev skills" do
      reviewer = assemble(onboard_task, agent_slug: "platform-reviewer")
      concierge = assemble(dev_task, agent_slug: "powernode-concierge")

      domains = ->(result) { Ai::Skill.global.where(slug: slugs_of(result)).map { |s| s.metadata["domain"] } }
      expect(domains.call(reviewer) - %w[review knowledge]).to be_empty
      expect(domains.call(concierge) - %w[front-door knowledge external-agent-session]).to be_empty
    end

    it "closes over `requires`: a required skill rides along with the skill that needs it" do
      needing = Ai::Skill.global.where(Arel.sql("jsonb_array_length(coalesce(metadata->'relations'->'requires','[]'::jsonb)) > 0")).first
      skip "no seeded skill declares requires" unless needing
      required = needing.metadata.dig("relations", "requires").first
      allow_any_instance_of(Ai::SkillGraph::TraversalService).to receive(:traverse).and_return(
        discovered_skills: [ { skill_id: needing.id, slug: needing.slug, score: 0.9, depth: 0 } ]
      )

      result = assemble("anything", agent_slug: "platform-engineer")

      expect(slugs_of(result)).to include(needing.slug, required)
      expect(result[:skills].find { |s| s[:slug] == required }[:via]).to eq("requires")
    end

    it "gives a read-only role only read-only skills: a mutating skill is neither a candidate nor pulled in by `requires`" do
      reviewer = Ai::Agents::CanonicalRoster.fetch("platform-reviewer")
      expect(reviewer[:role][:read_only]).to be(true)
      mutating = Ai::Skill.global.where(Arel.sql("metadata->'manifest'->>'read_only' = 'false'"))
                          .find { |s| reviewer[:domains].include?(s.metadata["domain"]) }
      readonly = Ai::Skill.global.find_by!(slug: "acceptance-criteria-review")
      expect(mutating).to be_present
      readonly.update_columns(metadata: readonly.metadata.merge("relations" => (readonly.metadata["relations"] || {}).merge("requires" => [ mutating.slug ])))
      allow_any_instance_of(Ai::SkillGraph::TraversalService).to receive(:traverse).and_return(
        discovered_skills: [ { skill_id: readonly.id, slug: readonly.slug, score: 0.9, depth: 0 }, { skill_id: mutating.id, slug: mutating.slug, score: 0.8, depth: 0 } ]
      )

      result = assemble("anything", agent_slug: "platform-reviewer")

      expect(slugs_of(result)).to eq([ "acceptance-criteria-review" ])
      engineer = assemble("anything", agent_slug: "platform-engineer")
      expect(slugs_of(engineer)).to include(mutating.slug)
    end

    it "reports an uncovered task instead of guessing, and falls back to the roster tier" do
      result = assemble("bake a chocolate cake with raspberries for grandma")

      expect(result[:skills]).to eq([])
      expect(result[:uncovered]).not_to be_empty
      expect(result).to include(tier: "standard", model: "sonnet", effort: "medium")
    end
  end

  describe "tier, model and effort" do
    let(:skill) { Ai::Skill.global.find_by!(slug: slugs_of(assemble(dev_task)).first) }

    def set_hints!(slug, **hints)
      row = Ai::Skill.global.find_by!(slug: slug)
      row.update_columns(metadata: row.metadata.merge("hints" => row.metadata["hints"].merge(hints.transform_keys(&:to_s))))
    end

    it "never lowers below the roster tier: a reasoning agent with light-hinted skills stays reasoning" do
      result = assemble(review_task, agent_slug: "platform-reviewer")

      expect(result[:tier]).to eq("reasoning")
      expect(result[:model]).to eq("opus")
    end

    it "raises to the highest skill hint (min_tier and effort), naming the skill in floor_reason" do
      first = slugs_of(assemble(dev_task)).first
      set_hints!(first, min_tier: "reasoning", effort: "high")

      result = assemble(dev_task)

      expect(result).to include(tier: "reasoning", model: "opus", effort: "high")
      expect(result[:floor_reason]).to include("skill hint").and include(first)
    end

    it "raises to reasoning/high when a manifest verb is gated (verb risk), independent of the hints" do
      gated = Ai::Assembly::VerbRisk.new.gated_verbs(
        Ai::Tools::PlatformApiToolRegistry.all_tools.keys.map(&:to_s)
      ).reject { |v| v.start_with?("system_") }.first
      skip "no gated core verb registered" unless gated
      first = slugs_of(assemble(dev_task)).first
      row = Ai::Skill.global.find_by!(slug: first)
      row.update_columns(metadata: row.metadata.merge(
        "hints" => row.metadata["hints"].merge("min_tier" => "standard", "effort" => "medium"),
        "manifest" => row.metadata["manifest"].merge("verbs" => [ gated ], "gate_category" => "mutate", "read_only" => false)
      ))

      result = assemble(dev_task)

      expect(result).to include(tier: "reasoning", model: "opus", effort: "high")
      expect(result[:floor_reason]).to include("verb risk").and include(gated)
    end

    it "does not count an approval-parking probe under a skill that attests gate_category read, but still counts a destructive verb" do
      risk = Ai::Assembly::VerbRisk.new
      destructive = Ai::Tools::PlatformApiToolRegistry.all_tools.keys.map(&:to_s).find { |v| risk.gated?(v, parking: false) }
      parking = Ai::Tools::PlatformApiToolRegistry.all_tools.keys.map(&:to_s).find { |v| risk.gated?(v) && !risk.gated?(v, parking: false) }
      skip "no destructive or parking verb registered" unless destructive && parking
      first = slugs_of(assemble(dev_task)).first
      row = Ai::Skill.global.find_by!(slug: first)
      read_manifest = row.metadata["manifest"].merge("gate_category" => "read", "read_only" => true)
      hints = row.metadata["hints"].merge("min_tier" => "standard", "effort" => "medium")

      row.update_columns(metadata: row.metadata.merge("hints" => hints, "manifest" => read_manifest.merge("verbs" => [ parking ])))
      calm = assemble(dev_task)
      expect(calm[:skills].first[:slug]).to eq(first)
      expect(calm[:floor_reason]).not_to include("verb risk")

      row.update_columns(metadata: row.metadata.merge("manifest" => read_manifest.merge("verbs" => [ parking, destructive ])))
      expect(assemble(dev_task)[:floor_reason]).to include("verb risk").and include(destructive)
    end

    it "maps tiers to the Claude Code models for context claude_code, and returns no model for the platform context" do
      expect(Ai::Assembly::Service::CLAUDE_CODE_MODELS).to eq("light" => "haiku", "standard" => "sonnet", "reasoning" => "opus", "frontier" => "fable")

      platform = assemble(dev_task, context: "platform")
      expect(platform[:model]).to be_nil
      expect(platform[:tier]).to be_present
    end

    it "only ever returns an effort the Agent tool accepts" do
      expect(%w[low medium high xhigh max]).to include(assemble(dev_task)[:effort])
    end
  end

  describe "learnings" do
    it "selects active learnings tagged with a selected skill's tags or knowledge tags, and nothing else" do
      first = Ai::Skill.global.find_by!(slug: slugs_of(assemble(dev_task)).first)
      tag = first.tags.first
      other_account = create(:account)
      mine = create(:ai_compound_learning, account: account, status: "active", tags: [ tag ], title: "mine")
      create(:ai_compound_learning, account: account, status: "active", tags: [ "unrelated-tag-xyz" ], title: "unrelated")
      create(:ai_compound_learning, account: account, status: "deprecated", tags: [ tag ], title: "retired")
      create(:ai_compound_learning, account: other_account, status: "active", tags: [ tag ], title: "theirs")

      result = assemble(dev_task)

      expect(result[:learnings].map { |l| l[:title] }).to eq([ "mine" ])
      expect(result[:learnings].first).to include(id: mine.id)
      expect(result[:knowledge_tags]).to include(tag)
    end
  end

  describe "the record" do
    it "persists one RoutingDecision with request_type task_assembly and returns its id as assembly_id" do
      expect { @result = assemble(dev_task) }.to change { Ai::RoutingDecision.where(request_type: "task_assembly").count }.by(1)

      decision = Ai::RoutingDecision.find(@result[:assembly_id])
      expect(@result[:routing_decision_id]).to eq(decision.id)
      expect(decision).to have_attributes(account_id: account.id, request_type: "task_assembly", model_tier: @result[:tier])
      expect(decision.request_metadata).to include("agent_slug" => "platform-engineer", "context" => "claude_code",
                                                   "model" => @result[:model], "effort" => @result[:effort])
      expect(decision.request_metadata["selected"].map { |s| s["slug"] }).to eq(slugs_of(@result))
    end

    it "stores slugs and a content hash, not the skills' prompts, manifests or learning text" do
      result = assemble(dev_task)
      stored = Ai::RoutingDecision.find(result[:assembly_id]).request_metadata

      expect(stored["selected"]).to all(satisfy { |s| (s.keys - %w[slug name score via content_hash]).empty? && s["content_hash"].present? })
      expect(stored["selected"].map { |s| s["slug"] }).to eq(slugs_of(result))
      expect(stored["learnings"]).to all(be_a(String)) # ids only
      expect(stored.to_json).not_to include(result[:skills].first[:system_prompt][0, 40])
    end

    it "is idempotent by assembly_id: the same assembly comes back, re-read by slug, and no row is added" do
      first = assemble(dev_task)

      again = nil
      expect { again = assemble(nil, agent_slug: "platform-engineer", assembly_id: first[:assembly_id]) }
        .not_to change(Ai::RoutingDecision, :count)

      expect(again[:assembly_id]).to eq(first[:assembly_id])
      expect(slugs_of(again)).to eq(slugs_of(first))
      expect(again[:skills].map { |s| s[:system_prompt] }).to eq(first[:skills].map { |s| s[:system_prompt] })
      expect(again.slice(:tier, :model, :effort)).to eq(first.slice(:tier, :model, :effort))
      expect(again[:skills]).to all(include(content_changed: false))
    end

    it "serves the CURRENT prompt on fetch and flags a skill whose content changed since the assembly" do
      first = assemble(dev_task)
      changed = Ai::Skill.global.find_by!(slug: slugs_of(first).first)
      changed.update_columns(system_prompt: "## Procedure\n1. changed after the fact")

      again = assemble(nil, agent_slug: "platform-engineer", assembly_id: first[:assembly_id])

      expect(again[:skills].first).to include(system_prompt: "## Procedure\n1. changed after the fact", content_changed: true)
    end

    it "reports a skill that no longer exists instead of failing the fetch" do
      first = assemble(dev_task)
      Ai::Skill.global.where(slug: slugs_of(first).first).update_all(slug: "renamed-away")

      again = assemble(nil, agent_slug: "platform-engineer", assembly_id: first[:assembly_id])

      expect(again[:skills].first).to include(slug: slugs_of(first).first, missing: true)
    end

    it "refuses an assembly_id from another account, an unknown one, an unknown agent and a blank task" do
      theirs = described_class.new(account: create(:account)).call(task: dev_task, agent_slug: "platform-engineer", context: "claude_code")

      expect { assemble(nil, assembly_id: theirs[:assembly_id]) }.to raise_error(described_class::Refusal, /assembly/i)
      expect { assemble(nil, assembly_id: SecureRandom.uuid) }.to raise_error(described_class::Refusal, /assembly/i)
      expect { assemble(dev_task, agent_slug: "platform-developer") }.to raise_error(described_class::Refusal, /agent_slug/)
      expect { assemble("  ") }.to raise_error(described_class::Refusal, /task/)
      expect { assemble(dev_task, context: "elsewhere") }.to raise_error(described_class::Refusal, /context/)
    end
  end
end
