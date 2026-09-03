# frozen_string_literal: true

require "rails_helper"

# HIER-P1B item 9 — Claude Code's Agent tool routes on `description`, so the
# exported description must carry concrete triggers ("Use this agent when …")
# and an exclusion naming the sibling that owns the adjacent domain ("Do not
# use for …"). Bounded at MAX_CHARS so the Agent-tool prompt stays compact.
RSpec.describe Ai::ClaudeExport::RoutingDescription do
  let(:account) { create(:account) }

  def agent(name:, description:, agent_type: "assistant")
    create(:ai_agent, account: account, name: name, description: description, agent_type: agent_type)
  end

  def skill(name:, description:, tags: [])
    create(:ai_skill, account: account, name: name, description: description, tags: tags)
  end

  describe ".build" do
    it "starts with a trigger clause and carries an exclusion clause" do
      text = described_class.build(agent(name: "Fleet Autonomy", description: "Reconciles node and module drift."),
                                   skills: [], domains: [], siblings: [])

      expect(text).to start_with("Use this agent when")
      expect(text).to include("Do not use for")
    end

    it "derives triggers from policy domains, bound skills and the agent description" do
      s = skill(name: "Rotate Certificates", description: "Rotates fleet TLS certificates.", tags: %w[tls acme])
      text = described_class.build(agent(name: "Fleet Autonomy", description: "Reconciles node and module drift."),
                                   skills: [ s ], domains: %w[storage], siblings: [])

      expect(text).to include("storage")
      expect(text).to include("Rotate Certificates")
      expect(text).to include("drift")
    end

    it "reads the description mid-sentence without breaking a leading acronym" do
      plain = described_class.build(agent(name: "A", description: "Reconciles drift."), skills: [], domains: [], siblings: [])
      acronym = described_class.build(agent(name: "B", description: "SDWAN reconciler for peers."), skills: [], domains: [], siblings: [])

      expect(plain).to include("involves reconciles drift.")
      expect(acronym).to include("involves SDWAN reconciler for peers.")
    end

    it "names the sibling owning the adjacent domain in the exclusion" do
      sibling = { key: "sdwan-manager", name: "SDWAN Manager", domains: %w[sdwan], agent_type: "monitor" }
      text = described_class.build(agent(name: "Fleet Autonomy", description: "Reconciles drift."),
                                   skills: [], domains: %w[cve], siblings: [ sibling ])

      expect(text).to include("Do not use for sdwan")
      expect(text).to include("`sdwan-manager`")
    end

    it "falls back to a generic exclusion when no sibling exists" do
      text = described_class.build(agent(name: "Solo", description: "Does one thing."),
                                   skills: [], domains: [], siblings: [])

      expect(text).to include("Do not use for")
      expect(text).to include("general-purpose")
    end

    it "stays under MAX_CHARS even for a verbose agent, keeping the exclusion clause intact" do
      verbose = agent(name: "Verbose", description: ("verbose detail " * 60).strip)
      skills = 6.times.map { |i| skill(name: "Skill Number #{i} With A Long Name", description: "d" * 80, tags: %w[a b c]) }
      sibling = { key: "sibling-agent", name: "Sibling", domains: %w[gitops], agent_type: "monitor" }

      text = described_class.build(verbose, skills: skills, domains: %w[cve storage], siblings: [ sibling ])

      expect(text.length).to be <= described_class::MAX_CHARS
      expect(text).to include("Do not use for gitops")
      expect(text).to include("`sibling-agent`")
    end
  end

  # The property the brief pins, walked over a canonical-shaped set through the
  # same batch entry point the exporter uses (siblings computed internally).
  describe ".build_all" do
    it "gives every agent at least one trigger, one exclusion, and stays under MAX_CHARS" do
      sdwan = agent(name: "SDWAN Manager", description: "Manages SD-WAN peers and route policies.", agent_type: "monitor")
      cve   = agent(name: "CVE Responder", description: "Triages CVEs and plans upgrades.", agent_type: "monitor")
      chat  = agent(name: "System Concierge", description: "Operator chat for the system extension surface.")
      plain = agent(name: "Strategic Planner", description: "")

      by_key = described_class.build_all(
        [ sdwan, cve, chat, plain ],
        skills_by_agent: { chat.id => [ skill(name: "Provision Infrastructure", description: "Provisions a stack.") ] },
        domains_by_agent: { sdwan.id => %w[sdwan], cve.id => %w[cve] }
      )

      expect(by_key.keys).to contain_exactly(sdwan.slug, cve.slug, chat.slug, plain.slug)
      by_key.each_value do |text|
        expect(text).to match(/\AUse this agent when \S/)
        expect(text).to match(/Do not use for \S/)
        expect(text.length).to be <= described_class::MAX_CHARS
      end
      expect(by_key[sdwan.slug]).to include("`#{cve.slug}`")
      expect(by_key[cve.slug]).to include("`#{sdwan.slug}`")
    end

    # The exclusion is a ROUTING signal, so it must name the NEIGHBOUR — the
    # sibling whose subject matter overlaps this agent's and could be confused
    # with it (SDWAN Manager vs Fleet Autonomy). Ranking siblings on foreign-topic
    # count alone made the globally topic-richest agent the answer for EVERY
    # agent (22 of 23 canonical descriptions excluded the same one), which is not
    # a signal but a standing bias in Claude Code's automatic delegation.
    it "excludes the vocabulary-adjacent sibling, not the globally topic-richest one" do
      storage = agent(name: "Storage Migration Planner", description: "Plans storage migrations between volumes.")
      volumes = agent(name: "Storage Volume Operator", description: "Attaches, snapshots and restores storage volumes.")
      # Deliberately the topic-richest agent AND sharing no vocabulary with the
      # other two: under the old rule it won every exclusion.
      richest = agent(name: "Fleet Autonomy", description: "Reconciles node and module drift.", agent_type: "monitor")

      by_key = described_class.build_all(
        [ storage, volumes, richest ],
        skills_by_agent: {
          storage.id => [ skill(name: "Plan Storage Migration", description: "Plans a migration.", tags: %w[storage migration]) ],
          volumes.id => [ skill(name: "Snapshot Storage Volume", description: "Snapshots a volume.", tags: %w[storage volume]) ],
          richest.id => [
            skill(name: "Reap Instance", description: "Reaps an instance.", tags: %w[reap]),
            skill(name: "Replace Instance", description: "Replaces an instance.", tags: %w[replace]),
            skill(name: "Promote Replica", description: "Promotes a replica.", tags: %w[promote]),
            skill(name: "Refresh Package Module", description: "Refreshes a module.", tags: %w[refresh]),
            skill(name: "Cordon Instance", description: "Cordons an instance.", tags: %w[cordon]),
            skill(name: "Reconcile Node Drift", description: "Reconciles drift.", tags: %w[reconcile])
          ]
        },
        domains_by_agent: {}
      )

      expect(by_key[storage.slug]).to include("`#{volumes.slug}`")
      expect(by_key[volumes.slug]).to include("`#{storage.slug}`")
      expect(by_key[storage.slug]).not_to include("`#{richest.slug}`")
    end

    # Determinism: the freshness gate diffs the committed files byte for byte.
    it "renders the same exclusion on a re-run with the agents in a different order" do
      one   = agent(name: "SDWAN Manager", description: "Manages SD-WAN peers and route policies.", agent_type: "monitor")
      two   = agent(name: "Fleet Autonomy", description: "Reconciles node and module drift.", agent_type: "monitor")
      three = agent(name: "CVE Responder", description: "Triages CVEs and plans upgrades.", agent_type: "monitor")

      first = described_class.build_all([ one, two, three ], skills_by_agent: {}, domains_by_agent: {})
      again = described_class.build_all([ three, one, two ], skills_by_agent: {}, domains_by_agent: {})

      expect(again).to eq(first)
    end
  end
end
