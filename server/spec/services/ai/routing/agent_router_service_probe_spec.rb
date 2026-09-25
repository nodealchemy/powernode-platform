# frozen_string_literal: true

require "rails_helper"

# IMP-dfca08b9b412 — BEHAVIOURAL routing probes, one per Fable-review task
# category (fleet boot-image drift, volume restore, a CVE task, ingress
# exposure, docs, platform development). Each asserts WHICH AGENT WINS for a
# realistic, natural-language task description — never the tokenizer or
# domain_matches? directly — so a regression that keeps every unit passing
# while the wrong agent wins again is caught here.
#
# FIXTURE-VS-SEED DECISION (asked for explicitly, not incidental): fixtures,
# built to FAITHFULLY MIRROR the real canonical agents this defect was found
# against — real names, real seeded descriptions (verbatim from
# server/db/seeds/ai_engineering_agents_seed.rb and
# extensions/system/server/db/seeds/system_*_agent.rb), the real declared
# policy domains (from PolicyDeclarations / PolicyDomainTable::PREFIXES), and the real
# bound skills (from platform_skill_assignments_seed.rb) where one exists —
# rather than routing against the live seeded database. Reasons:
#   1. The live seeded set is non-deterministic input for a spec (account
#      rows, trust scores and skill bindings drift with every seed change),
#      so a spec built on it would rot silently rather than fail loudly.
#   2. #route's scoring is a pure function of (agent attributes, its
#      InterventionPolicy domains, its bound skills, task text) — nothing
#      here depends on the wider seeded graph (accounts, providers, other
#      unrelated agents) that only a full seed run could supply.
#   3. Faithful fixtures were load-bearing during triage: the router's
#      #skill_matches / domain-corroboration profile is built from
#      agent.description and bound Ai::Skill#description/#tags VERBATIM, so a
#      fixture using paraphrased text would silently under- or over-state
#      real overlap. Two probes ("volume restore", "docs") only reproduced the
#      correct fix once the REAL bound skill (restore_volume,
#      documentation-writer) was added — a fixture with no skills at all
#      showed a wider failure than the live agent set actually has. Do not
#      "simplify" these fixtures back to bare name+description; that
#      regresses the fixtures to a shape that already misled one round of
#      this investigation.
#
# Do NOT "fix" this spec by feeding platform.discover_skills into the router —
# that is the wholesale redesign the operator explicitly ruled out for this
# task. The fix lives in Ai::Routing::AgentRouterService's four named
# mechanisms only.
RSpec.describe "platform.route_task behavioural probes (IMP-dfca08b9b412)" do
  let(:account) { create(:account) }
  let(:provider) { create(:ai_provider, account: account, provider_type: "openai", is_active: true) }
  subject(:router) { Ai::Routing::AgentRouterService.new(account: account) }

  def global_agent(name:, description:, agent_type: "monitor")
    create(:ai_agent, :global, is_system: true, name: name, description: description, agent_type: agent_type, status: "active")
  end

  def domain_policy(agent, category)
    Ai::InterventionPolicy.create!(account: account, agent: agent, scope: "agent",
                                    action_category: category, policy: "require_approval", priority: 10)
  end

  # Real seeded descriptions, verbatim.
  let!(:cve) do
    global_agent(name: "CVE Responder",
                 description: "CVE intake + remediation — SBOM ingest, exposure scan, patch orchestration")
  end
  let!(:ingress) do
    global_agent(name: "Ingress Manager",
                 description: "Owns service exposure and certificate issuance: local publish, public TCP/HTTPS " \
                              "exposure, ACME DNS-01 issuance, backend sets")
  end
  let!(:disk_image) do
    global_agent(name: "Disk Image Manager",
                 description: "Disk-image CI orchestrator: build, verify, promote, rollback and retention of " \
                              "fleet boot publications")
  end
  let!(:storage) do
    global_agent(name: "Storage Manager",
                 description: "Data-protection reconciler: storage assignments, volume lifecycle, snapshots and restores")
  end
  let!(:docs) do
    global_agent(name: "Documentation Specialist", agent_type: "content_generator",
                 description: "Keeps the platform's documentation truthful: concept and guide pages, runbooks, " \
                              "KB articles, reference pages")
  end
  let!(:dev) do
    global_agent(name: "Platform Developer", agent_type: "code_assistant",
                 description: "Drains the dev-improve loop as the platform's always-on code executor: claims a " \
                              "task, verifies, fixes, tests, reports")
  end
  # The router's actual competitor on every probe below: a domain-less
  # generalist that carries the NEUTRAL_DOMAIN floor (0.25) unconditionally,
  # per the real infrastructure-generalist canonical (extensions/system/server
  # /db/seeds/system_concierge_agent.rb — renamed from "System Concierge" in
  # that extension seed; NOT via any core migration, and its slug is written
  # explicitly as "infrastructure-generalist" in the same seed, so it is not
  # the stale/unspawnable slug the original finding attributed to a core
  # rename — see the re-verification notes on IMP-dfca08b9b412).
  let!(:generalist) do
    global_agent(name: "Infrastructure Generalist", agent_type: "assistant",
                 description: "Operator chat agent for the full system extension surface (fleet, SDWAN, " \
                              "container runtimes, modules, disk image CI) — read-only by default, dispatches " \
                              "state-changing skills with operator confirmation")
  end

  before do
    # Real domain categories (PolicyDomainTable::PREFIXES / PolicyDeclarations) — not
    # invented ones — so domain_matches? is exercised against the same
    # category strings the extension actually registers.
    domain_policy(cve, "system.cve_remediate")
    domain_policy(cve, "system.cve_exposure_scan")
    domain_policy(ingress, "system.expose_service_publicly")
    domain_policy(ingress, "system.acme_certificate_provision")
    domain_policy(disk_image, "system.disk_image_publication_promote")
    domain_policy(storage, "system.restore_volume")
    domain_policy(storage, "system.volume_snapshot_due")
    domain_policy(dev, "dev.task_claim")
    domain_policy(dev, "dev.campaign_propose")
    domain_policy(docs, "docs.update")

    # Real bound skills, verbatim (name/slug/tags/description) from the
    # system extension's chat-skill catalog (extensions/system/server/db/
    # seeds/system_skills_seed.rb) bound via the executors' real `binds_to`
    # (extensions/system/server/app/services/system/ai/skills/*_executor.rb),
    # and from platform_skill_assignments_seed.rb for the two core agents.
    # TAGS matter now (review round 2, F2): domain corroboration reads only
    # each skill's name + tags, so a skill fixture with a plausible
    # description but no real tags would silently under-test the tightened
    # path — every skill below carries its real seeded tags, not invented ones.
    bind_skill = ->(agent, name:, slug:, tags:, description: "irrelevant to corroboration — tags/name only") do
      skill = create(:ai_skill, :global, slug: slug, name: name, category: "devops", tags: tags, description: description)
      create(:ai_agent_skill, agent: agent, skill: skill, is_active: true)
    end

    bind_skill.call(storage, name: "Restore Volume", slug: "system-restore-volume",
                     tags: %w[storage volumes snapshot restore disaster-recovery])

    bind_skill.call(cve, name: "CVE Response", slug: "system-cve-response", tags: %w[cve security fleet exposure])
    bind_skill.call(cve, name: "CVE Runbook Generate", slug: "system-cve-runbook-generate",
                     tags: %w[cve security runbook documentation])

    bind_skill.call(ingress, name: "Expose Service Publicly", slug: "system-expose-service-publicly",
                     tags: %w[platform sdwan vip port-mapping acme reverse-proxy expose public])
    bind_skill.call(ingress, name: "Expose Service Locally", slug: "system-expose-service-local",
                     tags: %w[platform sdwan service expose local forward-auth reverse-proxy svc])
    bind_skill.call(ingress, name: "ACME Certificate Provision", slug: "system-acme-certificate-provision",
                     tags: %w[platform acme certificates tls issuance provision])

    bind_skill.call(disk_image, name: "Disk Image Promote", slug: "system-disk-image-promote",
                     tags: %w[disk-image publication promote boot-image release])
    bind_skill.call(disk_image, name: "Disk Image Rollback", slug: "system-disk-image-rollback",
                     tags: %w[disk-image publication rollback revert boot-image])

    bind_skill.call(docs, name: "Documentation Writer", slug: "documentation-writer",
                     tags: %w[documentation api-docs adr])

    bind_skill.call(dev, name: "Extension Developer", slug: "extension-developer",
                     tags: %w[extensions feature-gating submodule])
  end

  # Cause (b): domain_matches? is a literal-token match ("disk_image" ->
  # tokens disk/image); a task that describes the SITUATION rather than
  # naming the domain never reaches it on its own. Fixed by
  # #domain_corroborated? falling back to the agent's CURATED skill corpus
  # (name + tags — see the review-round-2 note in the service). Never says
  # "disk"/"image" (the literal domain tokens); does say "promote", "publication"
  # and "boot" — real tags on the real Disk Image Promote skill.
  #
  # LENGTH IS LOAD-BEARING HERE (review round 2, R1 red-first re-check): a
  # short task built around only those 2-3 matching words also gives the
  # (pre-existing, unmodified) SKILL dimension enough of a ratio to win on
  # UNFIXED code by itself — red-first against reverted production code
  # caught this directly (5 of 6 short-worded probes passed with NO fix
  # applied, domain: 0.0 in every winning breakdown). The extra, unrelated
  # sentence length here is not padding for its own sake: it dilutes
  # #skill_matches' matched/total ratio (a realistic task is rarely 6 words)
  # so the win depends on #domain_corroborated? actually firing — confirmed
  # by breakdown on fixed code: skill 0.094, domain 0.6.
  it "routes fleet boot-image drift to the Disk Image Manager" do
    result = router.route(task: "Several operators have noticed that new instances on this platform still come " \
                                "up running an older baseline than what landed last week, which is confusing " \
                                "everyone during support calls — the fix is to promote the current publication " \
                                "so new instances boot the right version going forward.")
    expect(result[:agent_id]).to eq(disk_image.id)
  end

  # Cause (b), and the concrete reason the fixture carries the REAL Restore
  # Volume skill and its real tags (see the file header): never says
  # "storage" (the literal domain word); does say "restore", "volume" and
  # "snapshot" — real tags/name tokens on that skill. Diluted length for the
  # same reason as the probe above (see its comment) — confirmed by
  # breakdown: skill 0.154, domain 0.6 on fixed code; skill 0.0, domain 0.25
  # (the generalist's floor, uncontested) on unfixed code.
  it "routes a volume restore to the Storage Manager" do
    result = router.route(task: "The team accidentally deleted some files from this instance during a bad " \
                                "deploy this afternoon and everyone's worried the data is gone for good, but I " \
                                "think we can restore the volume from a recent snapshot before this turns into " \
                                "a bigger incident.")
    expect(result[:agent_id]).to eq(storage.id)
  end

  # Cause (a): MIN_TASK_WORD = 4 discarded the 3-character domain name "cve"
  # unconditionally, so CVE Responder could never match its OWN domain no
  # matter how the task was phrased. Fixed by domain_words_of (unfiltered)
  # feeding domain_matches? instead of the length-filtered task_words. This
  # one did NOT need dilution — it reaches domain 1.0 via the literal path
  # (domain_matches?, not corroboration), which is a binary "the word is
  # there or it isn't" and was never diluted by task length in the first
  # place; confirmed reddening cleanly at its original short length in both
  # the review-round-1 and round-2 red-first runs.
  it "routes a CVE task to the CVE Responder" do
    result = router.route(task: "Triage the new critical CVE and plan a remediation rollout for the affected modules.")
    expect(result[:agent_id]).to eq(cve.id)
  end

  # Cause (b), the finding's own example: never says "ingress" (the literal
  # domain word); does say "expose" and "public" — real tags on the Ingress
  # Manager's real Expose Service Publicly skill. Diluted for the same reason
  # as the two probes above — confirmed by breakdown: skill 0.143, domain 0.6
  # on fixed code; skill 0.0, domain 0.25 on unfixed code.
  it "routes an ingress exposure task to the Ingress Manager" do
    result = router.route(task: "Our customers keep asking whether they can reach this internal backend from " \
                                "their own home networks without any special access, and the answer needs to " \
                                "be yes going forward — please expose it to the public internet so it works " \
                                "for everyone outside our office.")
    expect(result[:agent_id]).to eq(ingress.id)
  end

  # Cause (b) again: never says "docs" (the literal domain word); does say
  # "API" and "documentation" — two real tags on the real Documentation
  # Writer skill (tags include "api-docs", split into "api"/"docs" by
  # #domain_corroboration_tokens_for the same way a compound domain name
  # splits). Diluted for the same reason as the probes above — confirmed by
  # breakdown: skill 0.107, domain 0.6 on fixed code; skill 0.036, domain
  # 0.25 (generalist wins) on unfixed code.
  it "routes a docs task to the Documentation Specialist" do
    result = router.route(task: "New engineers keep asking the same onboarding questions about how our " \
                                "endpoints behave under edge cases, and nobody has time to answer them " \
                                "individually anymore, so somebody should really sit down and write proper " \
                                "API documentation covering the common scenarios.")
    expect(result[:agent_id]).to eq(docs.id)
  end

  # Cause (b), and review round 2's precision fix made this one routable at
  # all: the ORIGINAL short wording ("a bug in the routing service") gave
  # Ingress Manager a false-positive single-token hit on "service" that
  # outscored Platform Developer's zero — exactly the F2 finding. Rephrased
  # to avoid both "dev" (the literal domain word, 3 chars — cause (a)
  # territory) and "service" (the false-positive word), while still saying
  # "extension", "feature" and "gating" — real tokens on Platform Developer's
  # real Extension Developer skill (name + the "feature-gating" tag).
  # Diluted for the same reason as the probes above — confirmed by
  # breakdown: skill 0.119, domain 0.6 on fixed code; skill 0.024, domain
  # 0.25 (generalist wins) on unfixed code.
  it "routes a generic platform-development bug-fix task to the Platform Developer" do
    result = router.route(task: "We've been getting sporadic reports from a handful of customers that some " \
                                "parts of the interface behave inconsistently depending on which account " \
                                "they're logged into, and after digging through the logs for a while it looks " \
                                "like the root cause is somewhere in how the extension handles its feature " \
                                "gating logic — needs a proper fix plus a regression test so it doesn't come back.")
    expect(result[:agent_id]).to eq(dev.id)
  end

  # STILL OPEN — kept as a SEVENTH, separate example rather than folded into
  # the passing one above (review round 2, R2). The probe above proves
  # Platform Developer routes correctly when a task shares real tag
  # vocabulary with its bound skills; it does NOT prove the router handles a
  # task that shares NONE. This is that second, harder case, and it still
  # fails: a fully generic bug-fix task with no curated-tag overlap and no
  # literal "dev" (3 characters, filtered out of the length-filtered path but
  # never actually present here either) has nothing for either domain
  # mechanism to match, and loses to whichever competitor picks up an
  # incidental word or to the generalist's unconditional 0.25 NEUTRAL_DOMAIN
  # floor. Traces to TaskComplexityClassifierService's flat ~0.125/economy
  # score for any short single-message task and to
  # AgentRouterService::NEUTRAL_DOMAIN — both mechanisms the operator ruled
  # out of scope for IMP-dfca08b9b412 and asked to have filed separately
  # rather than fixed here. `pending`, not deleted or reworded away, so a
  # future change to either mechanism flips this GREEN and RSpec flags that
  # as a fix rather than the limitation silently vanishing.
  it "routes a generic platform-development bug-fix task with NO shared tag vocabulary to the Platform Developer" do
    pending "residual: no curated-tag overlap available at all — traces to the complexity classifier's flat " \
            "~0.125/economy score and NEUTRAL_DOMAIN's unconditional floor, both out of scope for this task"
    result = router.route(task: "There's a bug in the routing service — go fix it and add a test.")
    expect(result[:agent_id]).to eq(dev.id)
  end
end
