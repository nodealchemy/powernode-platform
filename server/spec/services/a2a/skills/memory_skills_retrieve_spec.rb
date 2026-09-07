# frozen_string_literal: true

require "rails_helper"

# IMP-8bc3342afd14 — A2a::Skills::MemorySkills#retrieve raised on EVERY call,
# down both branches. The finding was filed as NoMethodError from calling
# `#search` / `#recent` on Ai::Memory::ContextInjectorService, which indeed has
# neither; running it shows it dies a step EARLIER, with
# `NameError: uninitialized constant A2a::Skills::MemorySkills::Memory`. The
# memory services are all `Ai::Memory::*` and there is no top-level Memory
# module, so `Memory::ContextInjectorService` never resolved from this
# namespace and the retriever was never constructed. Same conclusion — no input
# made the skill work — by a different mechanism than the one filed.
#
# It is not an internal helper. A2a::SkillRegistry declares
# handler: "A2a::Skills::MemorySkills.retrieve" (skill_registry.rb:217), so a
# federated PEER discovers memory.retrieve in the advertised catalog and gets an
# exception when it calls it — a dead capability advertised ACROSS A TRUST
# BOUNDARY rather than only internally.
#
# INVOKED THROUGH THE REGISTRY, not by calling the class. The defect is that the
# ADVERTISED skill is broken, so the descriptor's handler string is part of what
# is under test: these examples resolve and dispatch it exactly as
# A2a::MessageHandler#execute_skill does. Calling MemorySkills#retrieve directly
# would still pass if the descriptor pointed somewhere else entirely.
RSpec.describe "A2A memory.retrieve skill" do
  let(:account) { create(:account) }
  let(:agent) { create(:ai_agent, account: account) }
  # Real permissions, not a has_permission? stub. The users factory warns that
  # the FIRST user created in an account gets the OWNER role and every resource
  # permission, so a bare create(:user) is not an unprivileged actor — a stub
  # would have hidden that and made the negative examples below prove only that
  # the code path runs, not that the policy holds.
  let(:user) do
    create(:user, account: account, permissions: [ ::Ai::Tools::MemoryTool::REQUIRED_PERMISSION ])
  end

  # Resolve and dispatch the way A2a::MessageHandler#execute_skill does
  # (message_handler.rb:242-245), so the registered handler string is exercised.
  def invoke(input, as: user)
    skill = ::A2a::SkillRegistry.find_skill("memory.retrieve")
    raise "memory.retrieve is not registered" if skill.nil?

    handler_class, handler_method = skill[:handler].to_s.split(".")
    handler = handler_class.constantize.new(account: account, user: as)
    handler.public_send(handler_method, input, nil)
  end

  def returned_keys(result)
    Array(result[:output][:memories]).map { |m| m[:key] || m["key"] }.compact
  end

  def seed_stm!(key:, expired: false)
    create(
      :ai_agent_short_term_memory,
      account: account, agent: agent, session_id: "a2a-retrieve-spec",
      memory_key: key,
      memory_value: { data: "deployment runbook body for #{key}" },
      expires_at: expired ? 1.hour.ago : 1.hour.from_now
    )
  end

  describe "the registered descriptor" do
    it "is advertised and points at the handler under test" do
      skill = ::A2a::SkillRegistry.find_skill("memory.retrieve")

      expect(skill).to be_present
      expect(skill[:handler]).to eq("A2a::Skills::MemorySkills.retrieve")
    end
  end

  # THE ORACLE IS THE PRESENCE OF A SPECIFIC KEY, never a non-empty array and
  # never the absence of an exception. A rescue that swallowed NoMethodError
  # into [] would satisfy "did not raise" and "is an Array"; only naming the
  # row that must come back distinguishes a working retrieval from a silent
  # empty one.
  describe "with a query" do
    it "returns the matching memory" do
      seed_stm!(key: "deploy_runbook_live")

      result = invoke({ "agent_id" => agent.id, "query" => "deploy_runbook" })

      expect(returned_keys(result)).to include("deploy_runbook_live")
    end

    # The point of sequencing this after IMP-63da66a05a4f: routing through the
    # shared search seam means the expiry filter is INHERITED rather than
    # reimplemented here. If a future edit re-forks the query, this fails.
    it "withholds an expired short-term memory" do
      seed_stm!(key: "deploy_runbook_live")
      seed_stm!(key: "deploy_runbook_stale", expired: true)

      result = invoke({ "agent_id" => agent.id, "query" => "deploy_runbook" })

      keys = returned_keys(result)
      expect(keys).to include("deploy_runbook_live")
      expect(keys).not_to include("deploy_runbook_stale")
      expect(result[:output].to_json).not_to include("deploy_runbook_stale")
    end
  end

  describe "without a query" do
    it "returns recent memories" do
      seed_stm!(key: "deploy_runbook_live")

      result = invoke({ "agent_id" => agent.id })

      expect(returned_keys(result)).to include("deploy_runbook_live")
    end

    it "withholds an expired short-term memory" do
      seed_stm!(key: "deploy_runbook_live")
      seed_stm!(key: "deploy_runbook_stale", expired: true)

      keys = returned_keys(invoke({ "agent_id" => agent.id }))

      expect(keys).to include("deploy_runbook_live")
      expect(keys).not_to include("deploy_runbook_stale")
    end
  end

  # BOTH branches must answer the same principal the same way. The query
  # branch runs through Ai::Tools::MemoryTool, whose gate is live; the listing
  # branch reads model scopes directly and would happily serve a user the tool
  # had just refused. That split — refused for one phrasing of the question,
  # served for the other — is the thing these examples exist to forbid, and it
  # is not hypothetical: an earlier draft of this fix had exactly it.
  describe "a user without ai.agents.read" do
    let(:nobody) { create(:user, account: account, permissions: []) }

    before { seed_stm!(key: "deploy_runbook_live") }

    it "is refused on the query branch" do
      expect { invoke({ "agent_id" => agent.id, "query" => "deploy_runbook" }, as: nobody) }
        .to raise_error(/permission denied/)
    end

    it "is refused on the listing branch too, not quietly served" do
      expect { invoke({ "agent_id" => agent.id }, as: nobody) }
        .to raise_error(/permission denied/)
    end
  end

  # A federated peer arrives with no User at all. It is allowed through on
  # purpose — account scoping in #find_agent is its boundary — and pinning it
  # keeps a later "tighten the gate" edit from silently killing the skill for
  # the only principal that actually calls it.
  describe "a peer principal with no user" do
    before { seed_stm!(key: "deploy_runbook_live") }

    it "is served on the listing branch" do
      result = invoke({ "agent_id" => agent.id }, as: nil)

      expect(returned_keys(result)).to include("deploy_runbook_live")
    end

    # The QUERY branch specifically, because it is the only one that constructs
    # Ai::Tools::MemoryTool — and that construction passes `internal: true`,
    # which is both the riskiest line in the fix and the production default
    # (the A2A controller threads no user). An earlier draft covered only the
    # listing branch, leaving that line with no coverage at all.
    it "is served on the query branch, which is the one that builds the tool" do
      result = invoke({ "agent_id" => agent.id, "query" => "deploy_runbook" }, as: nil)

      expect(returned_keys(result)).to include("deploy_runbook_live")
    end
  end

  # A peer supplies `limit`. Unclamped it is whatever they send.
  describe "the peer-supplied limit" do
    before { seed_stm!(key: "deploy_runbook_live") }

    it "does not raise on a negative limit" do
      expect { invoke({ "agent_id" => agent.id, "limit" => -1 }) }.not_to raise_error
    end

    it "does not read a non-numeric limit as zero rows" do
      expect(returned_keys(invoke({ "agent_id" => agent.id, "limit" => "lots" })))
        .to include("deploy_runbook_live")
    end

    it "caps an absurd limit rather than honouring it" do
      expect(::A2a::Skills::MemorySkills::MAX_LIMIT).to be < 1_000_000
      expect { invoke({ "agent_id" => agent.id, "limit" => 1_000_000 }) }.not_to raise_error
    end
  end

  # Account scoping is the trust boundary this skill actually relies on —
  # find_agent resolves through @account.ai_agents — so it is pinned here
  # rather than assumed.
  describe "an agent in another account" do
    it "is not retrievable" do
      other_agent = create(:ai_agent, account: create(:account))

      expect { invoke({ "agent_id" => other_agent.id }) }
        .to raise_error(ActiveRecord::RecordNotFound)
    end
  end
end
