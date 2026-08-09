# frozen_string_literal: true

module Ai
  module Provisioning
    # Translates natural language operator input into a structured Project Brief.
    #
    # The brief is the canonical input to PlanComposerService. It captures intent,
    # use case, scale, regions, compliance, budget cap, latency targets, data
    # residency, and an optional preferred provider.
    #
    # `capture` is the cold-start entry — convert raw NL into a brief Hash plus
    # the list of fields that still need clarification.
    #
    # `refine` accepts a partially-populated brief plus a clarification utterance
    # and merges new field values in.
    #
    # `classify` is the cheap intent-type prefilter the Concierge uses to decide
    # whether a message should route to the provisioning flow at all. A regex
    # match returns immediately; ambiguous inputs fall through to a low-token
    # LLM call when an `llm_client` is available.
    #
    # All LLM access is funneled through #extract_brief_from_llm and
    # #classify_with_llm so test specs can stub the seam while real merge,
    # normalization, and missing-field logic still runs.
    class IntentCaptureService
      # Supplies resolve_service_agent — used to attribute this service's LLM
      # calls to an agent so they are recorded (IMP 019fe1da).
      include AgentBackedService

      BRIEF_SCHEMA = {
        intent: :string,
        use_case: :string,
        scale: { initial: :integer, target: :integer, growth_profile: :string },
        regions: :array,
        compliance: :array,
        budget_cap_usd_monthly: :float,
        latency_targets_ms: { p99: :integer },
        data_residency: :array,
        preferred_provider: :string_or_nil,
        preferred_template: :string_or_nil,
        # M3 "Run My Code" fields — populated when the operator references a
        # Git repo and wants its code deployed onto the provisioned instance.
        # All optional: when null, the plan stays a pure provisioning plan and
        # PlanComposerService skips the deploy_app_code step.
        repo_url: :string_or_nil,
        branch: :string_or_nil,
        start_command: :string_or_nil,
        runtime_hint: :string_or_nil # node|python|ruby|go|docker|java|none
      }.freeze

      REQUIRED_FIELDS = %i[intent use_case scale regions budget_cap_usd_monthly].freeze

      INTENT_KEYWORDS = /\b(?:provision|deploy|host|stack|cluster|database|scale|migrate)\b/i.freeze

      INTENT_PROVISION = "provision_infrastructure"
      INTENT_GENERAL = "general_chat"

      DEFAULT_TEMPERATURE = 0.2
      DEFAULT_MAX_TOKENS = 1024
      CLASSIFY_MAX_TOKENS = 64

      # Explicit task_type for the routing governance record, so escalations on
      # this seam are attributable rather than pooled under a generic default.
      TIER_TASK_TYPE = "provisioning_intent_capture"

      # Keep in sync with CostEstimatorService::LOCAL_PROVIDER_TYPES and
      # TopologyRendererService::LOCAL_PROVIDER_TYPES.
      LOCAL_PROVIDER_TYPES = %w[local_qemu].freeze

      # Provider identifiers shorter than this are too collision-prone to use
      # as deterministic text evidence (a 2-char name would substring-match
      # half the dictionary).
      MIN_EVIDENCE_NEEDLE_LENGTH = 3

      # The provider catalog is supplied by the system extension. Core mode has
      # none, and its absence has a defined meaning throughout this subsystem
      # (see PlanComposerService#resolve_provider_choice): "no providers
      # configured", not "reject everything". Extracted as a predicate so the
      # core-mode path is directly testable without unloading the extension.
      def self.provider_catalog_available?
        defined?(::System::Provider).present?
      end

      attr_reader :account, :user, :conversation

      def initialize(account:, user:, conversation: nil)
        @account = account
        @user = user
        @conversation = conversation
      end

      # Convert a free-text utterance into a structured brief.
      # Merges the LLM's extracted fields onto an optional `prior_brief` so
      # repeated passes converge on a complete brief.
      def capture(natural_language:, prior_brief: nil)
        base = normalize_brief(prior_brief)
        @cap_exceeded_payload = nil
        extracted = extract_brief_from_llm(
          natural_language: natural_language,
          prior_brief: base,
          mode: :capture
        ) || {}

        merged = deep_merge_brief(base, normalize_brief(extracted))
        coerced = coerce_brief(merged, evidence_text: natural_language)

        result = { brief: coerced, missing_fields: missing_fields_for(coerced) }
        result.merge!(cap_exceeded_attributes) if @cap_exceeded_payload
        result
      end

      # Apply a clarification utterance against an existing brief.
      # Re-runs extraction with the brief as context and merges the new fields.
      def refine(brief:, clarification:)
        base = normalize_brief(brief)
        @cap_exceeded_payload = nil
        extracted = extract_brief_from_llm(
          natural_language: clarification,
          prior_brief: base,
          mode: :refine
        ) || {}

        merged = deep_merge_brief(base, normalize_brief(extracted))
        coerced = coerce_brief(merged, evidence_text: clarification)

        result = { brief: coerced, missing_fields: missing_fields_for(coerced) }
        result.merge!(cap_exceeded_attributes) if @cap_exceeded_payload
        result
      end

      # Cheap intent classification. Regex prefilter handles the obvious cases
      # without an LLM round-trip; ambiguous inputs optionally fall through to
      # a low-token LLM call when a client is available. Returns at minimum
      # `{ intent_type: "general_chat", confidence: 0.3 }` so callers always
      # get a structured result.
      def classify(natural_language:)
        text = natural_language.to_s
        return { intent_type: INTENT_GENERAL, confidence: 0.0 } if text.strip.empty?

        if text.match?(INTENT_KEYWORDS)
          return { intent_type: INTENT_PROVISION, confidence: regex_confidence(text) }
        end

        llm_result = classify_with_llm(text)
        return llm_result if llm_result

        { intent_type: INTENT_GENERAL, confidence: 0.3 }
      end

      private

      # ----- LLM seams (stubbed in specs) ------------------------------------

      # Returns a Hash of brief fields parsed from the LLM response, or nil.
      # The brief assembly logic in #capture/#refine remains real even when
      # this method is stubbed.
      #
      # CostCapGuard gates the LLM call: when the account has burned through
      # its daily LLM allowance we return nil so the caller falls back to the
      # prior brief and surfaces an upgrade prompt via the missing_fields list.
      def extract_brief_from_llm(natural_language:, prior_brief:, mode:)
        client = llm_client
        return nil unless client

        guard = ::Ai::Provisioning::CostCapGuard.allow?(account: account)
        if guard.cap_exceeded?
          @cap_exceeded_payload = guard.payload
          Rails.logger.warn(
            "[IntentCaptureService] LLM cost cap exceeded for account=#{account&.id} " \
              "(spent=$#{guard.payload[:spent]}, cap=$#{guard.payload[:cap]})"
          )
          return nil
        end

        prompt = build_brief_prompt(natural_language, prior_brief, mode)
        response = safe_complete(
          client,
          messages: [{ role: "user", content: prompt }],
          max_tokens: DEFAULT_MAX_TOKENS,
          temperature: DEFAULT_TEMPERATURE
        )
        return nil unless response&.success?

        parse_brief_json(response.content)
      end

      # Returns { intent_type:, confidence: } from a low-token LLM call,
      # or nil when no client is configured / the call fails.
      def classify_with_llm(natural_language)
        client = llm_client
        return nil unless client

        prompt = build_classify_prompt(natural_language)
        response = safe_complete(
          client,
          messages: [{ role: "user", content: prompt }],
          max_tokens: CLASSIFY_MAX_TOKENS,
          temperature: 0.0
        )
        return nil unless response&.success?

        parse_classify_json(response.content)
      end

      # Lazy-initialized; stubbable via `allow(service).to receive(:llm_client)`.
      def llm_client
        @llm_client ||= build_llm_client
      end

      # Wrapped so every LLM call this service makes lands an Ai::AgentExecution
      # — token counts, cost_usd, performance_metrics and the budget debit
      # (IMP 019fe1da). #tracked_client_for wraps WITHOUT re-routing which
      # provider serves the call; see its doc for why that distinction matters
      # and why there is no double-debit.
      def build_llm_client
        tracked_client_for(WorkerLlmClient.for_account(account), agent: tracking_agent)
      rescue StandardError => e
        Rails.logger.warn("[IntentCaptureService] LLM client unavailable: #{e.message}")
        nil
      end

      # Memoized so the client wrap and the tier resolution attribute to the SAME
      # agent, and so the lookup happens once per service instance rather than
      # per LLM call. nil is a valid outcome (core mode / unseeded account): the
      # client stays unwrapped and no tier is resolved.
      def tracking_agent
        return @tracking_agent if defined?(@tracking_agent)

        @tracking_agent = resolve_tracking_agent(::Ai::Provisioning::TrackingAgents::SLUGS)
      end

      # Governed per-task tier resolution (IMP-019fe1da, fifth oracle).
      #
      # resolve_task_tier is gated on ai_task_tier_routing_enabled: with the gate
      # OFF it returns nil immediately, no resolver call at all, and this method
      # sends exactly the model it always did. With it ON it persists an
      # Ai::RoutingDecision + Ai::TaskComplexityAssessment and returns the
      # Resolution.
      #
      # The resolution is APPLIED, not merely recorded. Persisting a decision
      # that says "escalate to X" while still calling Y would make the routing
      # oracle actively misleading — worse than the empty table it replaces.
      # routing_decision_id rides along so TrackedWorkerLlmClient can link the
      # decision to the execution it creates, which is what lets
      # Ai::AgentExecution#record_routing_decision_outcome close the loop.
      def safe_complete(client, **opts)
        agent = tracking_agent
        resolution = if agent
                       resolve_task_tier(
                         agent: agent,
                         task_type: TIER_TASK_TYPE,
                         messages: Array(opts[:messages])
                       )
                     end

        baseline_model = resolve_model
        call_opts = opts.dup

        # This seam's output contract is JSON conforming to BRIEF_SCHEMA, which
        # the resolver cannot reason about — a downgrade to a reasoning-tier
        # model once returned prose and emptied the brief. Substitution is
        # therefore declined here, but the decision is still recorded and
        # annotated with why, so the routing oracle stays complete.
        if resolution && !resolution_applicable?(resolution, :structured_json)
          annotate_unapplied_resolution!(
            routing_decision_id,
            reason: "caller requires structured JSON (BRIEF_SCHEMA); substituting " \
                    "#{resolution.model.inspect} for #{baseline_model.inspect} is not " \
                    "permitted without a verified structured-output capability signal",
            delivered_model: baseline_model
          )
          call_opts[:model] = baseline_model
        else
          call_opts[:model] = resolution&.model.presence || baseline_model
          call_opts[:effort] = resolution.effort if resolution&.effort.present?
        end

        call_opts[:routing_decision_id] = routing_decision_id if routing_decision_id

        client.complete(**call_opts)
      rescue WorkerLlmClient::WorkerLlmError => e
        Rails.logger.warn("[IntentCaptureService] LLM call failed: #{e.message}")
        nil
      end

      def resolve_model
        # Prefer the conversation agent's configured model when present, else
        # ask the same provider WorkerLlmClient.for_account picks (i.e. the
        # account's first active *credential's* provider) for its default
        # model. Picking by Ai::Provider#is_active alone misses the case
        # where multiple providers are flagged active but only one has live
        # credentials — IntentCaptureService would then send (e.g.)
        # "gpt-4.1-mini" to an Anthropic HTTP client and the API would 404.
        model = conversation&.agent&.try(:model)
        model ||= conversation&.agent&.mcp_tool_manifest&.dig("model")
        return model if model.present?

        credential = account&.ai_provider_credentials&.active
                            &.includes(:provider)&.first
        credential&.provider&.default_model.presence || "gpt-4.1-mini"
      end

      # ----- Prompts ---------------------------------------------------------

      def build_brief_prompt(natural_language, prior_brief, mode)
        action_label = mode == :refine ? "Update the brief with new information" : "Extract a brief from the message"
        <<~PROMPT
          You are a provisioning intent extractor. #{action_label}.

          Return ONLY a single JSON object — no prose, no code fences. The object
          contains any of these fields you can confidently infer; OMIT fields you
          can't determine (do NOT guess):

            intent: short string ("provision a 3-node Postgres cluster")
            use_case: longer description of what the workload does
            scale: { initial: int, target: int, growth_profile: "linear"|"exponential"|"steady"|"bursty" }
            regions: array of region strings (e.g. ["us-east-1","eu-west-1"])
            compliance: array of frameworks (e.g. ["SOC2","HIPAA","PCI"])
            budget_cap_usd_monthly: number
            latency_targets_ms: { p99: int }
            data_residency: array of country/region codes the data must stay in
            preferred_provider: string id of a cloud provider, or null
            preferred_template: name of a node template to provision from, or null

          #{provider_extraction_rule.chomp}

          #{template_selection_rule.chomp}

          Local provider regions rule: when `preferred_provider` is
          "local_qemu" (or any other local-hypervisor provider — runs on the
          operator's own hardware), regions are NOT meaningful. Even if the
          operator mentions a cloud-style region like "us-east" or "eu-west"
          in passing, leave `regions` as an empty array []. Local providers
          have no concept of cloud regions; surfacing one would make the
          downstream plan composer try to resolve a non-existent zone. If
          the operator truly insists on a cloud-region label after picking
          local_qemu, treat it as confused intent and prefer empty regions.

          Run-My-Code rule: if the operator references a Git repository (e.g.
          "github.com/me/my-bot", "github:me/repo", "gitlab.com/foo/bar",
          "https://gitea.example.com/me/svc"), populate `repo_url` with the
          canonical HTTPS URL of the repo. If they mention a branch, populate
          `branch` (default to "main" only when the operator is explicit; leave
          null otherwise). If they specify a start command (e.g. "run node
          index.js", "start with python app.py", "launch via npm start"),
          populate `start_command`. If you can confidently infer the runtime
          from context (Node.js / Python / Ruby / Go / Docker / Java),
          populate `runtime_hint` with the lowercase token: "node", "python",
          "ruby", "go", "docker", "java", or "none". If none of these can be
          determined, leave the field null (do NOT guess).

          Existing brief (merge new fields onto this — do not repeat fields you have nothing to add to):
          #{JSON.dump(prior_brief)}

          Operator message:
          #{natural_language}
        PROMPT
      end

      # The provider rule is built from the account's ACTUAL catalog when one
      # exists. `preferred_provider` is a choice from an authoritative,
      # enumerable set — free-generating it from a generic cloud vocabulary is
      # what produced 'pro_cloud'/'local_qemu' from objectives naming
      # "IPNode PVE" (three live misextractions, 2026-08-08/09; the old list
      # did not even contain "proxmox"). The LLM's job is reduced to selecting
      # from the closed set; #provider_evidenced_in_text then overrides it
      # deterministically whenever the operator named a provider outright.
      #
      # An unconfigured provider is copied VERBATIM, not nulled: the composer's
      # clarification path uses that signal to say "you asked for X, which
      # isn't configured" instead of blankly asking which provider to use.
      def provider_extraction_rule
        providers = configured_providers
        if providers.any?
          catalog = providers.map do |p|
            %(  - "#{p.name}" (id #{p.id}) -> #{p.provider_type})
          end.join("\n")
          <<~RULE
            Provider extraction rule: this account's configured providers are a
            CLOSED SET. The only valid `preferred_provider` values are the ->
            tokens below:
            #{catalog}
            If the operator references one of these providers (by name, token,
            or id), set `preferred_provider` to its -> token EXACTLY as listed.
            If the operator names a provider that is NOT in this list, copy the
            name they wrote verbatim so the platform can tell them it is not
            configured. If no provider is mentioned, leave it null. NEVER
            invent, translate, or substitute a provider identifier.
          RULE
        else
          <<~RULE
            Provider extraction rule: if the operator names a specific provider
            (AWS, Hetzner, DigitalOcean, GCP, Azure, Vultr, Linode, OpenStack,
            Local QEMU/KVM, LocalQemu, "local hypervisor", Pro Cloud), populate
            `preferred_provider` with the lowercase canonical identifier — e.g.
            "aws", "hetzner", "digitalocean", "gcp", "azure", "vultr", "linode",
            "openstack", "local_qemu" (for Local QEMU/KVM and any "local
            hypervisor" / "on-box" phrasing), "pro_cloud" (Powernode-managed
            pool). If no provider is mentioned, leave it null (do NOT guess).
          RULE
        end
      end

      # Same closed-set principle as providers (IMP 019fe3a7-266d): the
      # account's node templates are enumerable and authoritative, and the
      # template decides boot_mode — which decides whether the provisioned node
      # carries the agent at all. boot_mode is surfaced per entry because an
      # operator writing "the uefi one" gives the LLM something to select on.
      # No generic fallback: without a catalog there is nothing to constrain
      # against, and the schema line above already defines the field.
      def template_selection_rule
        templates = configured_templates
        return "" if templates.empty?

        catalog = templates.map do |t|
          boot = t.config.is_a?(Hash) ? t.config["boot_mode"] : nil
          %(  - "#{t.name}" (id #{t.id}) [boot_mode #{boot.presence || 'cloud_init'}])
        end.join("\n")
        <<~RULE
          Template rule: this account's node templates are a CLOSED SET:
          #{catalog}
          If the operator references one of these templates (by name or id),
          set `preferred_template` to its name EXACTLY as listed. If they name
          a template NOT in this list, copy the name they wrote verbatim. If no
          template is mentioned, leave it null. NEVER invent a template name.
        RULE
      end

      def build_classify_prompt(natural_language)
        <<~PROMPT
          Classify the operator's message into ONE intent and a confidence score.

          Intents:
            #{INTENT_PROVISION}  — wants to create / scale / migrate / replace infrastructure
            #{INTENT_GENERAL}    — anything else (questions, conversation, status checks)

          Return JSON ONLY: {"intent_type":"...","confidence":0.0-1.0}

          Message:
          #{natural_language}
        PROMPT
      end

      # ----- Parsing ---------------------------------------------------------

      def parse_brief_json(content)
        json = extract_json_object(content)
        unless json.is_a?(Hash)
          # Previously the ONLY silent path here. A model that answers in prose
          # instead of JSON — which is what a reasoning-tier substitution did —
          # returned nil from here, the caller merged {} onto an empty base, and
          # the operator eventually saw "CompositionError: intent is required",
          # naming neither the model nor the parse miss. Never silent again.
          Rails.logger.warn(
            "[IntentCaptureService] brief response contained no JSON object " \
              "(got #{json.class}); excerpt: #{content.to_s.strip[0, 200].inspect}"
          )
          return nil
        end

        json.deep_stringify_keys
      rescue JSON::ParserError => e
        Rails.logger.warn(
          "[IntentCaptureService] Brief JSON parse failed: #{e.message}; " \
            "excerpt: #{content.to_s.strip[0, 200].inspect}"
        )
        nil
      end

      def parse_classify_json(content)
        json = extract_json_object(content)
        return nil unless json.is_a?(Hash)

        intent = json["intent_type"] || json[:intent_type]
        confidence = (json["confidence"] || json[:confidence]).to_f

        return nil unless [INTENT_PROVISION, INTENT_GENERAL].include?(intent)

        { intent_type: intent, confidence: confidence.clamp(0.0, 1.0) }
      rescue JSON::ParserError => e
        Rails.logger.warn("[IntentCaptureService] Classify JSON parse failed: #{e.message}")
        nil
      end

      def extract_json_object(content)
        return nil unless content.is_a?(String)

        # Strip ```json fences and surrounding prose; isolate the largest balanced object.
        stripped = content.strip
        stripped = stripped.sub(/\A```(?:json)?\s*/i, "").sub(/```\s*\z/, "")
        first = stripped.index("{")
        last = stripped.rindex("}")
        return nil unless first && last && last > first

        JSON.parse(stripped[first..last])
      end

      # ----- Brief shape helpers --------------------------------------------

      def empty_brief
        {
          "intent" => nil,
          "use_case" => nil,
          "scale" => { "initial" => nil, "target" => nil, "growth_profile" => nil },
          "regions" => [],
          "compliance" => [],
          "budget_cap_usd_monthly" => nil,
          "latency_targets_ms" => { "p99" => nil },
          "data_residency" => [],
          "preferred_provider" => nil,
          "preferred_template" => nil,
          "repo_url" => nil,
          "branch" => nil,
          "start_command" => nil,
          "runtime_hint" => nil
        }
      end

      def normalize_brief(brief)
        return empty_brief unless brief.is_a?(Hash)

        brief.deep_stringify_keys
      end

      def deep_merge_brief(base, additions)
        base = empty_brief.deep_merge(base) { |_k, a, b| b.nil? ? a : b }
        return base if additions.blank?

        base.deep_merge(additions) do |_k, a, b|
          if b.nil? || (b.respond_to?(:empty?) && b.empty? && !a.nil?)
            a
          elsif a.is_a?(Array) && b.is_a?(Array)
            (a + b).uniq
          else
            b
          end
        end
      end

      def coerce_brief(brief, evidence_text: nil)
        out = brief.dup
        out["intent"] = out["intent"]&.to_s
        out["use_case"] = out["use_case"]&.to_s

        scale = out["scale"].is_a?(Hash) ? out["scale"].dup : {}
        scale["initial"] = scale["initial"]&.to_i unless scale["initial"].nil?
        scale["target"] = scale["target"]&.to_i unless scale["target"].nil?
        scale["growth_profile"] = scale["growth_profile"]&.to_s
        out["scale"] = scale

        out["regions"] = Array(out["regions"]).map(&:to_s).uniq
        out["compliance"] = Array(out["compliance"]).map(&:to_s).uniq
        out["data_residency"] = Array(out["data_residency"]).map(&:to_s).uniq

        # Resolve preferred_provider against what the account ACTUALLY has,
        # BEFORE the local-provider scrub below — that scrub keys off the
        # provider TYPE, and an operator naturally writes the provider's NAME.
        out["preferred_provider"] = normalize_preferred_provider(out["preferred_provider"])

        # Deterministic text evidence beats generative extraction: when the
        # operator's own words name exactly one configured provider, that IS
        # the preferred provider — no LLM opinion can change it. This is the
        # fix for three live misextractions (2026-08-08/09) where objectives
        # naming "the 'IPNode PVE' provider" yielded 'pro_cloud' twice and
        # 'local_qemu' once; the last was configured, passed validation, and
        # the scrub below then silently destroyed regions ["dna","rna"].
        evidenced = provider_evidenced_in_text(evidence_text)
        if evidenced && out["preferred_provider"] != evidenced.provider_type.to_s
          Rails.logger.info(
            "[IntentCaptureService] preferred_provider #{out['preferred_provider'].inspect} " \
              "overridden by text evidence: operator named #{evidenced.name.inspect} " \
              "(#{evidenced.provider_type})"
          )
          out["preferred_provider"] = evidenced.provider_type.to_s
        end

        apply_local_provider_region_scrub!(out, evidenced)

        # Template choice follows the same three layers as provider choice
        # (IMP 019fe3a7-266d): normalize against the catalog, then let
        # deterministic text evidence beat the LLM's extraction.
        out["preferred_template"] = normalize_preferred_template(out["preferred_template"])
        evidenced_template = template_evidenced_in_text(evidence_text)
        if evidenced_template && out["preferred_template"] != evidenced_template.name.to_s
          Rails.logger.info(
            "[IntentCaptureService] preferred_template #{out['preferred_template'].inspect} " \
              "overridden by text evidence: operator named #{evidenced_template.name.inspect}"
          )
          out["preferred_template"] = evidenced_template.name.to_s
        end

        unless out["budget_cap_usd_monthly"].nil?
          out["budget_cap_usd_monthly"] = out["budget_cap_usd_monthly"].to_f
        end

        latency = out["latency_targets_ms"].is_a?(Hash) ? out["latency_targets_ms"].dup : {}
        latency["p99"] = latency["p99"]&.to_i unless latency["p99"].nil?
        out["latency_targets_ms"] = latency

        # (preferred_provider is normalized above, before the local-provider
        # region scrub that depends on its resolved TYPE.)

        # M3 "Run My Code" fields — string_or_nil. Coerce non-nil values to
        # String; leave explicit nils alone so the plan composer can branch
        # on `brief["repo_url"].present?`.
        %w[repo_url branch start_command runtime_hint].each do |key|
          out[key] = out[key].to_s if out[key].is_a?(String) || out[key].is_a?(Symbol)
          out[key] = nil if out[key].is_a?(String) && out[key].strip.empty?
        end
        out["runtime_hint"] = out["runtime_hint"].downcase if out["runtime_hint"].is_a?(String)

        out
      end

      # Resolve the LLM's free-text provider reference to a provider_type the
      # account actually has, or nil (IMP 019fe1e0-71b1).
      #
      # The extracted value was previously stringified and trusted. Observed
      # failure: an objective naming "the 'IPNode PVE' provider" yielded
      # 'pro_cloud' — a type absent from that account — which matched nothing in
      # PlanComposerService#resolve_provider_choice and degraded to the
      # clarification path. The more dangerous variant is a hallucinated type
      # that DOES match some other configured provider: that silently routes the
      # whole plan to the wrong cloud with no error and no operator signal.
      #
      # Accepts provider_type, display name, or id because operators write the
      # NAME; normalizes to provider_type, which is what the downstream matcher
      # compares against.
      def normalize_preferred_provider(raw)
        return nil if raw.blank?

        value = raw.to_s.strip
        return value if value.empty?

        # Core mode has no catalog to validate against (nulling every value
        # would be a regression, not a safety win), and zero configured
        # providers is an existing, defined state ("legacy/test path" per
        # resolve_provider_choice) — nothing to validate against either way.
        providers = configured_providers
        return value if providers.empty?

        needle = value.downcase
        match = providers.find do |p|
          p.provider_type.to_s.downcase == needle ||
            p.name.to_s.downcase == needle ||
            p.id.to_s.downcase == needle
        end
        return match.provider_type.to_s if match

        # Deliberately NOT nulled. An unconfigured value and nil both reach the
        # same place downstream (resolve_provider_choice matches nothing and
        # falls through to clarification), so discarding it would change no
        # outcome while throwing away a real signal — the operator asked for
        # something they have not configured, which is worth keeping in the
        # brief and worth saying out loud. Whether that should instead become a
        # distinct "you asked for X, which isn't configured" response is a
        # product decision, not this defect's to make.
        Rails.logger.warn(
          "[IntentCaptureService] preferred_provider #{value.inspect} for " \
            "account=#{account&.id} matches no configured provider " \
            "#{providers.map { |p| [p.name, p.provider_type] }.inspect}; leaving it on the " \
            "brief — the composer will ask which provider to use."
        )
        value
      end

      # Normalize the LLM's template reference to the configured template's
      # canonical NAME (accepting name or id), keep-with-warn for values the
      # account does not have — identical contract to
      # #normalize_preferred_provider, for the same reasons.
      def normalize_preferred_template(raw)
        return nil if raw.blank?

        value = raw.to_s.strip
        return value if value.empty?

        templates = configured_templates
        return value if templates.empty?

        needle = value.downcase
        match = templates.find do |t|
          t.name.to_s.downcase == needle || t.id.to_s.downcase == needle
        end
        return match.name.to_s if match

        Rails.logger.warn(
          "[IntentCaptureService] preferred_template #{value.inspect} for " \
            "account=#{account&.id} matches no configured template " \
            "#{templates.map(&:name).inspect}; leaving it on the brief."
        )
        value
      end

      # The account's node-template catalog, or [] in core mode. Memoized for
      # the same single-pass consistency reasons as #configured_providers.
      def configured_templates
        return @configured_templates if defined?(@configured_templates)

        @configured_templates =
          if defined?(::System::NodeTemplate)
            ::System::NodeTemplate.where(account_id: account.id).to_a
          else
            []
          end
      end

      # The account's enabled provider catalog, or [] in core mode / when none
      # are configured. Memoized per service instance: the prompt builder, the
      # validator, the text-evidence matcher, and the region scrub must all see
      # the same list within one capture/refine pass.
      def configured_providers
        return @configured_providers if defined?(@configured_providers)

        @configured_providers =
          if self.class.provider_catalog_available?
            ::System::Provider.where(account_id: account.id, enabled: true).to_a
          else
            []
          end
      end

      # Deterministic resolution layer: returns the single configured provider
      # the operator's utterance names (by display name, provider_type, or id),
      # or nil when the text names zero — or more than one, where picking is
      # genuinely ambiguous and the LLM's constrained extraction stands.
      def provider_evidenced_in_text(text)
        sole_record_evidenced_in_text(configured_providers, text) do |provider|
          [provider.name, provider.provider_type, provider.id]
        end
      end

      # Same layer for node templates (name or id — templates have no type).
      def template_evidenced_in_text(text)
        sole_record_evidenced_in_text(configured_templates, text) do |template|
          [template.name, template.id]
        end
      end

      # Matching is intentionally dumb string work: normalized (case-folded,
      # [-_ ] collapsed) whole-token inclusion. Dumb is the point — this layer
      # exists because it cannot hallucinate. Exactly one matched record is
      # evidence; zero or several is not.
      def sole_record_evidenced_in_text(records, text)
        return nil if text.blank? || records.empty?

        haystack = normalize_evidence(text)
        matches = records.select do |record|
          yield(record).any? do |identifier|
            needle = normalize_evidence(identifier.to_s)
            next false if needle.length < MIN_EVIDENCE_NEEDLE_LENGTH

            haystack.match?(/(?<![[:alnum:]])#{Regexp.escape(needle)}(?![[:alnum:]])/)
          end
        end
        matches.size == 1 ? matches.first : nil
      end

      def normalize_evidence(str)
        str.to_s.downcase.gsub(/[-_\s]+/, " ").strip
      end

      # Local-provider regions scrub, data-driven (was: unconditional emptying
      # keyed on a hardcoded type list — which, combined with a misextracted
      # provider, silently destroyed real multi-region intent).
      #
      # - Regions the local provider has CONFIGURED (ProviderRegion.region_code)
      #   are real placement intent and survive.
      # - A local pick that is UNCORROBORATED by the operator's text and whose
      #   scrub would drop regions belonging to a DIFFERENT configured provider
      #   is the misextraction signature: demote the pick to nil (the composer
      #   asks which provider) and keep the regions. Never silently reroute.
      # - Otherwise scrub as before: unconfigured cloud-style regions alongside
      #   a local provider are confused intent, and the composer would try to
      #   resolve a non-existent zone.
      def apply_local_provider_region_scrub!(out, evidenced)
        type = out["preferred_provider"].to_s
        return unless LOCAL_PROVIDER_TYPES.include?(type)

        regions = Array(out["regions"])
        return if regions.empty?

        provider = configured_providers.find { |p| p.provider_type.to_s == type }
        unless provider
          # Core mode / unconfigured local type: no region data to consult —
          # preserve the original unconditional behavior.
          out["regions"] = []
          return
        end

        allowed = provider.provider_regions.pluck(:region_code).map { |c| c.to_s.downcase }
        kept, dropped = regions.partition { |r| allowed.include?(r.to_s.downcase) }
        return if dropped.empty?

        corroborated = evidenced && evidenced.id == provider.id
        if !corroborated && regions_belong_to_other_provider?(dropped, provider)
          Rails.logger.warn(
            "[IntentCaptureService] demoting uncorroborated preferred_provider " \
              "#{type.inspect}: scrubbing would drop regions #{dropped.inspect}, which are " \
              "configured on a different provider for account=#{account&.id}. Keeping the " \
              "regions and letting the composer ask which provider to use."
          )
          out["preferred_provider"] = nil
          return
        end

        Rails.logger.warn(
          "[IntentCaptureService] dropping regions #{dropped.inspect} — not configured on " \
            "local provider #{provider.name.inspect} (#{type}) for account=#{account&.id}"
        )
        out["regions"] = kept
      end

      def regions_belong_to_other_provider?(regions, provider)
        other_codes = ::System::ProviderRegion
                      .where(account_id: account.id)
                      .where.not(provider_id: provider.id)
                      .pluck(:region_code)
                      .map { |c| c.to_s.downcase }
        regions.any? { |r| other_codes.include?(r.to_s.downcase) }
      end

      def missing_fields_for(brief)
        REQUIRED_FIELDS.select { |field| field_blank?(brief, field) }
      end

      def field_blank?(brief, field)
        case field
        when :scale
          scale = brief["scale"]
          !scale.is_a?(Hash) || scale["initial"].blank? || scale["target"].blank?
        when :regions
          Array(brief["regions"]).empty?
        else
          brief[field.to_s].blank?
        end
      end

      def regex_confidence(text)
        # Multiple matches → higher confidence; clamp to [0.6, 0.95].
        match_count = text.scan(INTENT_KEYWORDS).size
        (0.6 + (0.1 * match_count)).clamp(0.6, 0.95)
      end

      # Surface the cost-cap state to capture/refine callers so the chat layer
      # can render UpgradeRequiredCard instead of pretending the LLM round-trip
      # succeeded.
      def cap_exceeded_attributes
        payload = @cap_exceeded_payload || {}
        {
          cap_exceeded: true,
          requires_upgrade: true,
          reason: "llm_cost_cap_exceeded",
          spent: payload[:spent],
          cap: payload[:cap]
        }
      end
    end
  end
end
