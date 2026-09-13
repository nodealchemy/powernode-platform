# frozen_string_literal: true

require "rails_helper"

# IMP-01a07d5a-17cd — the SIBLINGS of the retrieve defect
# (spec/services/a2a/skills/memory_skills_retrieve_spec.rb). #retrieve was
# repaired; #store and #inject were left naming the same unresolvable constant,
# so two of the three advertised memory skills still raised on every call:
#
#   NameError: uninitialized constant A2a::Skills::MemorySkills::Memory
#
# `Memory::StorageService` / `Memory::ContextInjectorService` never resolved
# from this namespace — the services are `Ai::Memory::*` and there is no
# top-level Memory module. Constant lookup from A2a::Skills::MemorySkills walks
# MemorySkills -> Skills -> A2a -> Object and finds no `Memory` at any step.
#
# ADVERTISED ACROSS A TRUST BOUNDARY, which is why this is not an internal
# helper bug: A2a::SkillRegistry declares handler strings for all three
# (skill_registry.rb), so a federated peer discovers memory.store and
# memory.inject in the catalog and gets an exception when it calls them.
#
# Dispatched THROUGH THE REGISTRY exactly as A2a::MessageHandler#execute_skill
# does, so the descriptor's handler string is part of what is under test —
# calling the class directly would still pass if the descriptor pointed
# elsewhere.
RSpec.describe "A2A memory.store and memory.inject skills" do
  let(:account) { create(:account) }
  let(:agent) { create(:ai_agent, account: account) }

  # Real permissions, not a has_permission? stub — the users factory gives the
  # FIRST user in an account the OWNER role and every resource permission, so a
  # bare create(:user) is not an unprivileged actor and a stub would hide that.
  let(:writer) do
    create(:user, account: account,
                  permissions: [ "ai.memory.write", ::Ai::Tools::MemoryTool::REQUIRED_PERMISSION ])
  end

  def invoke(skill_id, input, as: writer)
    invoke_with_task(skill_id, input, nil, as: as)
  end

  # The second positional argument is the Ai::A2aTask A2a::MessageHandler
  # #execute_skill supplies (message_handler.rb:245); most examples pass nil
  # because a direct invocation has none.
  def invoke_with_task(skill_id, input, task, as: writer)
    skill = ::A2a::SkillRegistry.find_skill(skill_id)
    raise "#{skill_id} is not registered" if skill.nil?

    handler_class, handler_method = skill[:handler].to_s.split(".")
    handler_class.constantize.new(account: account, user: as).public_send(handler_method, input, task)
  end

  describe "the registered descriptors" do
    it "advertise both handlers under test" do
      expect(::A2a::SkillRegistry.find_skill("memory.store")[:handler])
        .to eq("A2a::Skills::MemorySkills.store")
      expect(::A2a::SkillRegistry.find_skill("memory.inject")[:handler])
        .to eq("A2a::Skills::MemorySkills.inject")
    end

    # The enum advertised what the code could not do: "procedural" was offered
    # to peers and silently stored as a FACT, because #store branches on
    # "experiential" and treats everything else as factual. A declared option
    # that quietly does something else is the same defect class as a dead
    # skill, so the advertisement was narrowed to what is implemented.
    it "advertise only the memory types store actually implements" do
      enum = ::A2a::SkillRegistry.find_skill("memory.store")
                                 .dig(:input_schema, :properties, :memory_type, :enum)

      expect(enum).to contain_exactly("factual", "experiential")
    end
  end

  # THE ORACLE IS A PERSISTED ROW, never "did not raise". A rescue that
  # swallowed the NameError and returned a stub hash would satisfy "returns
  # success"; only reading the record back distinguishes a working store.
  describe "memory.store" do
    it "persists a factual memory and returns its id" do
      result = invoke("memory.store", {
        "agent_id" => agent.id, "memory_type" => "factual",
        "key" => "deploy_runbook", "content" => { "steps" => "drain, deploy, verify" }
      })

      expect(result[:output][:success]).to be(true)
      entry = ::Ai::ContextEntry.find(result[:output][:memory_id])
      expect(entry.entry_key).to eq("deploy_runbook")
      expect(entry.memory_type).to eq("factual")
    end

    it "persists an experiential memory and returns its id" do
      result = invoke("memory.store", {
        "agent_id" => agent.id, "memory_type" => "experiential",
        "content" => { "outcome" => "rollback succeeded" }, "context" => { "run" => 7 }
      })

      entry = ::Ai::ContextEntry.find(result[:output][:memory_id])
      expect(entry.memory_type).to eq("experiential")
    end

    # store_fact's update branch returns a DIFFERENT record than the create
    # branch (ContextEntry#update_content archives and re-creates), so a second
    # store of the same key must still answer with a resolvable id.
    it "returns a resolvable id when re-storing an existing key" do
      invoke("memory.store", { "agent_id" => agent.id, "key" => "k", "content" => { "v" => 1 } })
      result = invoke("memory.store", { "agent_id" => agent.id, "key" => "k", "content" => { "v" => 2 } })

      expect { ::Ai::ContextEntry.find(result[:output][:memory_id]) }.not_to raise_error
    end

    it "refuses a user without ai.memory.write" do
      nobody = create(:user, account: account, permissions: [])

      expect { invoke("memory.store", { "agent_id" => agent.id, "content" => { "a" => 1 } }, as: nobody) }
        .to raise_error(/permission denied/)
    end

    # A federated peer arrives with no User at all; allowed through on purpose
    # (account scoping in #find_agent is the boundary that applies), pinned so a
    # later "tighten the gate" edit cannot silently kill the only principal that
    # actually calls this.
    it "serves a peer principal with no user" do
      result = invoke("memory.store", { "agent_id" => agent.id, "content" => { "a" => 1 } }, as: nil)

      expect(result[:output][:success]).to be(true)
    end

    it "does not reach an agent in another account" do
      other = create(:ai_agent, account: create(:account))

      expect { invoke("memory.store", { "agent_id" => other.id, "content" => { "a" => 1 } }) }
        .to raise_error(ActiveRecord::RecordNotFound)
    end
  end

  describe "memory.inject" do
    it "returns a built context" do
      invoke("memory.store", {
        "agent_id" => agent.id, "key" => "deploy_runbook",
        "content" => { "steps" => "drain, deploy, verify" }
      })

      result = invoke("memory.inject", { "agent_id" => agent.id, "task" => { "description" => "deploy" } })

      expect(result[:output][:context]).to include(:context, :token_estimate, :breakdown)
    end

    # THE PRODUCTION PATH, and the one the repair turns on. A2a::MessageHandler
    # #execute_skill passes the Ai::A2aTask RECORD as the second positional
    # argument (message_handler.rb:245); every task reader inside the injector
    # (WorkingMemoryService#context_id's `@task.id`, #extract_task_query's
    # `task.message`, #task_relevance_boost's `task.metadata`) requires a record
    # and raises NoMethodError on the Hash the skill used to pass instead.
    # Invoking with `as: nil, task: <record>` is exactly the shape a federated
    # peer produces.
    it "accepts the A2aTask record the handler passes, not just a nil task" do
      record = create(:ai_a2a_task, account: account,
                                    message: { "role" => "user",
                                               "parts" => [ { "type" => "text", "text" => "deploy runbook" } ] })

      result = invoke_with_task("memory.inject", { "agent_id" => agent.id, "task" => {} }, record, as: nil)

      expect(result[:output][:context]).to include(:context, :token_estimate, :breakdown)
    end

    it "refuses a user without ai.agents.read" do
      nobody = create(:user, account: account, permissions: [])

      expect { invoke("memory.inject", { "agent_id" => agent.id, "task" => {} }, as: nobody) }
        .to raise_error(/permission denied/)
    end

    it "serves a peer principal with no user" do
      expect { invoke("memory.inject", { "agent_id" => agent.id, "task" => {} }, as: nil) }.not_to raise_error
    end

    # token_budget is peer-supplied and multiplied into a character budget. A
    # huge value is a memory-pressure lever on a federation-facing path; the
    # same clamping discipline #retrieve applies to `limit`.
    describe "the peer-supplied token_budget" do
      it "caps an absurd budget rather than honouring it" do
        expect(::A2a::Skills::MemorySkills::MAX_TOKEN_BUDGET).to be < 1_000_000

        expect(::Ai::Memory::ContextInjectorService).to receive(:new).and_wrap_original do |orig, **kwargs|
          service = orig.call(**kwargs)
          expect(service).to receive(:build_context)
            .with(hash_including(token_budget: ::A2a::Skills::MemorySkills::MAX_TOKEN_BUDGET))
            .and_call_original
          service
        end

        invoke("memory.inject", { "agent_id" => agent.id, "task" => {}, "token_budget" => 1_000_000 })
      end

      it "does not read a non-numeric budget as zero" do
        expect { invoke("memory.inject", { "agent_id" => agent.id, "task" => {}, "token_budget" => "lots" }) }
          .not_to raise_error
      end
    end

    it "does not reach an agent in another account" do
      other = create(:ai_agent, account: create(:account))

      expect { invoke("memory.inject", { "agent_id" => other.id, "task" => {} }) }
        .to raise_error(ActiveRecord::RecordNotFound)
    end
  end
end
