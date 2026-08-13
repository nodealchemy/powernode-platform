# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Provisioning::IntentCaptureService, type: :service do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }

  subject(:service) { described_class.new(account: account, user: user) }

  describe "#capture" do
    context "when the LLM returns a partial brief" do
      let(:llm_payload) do
        {
          "intent" => "Spin up a 3-node Postgres cluster",
          "use_case" => "Primary OLTP for a side-business SaaS",
          "scale" => { "initial" => 3, "target" => 5, "growth_profile" => "linear" },
          "regions" => ["us-east-1"],
          "budget_cap_usd_monthly" => 200
        }
      end

      before do
        allow(service).to receive(:extract_brief_from_llm).and_return(llm_payload)
      end

      it "returns a brief that conforms to the documented shape" do
        result = service.capture(natural_language: "I need 3 Postgres nodes in us-east-1, ~$200/mo")

        expect(result).to be_a(Hash)
        expect(result[:brief]).to include(
          "intent" => "Spin up a 3-node Postgres cluster",
          "use_case" => "Primary OLTP for a side-business SaaS",
          "regions" => ["us-east-1"],
          "budget_cap_usd_monthly" => 200.0
        )
        expect(result[:brief]["scale"]).to include("initial" => 3, "target" => 5, "growth_profile" => "linear")
        expect(result[:brief]["compliance"]).to eq([])
        expect(result[:brief]["data_residency"]).to eq([])
        expect(result[:brief]["latency_targets_ms"]).to eq("p99" => nil)
        expect(result[:brief]["preferred_provider"]).to be_nil
      end

      it "coerces budget into a Float" do
        result = service.capture(natural_language: "anything")
        expect(result[:brief]["budget_cap_usd_monthly"]).to be_a(Float)
      end

      it "lists no missing fields when all required keys are populated" do
        result = service.capture(natural_language: "anything")
        expect(result[:missing_fields]).to be_empty
      end
    end

    context "when the LLM returns an incomplete brief" do
      before do
        allow(service).to receive(:extract_brief_from_llm).and_return(
          "intent" => "Provision something"
        )
      end

      it "reports the still-missing required fields" do
        result = service.capture(natural_language: "I want to provision something")

        expect(result[:missing_fields]).to match_array(
          %i[use_case scale regions budget_cap_usd_monthly]
        )
      end
    end

    context "when no LLM client is available" do
      before { allow(service).to receive(:llm_client).and_return(nil) }

      it "returns an empty brief with all required fields missing" do
        result = service.capture(natural_language: "I want to host a SaaS")
        expect(result[:missing_fields]).to match_array(described_class::REQUIRED_FIELDS)
        expect(result[:brief]).to include("intent" => nil, "regions" => [])
      end
    end

    context "when the operator references a Git repository (M3 Run My Code)" do
      let(:llm_payload) do
        {
          "intent" => "Deploy my Discord bot",
          "use_case" => "Discord bot for my server",
          "scale" => { "initial" => 1, "target" => 1, "growth_profile" => "steady" },
          "regions" => ["us-east-1"],
          "budget_cap_usd_monthly" => 20,
          "repo_url" => "https://github.com/me/my-bot",
          "branch" => "main",
          "start_command" => "node index.js",
          "runtime_hint" => "node"
        }
      end

      before do
        allow(service).to receive(:extract_brief_from_llm).and_return(llm_payload)
      end

      it "extracts repo_url onto the brief" do
        result = service.capture(natural_language: "deploy github.com/me/my-bot")
        expect(result[:brief]["repo_url"]).to eq("https://github.com/me/my-bot")
      end

      it "extracts branch when present" do
        result = service.capture(natural_language: "deploy from main")
        expect(result[:brief]["branch"]).to eq("main")
      end

      it "extracts start_command when present" do
        result = service.capture(natural_language: "run node index.js")
        expect(result[:brief]["start_command"]).to eq("node index.js")
      end

      it "extracts runtime_hint when present and lowercases it" do
        result = service.capture(natural_language: "Node.js Discord bot")
        expect(result[:brief]["runtime_hint"]).to eq("node")
      end

      it "leaves repo_url null when no repo is mentioned" do
        allow(service).to receive(:extract_brief_from_llm).and_return(
          "intent" => "Spin up a stack",
          "use_case" => "Generic workload",
          "scale" => { "initial" => 1, "target" => 1, "growth_profile" => "steady" },
          "regions" => ["us-east-1"],
          "budget_cap_usd_monthly" => 50
        )
        result = service.capture(natural_language: "spin up something for me")
        expect(result[:brief]["repo_url"]).to be_nil
        expect(result[:brief]["branch"]).to be_nil
        expect(result[:brief]["start_command"]).to be_nil
        expect(result[:brief]["runtime_hint"]).to be_nil
      end

      it "build_brief_prompt instructs the LLM how to populate the new fields" do
        prompt = service.send(:build_brief_prompt, "deploy github.com/me/x", {}, :capture)
        expect(prompt).to include("repo_url")
        expect(prompt).to include("branch")
        expect(prompt).to include("start_command")
        expect(prompt).to include("runtime_hint")
        expect(prompt).to match(/github\.com|gitlab\.com|gitea/i)
        expect(prompt).to match(/node|python|ruby|go|docker|java/i)
      end

      it "downcases runtime_hint even when LLM emits uppercase" do
        allow(service).to receive(:extract_brief_from_llm).and_return(
          llm_payload.merge("runtime_hint" => "PYTHON")
        )
        result = service.capture(natural_language: "Python service")
        expect(result[:brief]["runtime_hint"]).to eq("python")
      end

      it "treats blank string as nil for the new fields" do
        allow(service).to receive(:extract_brief_from_llm).and_return(
          llm_payload.merge(
            "repo_url" => "",
            "branch" => "   ",
            "start_command" => "",
            "runtime_hint" => ""
          )
        )
        result = service.capture(natural_language: "anything")
        expect(result[:brief]["repo_url"]).to be_nil
        expect(result[:brief]["branch"]).to be_nil
        expect(result[:brief]["start_command"]).to be_nil
        expect(result[:brief]["runtime_hint"]).to be_nil
      end
    end

    # IMP-cdc1d0703e5a. `with_storage_gb` reaches ProvisionFullStackExecutor
    # (per-instance VolumeManagementService.provision) only if the composer can
    # read a size from somewhere. No NodeTemplate config key declares a volume
    # size and nothing else on the platform does either — inventing one with no
    # writer would produce a field that is correct in shape and inert in
    # production. The honest writer is the operator's own utterance, so the
    # brief carries it.
    context "when the operator names a persistent volume size (storage_gb)" do
      let(:llm_payload) do
        {
          "intent" => "Provision a Postgres node with a data volume",
          "use_case" => "Primary OLTP with persistent storage",
          "scale" => { "initial" => 1, "target" => 1, "growth_profile" => "steady" },
          "regions" => ["us-east-1"],
          "budget_cap_usd_monthly" => 100,
          "storage_gb" => 100
        }
      end

      before do
        allow(service).to receive(:extract_brief_from_llm).and_return(llm_payload)
      end

      it "declares storage_gb in BRIEF_SCHEMA" do
        expect(described_class::BRIEF_SCHEMA).to include(storage_gb: :integer_or_nil)
      end

      it "round-trips storage_gb onto the brief" do
        result = service.capture(natural_language: "provision a db with a 100GB data volume")
        expect(result[:brief]["storage_gb"]).to eq(100)
      end

      it "coerces a stringified size to an Integer" do
        allow(service).to receive(:extract_brief_from_llm)
          .and_return(llm_payload.merge("storage_gb" => "250"))
        result = service.capture(natural_language: "give it 250GB")
        expect(result[:brief]["storage_gb"]).to eq(250)
      end

      it "leaves storage_gb nil when the operator names no volume" do
        allow(service).to receive(:extract_brief_from_llm)
          .and_return(llm_payload.except("storage_gb"))
        result = service.capture(natural_language: "just a node please")
        expect(result[:brief]["storage_gb"]).to be_nil
      end

      # The prompt's field list is hand-written prose, NOT generated from
      # BRIEF_SCHEMA — a schema entry alone would never reach the model.
      it "build_brief_prompt instructs the LLM how to populate storage_gb" do
        prompt = service.send(:build_brief_prompt, "a db with a 100GB volume", {}, :capture)
        expect(prompt).to include("storage_gb")
      end
    end

    context "when the operator names a specific cloud provider (M2 BYOC)" do
      let(:llm_payload) do
        {
          "intent" => "Spin up a Postgres node on AWS",
          "use_case" => "Primary OLTP",
          "scale" => { "initial" => 1, "target" => 1, "growth_profile" => "steady" },
          "regions" => ["us-east-1"],
          "budget_cap_usd_monthly" => 100,
          "preferred_provider" => "aws"
        }
      end

      before do
        allow(service).to receive(:extract_brief_from_llm).and_return(llm_payload)
      end

      it "extracts preferred_provider from the LLM payload onto the brief" do
        result = service.capture(natural_language: "deploy a postgres node on AWS in us-east-1")
        expect(result[:brief]["preferred_provider"]).to eq("aws")
      end

      it "build_brief_prompt enumerates the account's configured providers as a closed set" do
        # The account factory bootstraps a "Pro Cloud" provider (M1 self-serve),
        # so this account has a catalog and the prompt must enumerate IT — not
        # the generic cloud vocabulary, whose open-ended identifiers are what
        # produced misextractions like 'pro_cloud' for a Proxmox provider.
        prompt = service.send(:build_brief_prompt, "deploy on Hetzner", {}, :capture)
        expect(prompt).to include("preferred_provider")
        expect(prompt).to include("CLOSED SET")
        expect(prompt).to include("Pro Cloud")
      end

      it "build_brief_prompt falls back to the generic provider rule without a catalog" do
        allow(described_class).to receive(:provider_catalog_available?).and_return(false)
        prompt = service.send(:build_brief_prompt, "deploy on Hetzner", {}, :capture)
        expect(prompt).to include("preferred_provider")
        expect(prompt).to match(/AWS|Hetzner|DigitalOcean|GCP|Azure/i)
        expect(prompt).to include("lowercase")
      end
    end
  end

  describe "#refine" do
    let(:prior_brief) do
      {
        "intent" => "Postgres cluster",
        "use_case" => "OLTP",
        "scale" => { "initial" => 3, "target" => 5, "growth_profile" => "linear" },
        "regions" => ["us-east-1"],
        "compliance" => [],
        "budget_cap_usd_monthly" => 200.0,
        "latency_targets_ms" => { "p99" => nil },
        "data_residency" => [],
        "preferred_provider" => nil
      }
    end

    before do
      allow(service).to receive(:extract_brief_from_llm).and_return(
        "regions" => ["us-east-1", "eu-west-1"],
        "latency_targets_ms" => { "p99" => 100 },
        "compliance" => ["SOC2"]
      )
    end

    it "merges new fields onto the prior brief without losing existing values" do
      result = service.refine(brief: prior_brief, clarification: "Add EU presence and SOC2; aim for p99 100ms")

      expect(result[:brief]["intent"]).to eq("Postgres cluster")
      expect(result[:brief]["regions"]).to match_array(["us-east-1", "eu-west-1"])
      expect(result[:brief]["compliance"]).to eq(["SOC2"])
      expect(result[:brief]["latency_targets_ms"]["p99"]).to eq(100)
    end

    it "reports an empty missing_fields list when the merged brief is complete" do
      result = service.refine(brief: prior_brief, clarification: "anything")
      expect(result[:missing_fields]).to be_empty
    end
  end

  describe "#classify" do
    it "routes obvious provisioning utterances via the regex prefilter" do
      result = service.classify(natural_language: "Please provision a 3-node cluster for me")
      expect(result[:intent_type]).to eq(described_class::INTENT_PROVISION)
      expect(result[:confidence]).to be >= 0.6
    end

    it "scales confidence with multiple keyword matches" do
      one = service.classify(natural_language: "deploy this")[:confidence]
      many = service.classify(natural_language: "provision and deploy and scale a stack cluster")[:confidence]
      expect(many).to be > one
    end

    it "falls through to the LLM classifier on ambiguous input" do
      allow(service).to receive(:classify_with_llm).and_return(
        intent_type: described_class::INTENT_GENERAL, confidence: 0.7
      )

      result = service.classify(natural_language: "what time is it?")
      expect(result[:intent_type]).to eq(described_class::INTENT_GENERAL)
      expect(result[:confidence]).to eq(0.7)
    end

    it "returns a low-confidence general_chat default when the LLM is unavailable" do
      allow(service).to receive(:llm_client).and_return(nil)
      result = service.classify(natural_language: "tell me about cats")
      expect(result[:intent_type]).to eq(described_class::INTENT_GENERAL)
      expect(result[:confidence]).to eq(0.3)
    end

    it "handles empty input gracefully" do
      result = service.classify(natural_language: "")
      expect(result[:intent_type]).to eq(described_class::INTENT_GENERAL)
      expect(result[:confidence]).to eq(0.0)
    end

    # Regression: INTENT_KEYWORDS was unanchored, so keyword SUBSTRINGS inside ordinary
    # words (ghost→host, downscale→scale, stacks→stack, provisional→provision, hostname→host)
    # matched and short-circuited to provision_infrastructure, bypassing the LLM fallback.
    context "keyword anchoring (no substring false positives)" do
      before { allow(service).to receive(:classify_with_llm).and_return(nil) }

      [
        "a ghost story",
        "downscale my expectations",
        "stacks of paperwork",
        "we reached a provisional agreement",
        "what is the hostname here"
      ].each do |phrase|
        it "does not classify #{phrase.inspect} as provisioning" do
          result = service.classify(natural_language: phrase)
          expect(result[:intent_type]).not_to eq(described_class::INTENT_PROVISION)
        end
      end

      it "still classifies whole-word keyword utterances as provisioning" do
        result = service.classify(natural_language: "provision a host for me")
        expect(result[:intent_type]).to eq(described_class::INTENT_PROVISION)
      end
    end
  end

  describe "constants" do
    it "exposes BRIEF_SCHEMA, REQUIRED_FIELDS, and INTENT_KEYWORDS" do
      expect(described_class::BRIEF_SCHEMA).to be_frozen
      expect(described_class::REQUIRED_FIELDS).to eq(%i[intent use_case scale regions budget_cap_usd_monthly])
      expect("provision a cluster").to match(described_class::INTENT_KEYWORDS)
      expect("what is the weather").not_to match(described_class::INTENT_KEYWORDS)
    end
  end
end
