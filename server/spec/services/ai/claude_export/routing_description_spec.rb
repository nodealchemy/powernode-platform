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

  # HIER-P2G item 3 — the seed's OWN routing sentence. The wave-2 agent seeds
  # hand-author a "Use when …" sentence in the agent description precisely
  # because HIER-P1B exports it verbatim as the Claude Code routing
  # description; the renderer took only the FIRST sentence of the description
  # (a summary) and dropped that sentence from every committed skeleton. It is
  # the most specific trigger the agent has, so it is pinned: never dropped for
  # the MAX_CHARS budget, never truncated — derived triggers give way first,
  # then derived text is truncated.
  describe "the seed's own routing sentence" do
    let(:storage_description) do
      "Storage data plane — assignments and their reconciliation, volumes, snapshots, restores (copy-swap), " \
        "migrations, chown, NFS exports. Use when the task is about protecting, moving or restoring data on " \
        "a volume. Do not use for placement or capacity (use Capacity Manager) or node lifecycle (use Fleet Autonomy)."
    end
    let(:routing_sentence) { "Use when the task is about protecting, moving or restoring data on a volume." }

    it "keeps the hand-authored 'Use when …' sentence whole after the derived triggers" do
      text = described_class.build(agent(name: "Storage Manager", description: storage_description),
                                   skills: [], domains: %w[storage], siblings: [])

      expect(text).to include("involves storage; storage data plane — assignments")
      expect(text).to include(routing_sentence)
      expect(text).not_to include("Do not use for placement")
    end

    it "never drops or truncates it for the budget — derived triggers go first, then derived text" do
      skills = 6.times.map { |i| skill(name: "Storage Skill Number #{i} With A Long Name", description: "d" * 80, tags: %w[storage volume snapshot]) }
      sibling = { key: "capacity-manager", name: "Capacity Manager", domains: %w[capacity], agent_type: "monitor" }

      text = described_class.build(agent(name: "Storage Manager", description: storage_description),
                                   skills: skills, domains: %w[storage], siblings: [ sibling ])

      expect(text.length).to be <= described_class::MAX_CHARS
      expect(text).to include(routing_sentence)
      expect(text).to include("Do not use for")
    end

    it "yields derived text, one part at a time then by truncation, before the pinned sentence" do
      pinned = "Use when the task is about protecting data on a volume."
      parts = [ "storage", "Snapshot Volume", "Restore Volume", "volumes and snapshots and restores" ]

      roomy = described_class.fit_triggers(parts, 400, pinned: pinned)
      expect(roomy).to eq("Use this agent when the task involves storage; Snapshot Volume; Restore Volume; " \
                          "volumes and snapshots and restores. #{pinned}")

      squeezed = described_class.fit_triggers(parts, pinned.length + 1 + "Use this agent when the task involves storage; Snapshot Volume.".length, pinned: pinned)
      expect(squeezed).to eq("Use this agent when the task involves storage; Snapshot Volume. #{pinned}")

      truncated = described_class.fit_triggers(parts, pinned.length + 1 + "Use this agent when the task involves stor….".length, pinned: pinned)
      expect(truncated).to eq("Use this agent when the task involves stor…. #{pinned}")

      only_pinned = described_class.fit_triggers(parts, pinned.length, pinned: pinned)
      expect(only_pinned).to eq(pinned)
    end

    it "does not double the sentence when it is also the description's first sentence" do
      text = described_class.build(agent(name: "Solo", description: "Use when a node must be quarantined. Quarantines nodes."),
                                   skills: [], domains: [], siblings: [])

      expect(text.scan("Use when a node must be quarantined").size).to eq(1)
      expect(text).to include("involves quarantines nodes.")
    end
  end

  # HIER-P2G item 3 — the exclusion sibling. A seed that writes "Do not use for
  # placement or capacity (use Capacity Manager)" has named its neighbour; that
  # beats any vocabulary score. Vocabulary (including the extension's policy
  # domains) ranks the rest.
  describe "the exclusion sibling" do
    it "names the sibling the agent's own description points at, ahead of the vocabulary-adjacent one" do
      storage = agent(name: "Storage Manager",
                      description: "Storage data plane — volumes, snapshots, restores, migrations, data protection. " \
                                   "Do not use for placement or capacity (use Capacity Manager).")
      # Shares far more vocabulary with the storage agent than the named sibling does.
      curator = { key: "knowledge-graph-curator", name: "Knowledge Graph Curator", agent_type: "assistant",
                  domains: [], topics: [ "data analyst", "business search" ],
                  vocabulary: %w[storage data plane volumes snapshots restores migrations protection].to_set }
      capacity = { key: "capacity-manager", name: "Capacity Manager", agent_type: "monitor",
                   domains: %w[capacity], topics: [ "capacity", "placement" ], vocabulary: %w[capacity placement].to_set }

      text = described_class.build(storage, skills: [], domains: %w[storage], siblings: [ curator, capacity ])

      expect(text).to include("use `capacity-manager` (Capacity Manager) instead")
      expect(text).not_to include("knowledge-graph-curator")
    end

    it "ranks by shared vocabulary including the policy domains when the description names nobody" do
      storage = agent(name: "Storage Manager", description: "Moves and protects data.")
      capacity = { key: "capacity-manager", name: "Capacity Manager", agent_type: "monitor",
                   domains: %w[capacity storage], topics: [ "capacity", "storage" ], vocabulary: %w[capacity storage].to_set }
      curator = { key: "knowledge-graph-curator", name: "Knowledge Graph Curator", agent_type: "assistant",
                  domains: [], topics: [ "business search" ], vocabulary: %w[business search].to_set }

      text = described_class.build(storage, skills: [], domains: %w[storage], siblings: [ curator, capacity ])

      expect(text).to include("`capacity-manager`")
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

    # HIER-P2G: feeding the bound SKILLS into the vocabulary made the score a
    # RAW overlap count over a set whose size varies wildly — and the hub agent
    # (System Concierge binds nearly every system skill, so its vocabulary is
    # close to the union of everyone else's) then out-shared every specialist's
    # true neighbour, winning the exclusion slot for six unrelated agents. That
    # is the same standing bias the foreign-topic ranking had, one level down.
    # Normalising by the union charges a sibling for what it does NOT share.
    it "does not let a vocabulary-rich hub agent win the exclusion for every specialist" do
      planner = agent(name: "Storage Migration Planner", description: "Plans storage migrations between volumes.")
      volumes = agent(name: "Storage Volume Operator", description: "Attaches, snapshots and restores storage volumes.")
      cve     = agent(name: "CVE Responder", description: "Triages CVEs and plans upgrades.", agent_type: "monitor")
      hub     = agent(name: "System Concierge", description: "Operator chat for the whole system extension surface.")

      # The hub binds a superset of everyone's vocabulary (distinct rows, same words).
      hub_skills = [
        "Hub Plan Storage Migration", "Hub Snapshot Storage Volume", "Hub Restore Storage Volume",
        "Hub Attach Storage Volume", "Hub Triage CVE Exposure", "Hub Generate CVE Runbook",
        "Hub Deploy Platform Release", "Hub Compose Reverse Proxy", "Hub Recommend Fleet Capacity",
        "Hub Provision Infrastructure", "Hub Refresh Package Module", "Hub Expose Service Publicly",
        "Hub Discover Packages By Intent", "Hub Maintain Platform Schedule"
      ].map { |name| skill(name: name, description: "#{name} skill.", tags: name.downcase.split - %w[hub]) }

      by_key = described_class.build_all(
        [ planner, volumes, cve, hub ],
        skills_by_agent: {
          planner.id => [ skill(name: "Plan Storage Migration", description: "Plans a migration.", tags: %w[storage migration]) ],
          volumes.id => [ skill(name: "Snapshot Storage Volume", description: "Snapshots a volume.", tags: %w[storage volume]) ],
          cve.id     => [ skill(name: "Triage CVE Exposure", description: "Triages a CVE.", tags: %w[cve security]) ],
          hub.id     => hub_skills
        },
        domains_by_agent: {}
      )

      # Each specialist names its true neighbour, not the hub that lexically
      # contains it.
      expect(by_key[planner.slug]).to include("`#{volumes.slug}`")
      expect(by_key[volumes.slug]).to include("`#{planner.slug}`")
      expect(by_key[planner.slug]).not_to include("`#{hub.slug}`")
      expect(by_key[volumes.slug]).not_to include("`#{hub.slug}`")

      # And the property behind it: no single sibling is the answer for more
      # than half the set.
      excluded = by_key.values.map { |text| text[/use `([a-z0-9-]+)` \(/, 1] }.compact
      expect(excluded.size).to eq(by_key.size)
      expect(excluded.tally.values.max).to be <= (by_key.size / 2)
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
