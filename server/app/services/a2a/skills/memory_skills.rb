# frozen_string_literal: true

module A2a
  module Skills
    # MemorySkills - A2A skill implementations for agent memory operations
    class MemorySkills
      DEFAULT_LIMIT = 10
      MAX_LIMIT = 100
      DEFAULT_TOKEN_BUDGET = 2000
      MAX_TOKEN_BUDGET = 8000

      # The memory tiers Ai::Memory::StorageService actually implements. The
      # registry descriptor advertises exactly this list; #store refuses
      # anything else rather than absorbing it into the factual branch.
      MEMORY_TYPES = %w[factual experiential].freeze

      # The WRITE floor, taken from the same map Ai::Tools::MemoryTool resolves
      # its mutating actions against (ACTION_PERMISSIONS: write_shared_memory /
      # delete_shared_memory / consolidate_memory all sit on "ai.memory.write"),
      # so a peer that may READ memory cannot also WRITE it by reaching for a
      # different skill. Spelled as a constant here because the tool exposes the
      # map but no accessor for a single entry.
      WRITE_PERMISSION = "ai.memory.write"

      def initialize(account:, user: nil)
        @account = account
        @user = user
      end

      # Store memory
      #
      # Same defect as #retrieve carried (IMP-8bc3342afd14), left behind when
      # that one was repaired: `Memory::StorageService` does not resolve from
      # this namespace. Constant lookup walks MemorySkills -> Skills -> A2a ->
      # Object and finds no `Memory` at any step, because the services are all
      # `Ai::Memory::*` and there is no top-level Memory module. Every call
      # raised NameError before touching a database.
      #
      # `memory_type` is now CLOSED rather than open-with-a-fallthrough. The
      # advertised enum offered "procedural", which this branch silently stored
      # as a FACT — an option a peer can select that quietly does something
      # else is the same defect class as a dead skill, so the registry
      # descriptor was narrowed to the two types that exist and anything else
      # is refused here rather than absorbed. Refusing is safe: the federation
      # population is empty, so no peer has ever sent the third value.
      def store(input, task = nil)
        agent = find_agent(input["agent_id"])
        memory_type = (input["memory_type"].presence || "factual").to_s
        authorize!(WRITE_PERMISSION)

        unless MEMORY_TYPES.include?(memory_type)
          raise ArgumentError, "memory_type must be one of #{MEMORY_TYPES.join(', ')}, got #{memory_type.inspect}"
        end

        storage = ::Ai::Memory::StorageService.new(account: @account, agent: agent)

        memory =
          if memory_type == "experiential"
            storage.store_experiential(
              content: input["content"],
              context: input["context"] || {}
            )
          else
            storage.store_fact(
              key: input["key"] || "fact_#{Time.current.to_i}",
              value: input["content"],
              metadata: input["context"] || {}
            )
          end

        {
          output: {
            memory_id: memory.id,
            success: true,
            memory_type: memory_type
          }
        }
      end

      # Retrieve memories
      #
      # Every call to this skill used to raise (IMP-8bc3342afd14), down BOTH
      # branches, and it failed a step earlier than "wrong method": `Memory::`
      # does not resolve from this namespace — the services live under
      # `Ai::Memory::` and there is no top-level Memory module — so it died
      # constructing the retriever, before reaching the #search / #recent calls
      # that Ai::Memory::ContextInjectorService also does not have. That class's
      # whole public surface is build_context / build_query_context /
      # build_minimal_context / preview_context.
      #
      # It matters because the skill is ADVERTISED: A2a::SkillRegistry declares
      # it (skill_registry.rb:217), so a federated peer discovers memory.retrieve
      # in the catalog and gets an exception when it calls it.
      #
      # Both branches now route through EXISTING seams rather than growing new
      # ones — the tiered keyword search behind Ai::Tools::MemoryTool, and the
      # model scopes RouterService reads short-term memory through. The point of
      # reusing rather than reimplementing is that both inherit the `active`
      # expiry filter (IMP-63da66a05a4f) automatically; a hand-written query
      # here would have to remember it, and would drift the first time it did
      # not.
      def retrieve(input, task = nil)
        agent = find_agent(input["agent_id"])
        limit = clamped_limit(input["limit"])
        authorize_memory_read!

        memories =
          if input["query"].present?
            search_memories(agent: agent, query: input["query"], limit: limit)
          else
            recent_memories(agent: agent, limit: limit)
          end

        {
          output: {
            memories: memories
          }
        }
      end

      # Inject memory context
      #
      # Third instance of the unresolvable-constant defect above:
      # `Memory::ContextInjectorService` never resolved, so a peer asking for
      # injected context got a NameError. The service exists as
      # `Ai::Memory::ContextInjectorService`.
      #
      # FIXING THE CONSTANT EXPOSED A SECOND DEFECT UNDERNEATH, which is why
      # this method does more than swap a namespace. The old body passed
      # `input["task"]` — the peer's JSON object — as `task:`. Every consumer of
      # that argument inside the injector treats it as an A2A TASK RECORD:
      # #inject_working_memory hands it to WorkingMemoryService, which calls
      # `@task.id` (working_memory_service.rb:255); #extract_task_query reads
      # `task.message["parts"]`; #task_relevance_boost reads `task.metadata`.
      # A Hash answers none of those, so the repaired skill would have traded
      # NameError for `NoMethodError: undefined method 'id' for {}:Hash` — a
      # dead skill that now fails one layer deeper, which is worse, because it
      # looks fixed.
      #
      # The record was already in hand and was being thrown away: A2a::
      # MessageHandler#execute_skill passes the Ai::A2aTask as the SECOND
      # POSITIONAL ARGUMENT (message_handler.rb:245), the `task` parameter this
      # method has always declared and never used.
      #
      # So BOTH inputs are now used, each as what it actually is:
      #   task:  the Ai::A2aTask record (nil when invoked outside the handler —
      #          every `.id` / `.message` / `.metadata` reader inside the
      #          injector is already nil-guarded).
      #   query: text derived from the peer's `input["task"]` object, so the
      #          payload the descriptor advertises is HONOURED rather than
      #          silently dropped. Without this the peer's task description
      #          would stop influencing the result at all, which is a quieter
      #          way of staying broken.
      #
      # The returned value is build_context's whole hash
      # ({context:, token_estimate:, breakdown:}) — the descriptor advertises
      # `context` as an object, and the token accounting is what tells a caller
      # whether the budget it asked for was actually spent.
      def inject(input, task = nil)
        agent = find_agent(input["agent_id"])
        authorize!(::Ai::Tools::MemoryTool::REQUIRED_PERMISSION)

        injector = ::Ai::Memory::ContextInjectorService.new(agent: agent, account: @account)

        context = injector.build_context(
          task: task,
          query: query_from_peer_task(input),
          token_budget: clamped_token_budget(input["token_budget"])
        )

        {
          output: {
            context: context
          }
        }
      end

      private

      def find_agent(id)
        @account.ai_agents.find(id)
      end

      # ONE gate for BOTH branches, applied before either runs.
      #
      # Without it the two branches disagree: the query branch goes through
      # Ai::Tools::MemoryTool, whose gate is live (an unpermissioned user gets
      # "permission denied: ai.agents.read required" — verified by execution,
      # not read off the ladder), while the listing branch reads model scopes
      # directly and would answer that same user in full. A caller refused one
      # phrasing of a question and served the other is worse than either
      # policy on its own.
      #
      # The permission NAME comes from the tool rather than being spelled
      # here, so the two cannot drift; search_memory is absent from that
      # tool's ACTION_PERMISSIONS map, so its floor is the class constant.
      #
      # STATED PLAINLY BECAUSE IT WOULD OTHERWISE READ AS PROTECTION IT DOES
      # NOT YET PROVIDE: @user is nil on every production path today, so this
      # check is currently INERT. Api::V1::A2aController builds
      # A2a::MessageHandler.new(account: account) with no user (a2a_controller.rb
      # :70 and :104), and authenticate_jwt_token resolves a real User only to
      # return user&.account, discarding the identity it just proved. Filed
      # separately; when the user is threaded through, this starts refusing
      # without further change. A nil user is let through on purpose in the
      # meantime — the account scoping in #find_agent is the boundary that
      # actually applies, and it is the same posture as every other skill in
      # this directory, none of which check a permission at all.
      # PARAMETERISED so the three skills do not share a single floor: reading
      # memory and WRITING it are different authorities, and #store taking the
      # read permission would have let any peer that may look also mutate.
      def authorize!(permission)
        return if @user.nil?
        return if @user.has_permission?(permission) == true

        raise "permission denied: #{permission} required"
      end

      def authorize_memory_read!
        authorize!(::Ai::Tools::MemoryTool::REQUIRED_PERMISSION)
      end

      # The same clamping discipline #clamped_limit applies, for the same
      # reason: token_budget is peer-supplied and is multiplied into a
      # CHARACTER budget inside build_context, so an unclamped value is a
      # memory-pressure lever on a federation-facing path. A non-numeric string
      # becomes 0 through #to_i, which would silently build an EMPTY context
      # that reads like "this agent knows nothing" — so 0 falls back to the
      # default rather than being honoured.
      # Searchable text out of the peer's `task` object, mirroring
      # Ai::Memory::ContextInjectorService#extract_task_query's reading of the
      # A2A message shape ({"parts" => [{"type" => "text", "text" => ...}]}) and
      # falling back to the plain description/text keys a peer is as likely to
      # send. Truncated to the same 200 chars that method uses. Returns nil when
      # there is nothing to search on, so build_context's `query.present?`
      # section gates behave exactly as they do for a record-only call.
      def query_from_peer_task(input)
        explicit = input["query"]
        return explicit.to_s.truncate(200) if explicit.present?

        payload = input["task"]
        return nil unless payload.is_a?(Hash)

        parts = Array(payload.dig("message", "parts") || payload["parts"])
        text = parts.select { |part| part.is_a?(Hash) && part["type"] == "text" }
                    .map { |part| part["text"] }.compact.join(" ")
        text = [ payload["description"], payload["text"] ].compact.join(" ") if text.blank?

        text.presence&.truncate(200)
      end

      def clamped_token_budget(raw)
        value = raw.to_i
        return DEFAULT_TOKEN_BUDGET unless value.positive?

        [ value, MAX_TOKEN_BUDGET ].min
      end

      # A peer-supplied bound, clamped. Unclamped, "limit" is whatever a
      # federated caller sends: 1_000_000 is a legal integer, a non-numeric
      # string silently becomes 0 (an empty result that looks like "no
      # memories"), and a negative raises out of .limit.
      def clamped_limit(raw)
        value = raw.to_i
        return DEFAULT_LIMIT unless value.positive?

        [ value, MAX_LIMIT ].min
      end

      # The tiered keyword search the MCP memory tool already exposes. Reused
      # rather than reimplemented so this path cannot fork from it — in
      # particular the `active` filter that keeps EXPIRED SHORT-TERM rows out
      # of a result handed to a peer (IMP-63da66a05a4f).
      #
      # Two things that scope buys and two it does not, because the obvious
      # reading of "tiered search" is wrong on both:
      #   - the result also carries a LONG-TERM tier (Ai::CompoundLearning).
      #     Its `.active` is a STATUS filter, not an expiry one — that model
      #     has no expiry concept — so "inherits the expiry filter" is true of
      #     the short-term half only.
      #   - the long-term half is scoped by ACCOUNT, not by agent
      #     (memory_tool.rb filters on account: and does not use the resolved
      #     agent for that query), so a query-branch answer is wider than the
      #     agent-scoped listing branch. Pre-existing in the tool; filed
      #     separately rather than forked around here.
      #
      # `internal: true` is passed EXPLICITLY and unconditionally, never
      # inferred from `@user.nil?`. An earlier draft of this method wrote
      # `internal: @user.nil?`, which is precisely the bypass BaseTool
      # documents against at base_tool.rb:384-390: a nil user does not mean
      # "internal", because an mTLS instance principal also arrives without
      # one, and tools that inferred it "silently handed those principals
      # every per-action permission" (IMP-9030413bc292). Reintroducing that
      # inference here would have re-opened it on a federation-facing path.
      #
      # Explicit is correct for what this actually is — a skill executor
      # running without a user, which is the case BaseTool's own comment names
      # as the legitimate one. The tool is used here as a QUERY SEAM, not as
      # the authorization boundary; authorization is authorize_memory_read!
      # above plus the account scoping in #find_agent.
      def search_memories(agent:, query:, limit:)
        tool = ::Ai::Tools::MemoryTool.new(
          account: @account, agent: agent, user: @user, internal: true
        )

        result = tool.execute(
          params: { action: "search_memory", query: query, limit: limit }
        )

        # Surfaced, never swallowed into []. A refusal and "this agent has no
        # matching memories" are different answers, and returning [] for both
        # is how a dead capability looks healthy — which is the defect class
        # this task belongs to.
        raise "memory search failed: #{result[:error]}" unless result[:success]

        Array(result[:results])
      end

      # No query: the most recent live short-term rows, through the same model
      # scopes Ai::Memory::RouterService reads them with. `.active` is the
      # inherited expiry filter; `.recent` is the model's own ordering, which
      # is last_accessed_at DESC — most recently READ, not most recently
      # written, since touch_access! moves that column.
      def recent_memories(agent:, limit:)
        ::Ai::AgentShortTermMemory
          .active
          .for_agent(agent.id)
          .recent
          .limit(limit)
          .map { |memory| short_term_entry(memory) }
      end

      # Deliberately the SAME shape the tiered search emits for a SHORT-TERM
      # hit, so a caller does not have to branch on which path answered it.
      # Long-term hits from the query branch are a different shape
      # ({tier:, content:, category:, created_at:} — no key, no value); the
      # registry advertises `memories` as an untyped array, so both conform.
      # (This replaces a `memory_summary` helper that read memory_type /
      # content / importance off the row — fields no memory model on either
      # path actually has. It was only ever reachable through the raising
      # code above, so it had never run.)
      def short_term_entry(memory)
        {
          tier: "short_term",
          key: memory.memory_key,
          value: memory.memory_value,
          created_at: memory.created_at&.iso8601
        }
      end
    end
  end
end
