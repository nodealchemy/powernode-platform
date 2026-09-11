# frozen_string_literal: true

require "rails_helper"

# Component status plane, increment A6 — the investigation (design §5.3).
RSpec.describe Platform::InvestigationService do
  let(:account) { create(:account) }
  let(:service) { described_class.new(account: account) }

  let(:component) do
    create(:platform_component_status, account: account, component_kind: "docker_host",
                                       component_ref: "host-1", display_name: "web-1",
                                       verdict: Platform::ComponentStatus::DOWN,
                                       conditions: [ failing_condition ])
  end

  let(:failing_condition) do
    { "type" => "Connected", "status" => false, "reason" => "ConnectionError",
      "severity" => "down", "message" => "unreachable", "evidence" => {},
      "last_transition_at" => 10.minutes.ago }
  end

  around do |example|
    saved_sources = Platform::Investigation::EvidenceSources.handlers.dup
    saved_triggers = Platform::Investigation::Triggers.kinds
    Platform::Investigation::EvidenceSources.reset!
    Platform::Investigation::Triggers.reset!
    example.run
  ensure
    Platform::Investigation::EvidenceSources.reset!
    Platform::Investigation::Triggers.reset!
    saved_sources.each { |name, handler| Platform::Investigation::EvidenceSources.register(name, handler) }
    saved_triggers.each { |kind| Platform::Investigation::Triggers.register(kind) }
  end

  describe "extending the correlator" do
    # The design says EXTENDS, not forks. If this ever became a standalone
    # class the platform would carry two definitions of "these two things are
    # related", and they would drift.
    it "is a CrossSystemCorrelator and inherits its correlation machinery" do
      expect(described_class.superclass).to eq(Ai::SelfHealing::CrossSystemCorrelator)
      expect(service).to respond_to(:correlate_failures)
      expect(described_class.instance_method(:correlate_failures).owner)
        .to eq(Ai::SelfHealing::CrossSystemCorrelator)
    end
  end

  describe "#open!" do
    it "records evidence and returns an open investigation" do
      result = service.open!(component, trigger: Platform::Investigation::TRIGGER_OPERATOR)

      investigation = result[:investigation]
      expect(result[:opened]).to be(true)
      expect(investigation).to be_open
      expect(investigation.trigger).to eq("operator")
      expect(investigation.evidence["conditions"]).to be_present
      # Ranking is the worker's. An open investigation with evidence and no
      # hypotheses is the correct product of opening one.
      expect(investigation.hypotheses).to eq([])
    end

    it "derives the fingerprint rather than taking one" do
      result = service.open!(component, trigger: "operator")

      expect(result[:investigation].fingerprint).to eq("docker_host:host-1")
    end

    it "refuses when the component does not exist" do
      expect(service.open!(nil, trigger: "operator"))
        .to eq(refused: described_class::REFUSED_NO_COMPONENT)
    end

    describe "the open-fingerprint rule" do
      it "refuses a second open investigation of the same component" do
        service.open!(component, trigger: "operator")

        expect(service.open!(component, trigger: "down"))
          .to eq(refused: described_class::REFUSED_ALREADY_OPEN)
        expect(Platform::Investigation.count).to eq(1)
      end

      # The other arm, and the reason the index is PARTIAL: a component
      # investigated last month must be investigable again.
      it "allows another once the first has concluded" do
        first = service.open!(component, trigger: "operator")[:investigation]
        first.update!(status: Platform::Investigation::STATUS_COMPLETED)

        expect(service.open!(component, trigger: "down")[:opened]).to be(true)
        expect(Platform::Investigation.count).to eq(2)
      end

      # The rule is the DATABASE's, not the service's: a check in Ruby loses to
      # two triggers firing in the same second.
      it "is enforced by the database, not only by the pre-check" do
        service.open!(component, trigger: "operator")
        duplicate = Platform::Investigation.new(
          account_id: account.id, component_kind: "docker_host", component_ref: "host-1",
          fingerprint: "docker_host:host-1",
          trigger: "down", status: Platform::Investigation::STATUS_OPEN
        )

        # Straight past the service and its pre-check, so what refuses this is
        # the index and nothing else.
        expect { duplicate.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
      end

      it "does not confuse two different components" do
        other = create(:platform_component_status, account: account, component_kind: "docker_host",
                                                   component_ref: "host-2")
        service.open!(component, trigger: "operator")

        expect(service.open!(other, trigger: "operator")[:opened]).to be(true)
      end
    end

    describe "the daily cap" do
      it "refuses past the cap and allows below it" do
        SiteSetting.set(described_class::DAILY_CAP_SETTING, 2, setting_type: "integer")
        expect(described_class.daily_cap).to eq(2)

        2.times do |n|
          row = create(:platform_component_status, account: account, component_kind: "docker_host",
                                                   component_ref: "capped-#{n}")
          expect(service.open!(row, trigger: "operator")[:opened]).to be(true)
        end

        expect(service.open!(component, trigger: "operator"))
          .to eq(refused: described_class::REFUSED_DAILY_CAP)
      end

      it "counts only the last day" do
        SiteSetting.set(described_class::DAILY_CAP_SETTING, 1, setting_type: "integer")
        old = service.open!(component, trigger: "operator")[:investigation]
        old.update!(status: Platform::Investigation::STATUS_COMPLETED,
                    created_at: 2.days.ago)

        expect(service.open!(component, trigger: "operator")[:opened]).to be(true)
      end

      it "falls back to the default for a blank or non-positive setting" do
        SiteSetting.set(described_class::DAILY_CAP_SETTING, 0, setting_type: "integer")

        expect(described_class.daily_cap).to eq(described_class::DEFAULT_DAILY_CAP)
      end
    end
  end

  # A6 review F2. For an entire increment nothing enqueued the ranking job, so
  # all three doors opened investigations that nothing ever concluded — and
  # because the open-fingerprint index releases only when a row leaves `open`,
  # "one open investigation per component" became one investigation per
  # component, ever. The enqueue lives here rather than in each door, so this
  # is the one place it can be asserted for all three.
  describe "the ranking enqueue" do
    it "enqueues the ranking job with the investigation's own id" do
      expect(WorkerJobService).to receive(:enqueue_job)
        .with("PlatformInvestigationJob", hash_including(args: [ { "investigation_id" => instance_of(String) } ]))

      service.open!(component, trigger: "operator")
    end

    it "names the job the worker actually defines" do
      captured = nil
      allow(WorkerJobService).to receive(:enqueue_job) { |name, opts| captured = [ name, opts ] }

      investigation = service.open!(component, trigger: "operator")[:investigation]

      expect(captured.first).to eq("PlatformInvestigationJob")
      expect(captured.last[:args].first["investigation_id"]).to eq(investigation.id)
    end

    # AFTER the save, never before: the job carries only an id, so one that
    # raced its own row would look up nothing.
    it "enqueues only a persisted investigation" do
      allow(WorkerJobService).to receive(:enqueue_job) do |_name, opts|
        id = opts[:args].first["investigation_id"]
        expect(Platform::Investigation.where(id: id)).to exist
      end

      service.open!(component, trigger: "operator")
    end

    # The other arm on both bounds: a refusal opened nothing, so it must
    # enqueue nothing either — otherwise a capped account still spends.
    it "enqueues nothing when the open is refused" do
      service.open!(component, trigger: "operator")
      allow(WorkerJobService).to receive(:enqueue_job)

      expect(service.open!(component, trigger: "down")[:refused]).to be_present
      expect(WorkerJobService).not_to have_received(:enqueue_job)
    end

    # The evidence is the part that decays: it describes the failure at the
    # moment it happened. An investigation with evidence and no ranking is
    # worth strictly more than no investigation, so a dead queue must not
    # discard one.
    it "still opens the investigation when the enqueue fails" do
      allow(WorkerJobService).to receive(:enqueue_job).and_raise(StandardError, "redis is down")

      result = service.open!(component, trigger: "operator")

      expect(result[:opened]).to be(true)
      expect(result[:investigation]).to be_persisted
    end
  end

  describe "#assemble_evidence" do
    it "carries every core class, present even when empty" do
      evidence = service.assemble_evidence(component)

      described_class::CORE_EVIDENCE_CLASSES.each do |name|
        expect(evidence).to have_key(name), "no #{name} class in the assembled evidence"
      end
      expect(evidence["assembled_at"]).to be_present
    end

    it "resolves the dependency chain to VERDICTS, not bare references" do
      create(:platform_component_status, account: account, component_kind: "node_instance",
                                         component_ref: "node-9", verdict: Platform::ComponentStatus::DOWN)
      component.update!(dependencies: [ { "kind" => "node_instance", "ref" => "node-9", "relation" => "hosts" } ])

      chain = service.assemble_evidence(component.reload)["dependency_chain"]

      expect(chain.first["verdict"]).to eq(Platform::ComponentStatus::DOWN)
      expect(chain.first["resolved"]).to be(true)
    end

    it "marks a dependency it cannot see as unresolved rather than dropping it" do
      component.update!(dependencies: [ { "kind" => "node_instance", "ref" => "ghost" } ])

      chain = service.assemble_evidence(component.reload)["dependency_chain"]

      expect(chain.first["resolved"]).to be(false)
      expect(chain.first["verdict"]).to be_nil
    end

    it "includes this component's status events inside the window and not outside it" do
      create(:platform_status_event, account: account, component_kind: "docker_host",
                                     component_ref: "host-1", occurred_at: 5.minutes.ago)
      create(:platform_status_event, account: account, component_kind: "docker_host",
                                     component_ref: "host-1", occurred_at: 3.hours.ago)

      events = service.assemble_evidence(component)["status_events"]

      expect(events.size).to eq(1)
    end

    it "merges whatever an extension registers, without naming one" do
      Platform::Investigation::EvidenceSources.register(:module_changes) do |component_kind:, **|
        [ { "summary" => "promoted #{component_kind} module", "occurred_at" => 1.minute.ago.iso8601 } ]
      end

      evidence = service.assemble_evidence(component)

      expect(evidence["module_changes"].first["summary"]).to include("docker_host")
      expect(evidence["errors"]).to eq({})
    end

    # A class that silently vanished would RAISE confidence in whatever
    # survived, because the rule discounts by the number of classes.
    it "records a source that raises, and still assembles the rest" do
      Platform::Investigation::EvidenceSources.register(:remediation_history) { raise "extension is down" }

      evidence = service.assemble_evidence(component)

      expect(evidence["errors"]["remediation_history"]).to include("extension is down")
      expect(evidence["conditions"]).to be_present
    end

    it "counts only classes that carry something" do
      evidence = { "conditions" => [ failing_condition ], "status_events" => [],
                   "assembled_at" => Time.current.iso8601, "errors" => {} }

      expect(described_class.evidence_classes(evidence)).to eq([ "conditions" ])
    end
  end

  # A9 review S5 — the dependency walk uses the READER's neighbourhood, not the
  # component's. For a shared component the component's account is nil, which
  # collapsed the walk to shared rows only and hid every dependent living in a
  # real account.
  describe "the neighbourhood a shared component is walked in" do
    let(:shared_component) do
      create(:platform_component_status, :shared, component_kind: "provider_circuit_breaker",
                                                   component_ref: "breaker-1",
                                                   dependencies: [ { "kind" => "docker_host", "ref" => "a-host-1",
                                                                     "relation" => "hosts" } ])
    end

    it "resolves a dependent in the READER's account" do
      create(:platform_component_status, account: account, component_kind: "docker_host",
                                         component_ref: "a-host-1", verdict: Platform::ComponentStatus::DOWN)

      chain = described_class.new(account: account).assemble_evidence(shared_component)["dependency_chain"]

      expect(chain.first["resolved"]).to be(true)
      expect(chain.first["verdict"]).to eq(Platform::ComponentStatus::DOWN)
    end

    # The tenancy arm: a reader must not resolve another tenant's row.
    it "does not resolve a dependent in ANOTHER account" do
      create(:platform_component_status, account: create(:account), component_kind: "docker_host",
                                         component_ref: "a-host-1", verdict: Platform::ComponentStatus::DOWN)

      chain = described_class.new(account: account).assemble_evidence(shared_component)["dependency_chain"]

      expect(chain.first["resolved"]).to be(false)
    end

    # No reader at all — the automatic trigger on a shared component. There is
    # no tenant whose rows could be included, so a tenant's row stays unseen.
    it "sees shared rows only when there is no reader" do
      create(:platform_component_status, account: account, component_kind: "docker_host",
                                         component_ref: "a-host-1", verdict: Platform::ComponentStatus::DOWN)

      chain = described_class.new(account: nil).assemble_evidence(shared_component)["dependency_chain"]

      expect(chain.first["resolved"]).to be(false)
    end
  end

  # A9 review S1 — whose investigation this is.
  describe "ownership" do
    let(:shared_component) do
      create(:platform_component_status, :shared, component_kind: "provider_circuit_breaker",
                                                   component_ref: "breaker-9")
    end

    it "files a shared component's investigation under the opener's account" do
      result = described_class.new(account: account).open!(shared_component, trigger: "operator")

      expect(result[:investigation].account_id).to eq(account.id)
    end

    it "keeps it shared when there is no opener — the automatic trigger" do
      result = described_class.new(account: nil).open!(shared_component, trigger: "down")

      expect(result[:investigation].account_id).to be_nil
    end

    # An account-scoped component is never re-homed, whatever a caller passes:
    # no door can file one tenant's investigation under another's id.
    it "never re-homes an account-scoped component's investigation" do
      stranger = create(:account)

      result = described_class.new(account: stranger).open!(component, trigger: "operator")

      expect(result[:investigation].account_id).to eq(account.id)
    end
  end

  # A6 re-verification G1(a) — who opened it.
  describe "the opener" do
    it "records the person who asked" do
      opener = create(:user, account: account)

      opened = described_class.new(account: account).open!(component, trigger: "operator", opened_by: opener)

      expect(opened[:investigation].opened_by_user_id).to eq(opener.id)
    end

    it "records nobody through the class-level door the emitter uses" do
      expect(described_class.open!(component, trigger: "down")[:investigation].opened_by_user_id).to be_nil
    end

    # A principal that is not a person must not become the "human" the
    # security gate reads as consent.
    it "records nobody for a principal that is not a User" do
      agent = create(:ai_agent, account: account)

      opened = described_class.new(account: account).open!(component, trigger: "operator", opened_by: agent)

      expect(opened[:investigation].opened_by_user_id).to be_nil
    end
  end

  describe "the ranking record" do
    it "is not counted as an evidence class" do
      evidence = { "conditions" => [ { "type" => "Up", "status" => false } ],
                   "ranking" => { "state" => "failed" } }

      expect(described_class.evidence_classes(evidence)).to include("conditions")
      expect(described_class.evidence_classes(evidence)).not_to include("ranking")
    end

    it "puts a terminal record's message into the conclusion" do
      automatic = described_class.new(account: account).open!(component, trigger: "down")[:investigation]
      automatic.update_columns(evidence: automatic.evidence.merge(
        "ranking" => { "retryable" => false,
                       "message" => "Ranking was not run because automatic spend needs an agent-scoped grant." }
      ))

      expect(described_class.new(account: account).conclude!(automatic).conclusion).to include("agent-scoped grant")
    end

    it "says nothing about ranking when an agent's ranking was used — the other arm" do
      opened = described_class.new(account: account).open!(component, trigger: "operator")[:investigation]

      concluded = described_class.new(account: account)
                                 .conclude!(opened, ranked: [ { cause: "disk full", score: 1.0,
                                                                evidence_classes: [ "conditions" ] } ])

      expect(concluded.conclusion).not_to include("Ranking")
    end
  end

  describe "#conclude!" do
    let(:investigation) { service.open!(component, trigger: "operator")[:investigation] }

    it "scores hypotheses with the confidence rule rather than accepting a number" do
      concluded = service.conclude!(investigation, ranked: [
        { cause: "upstream node lost", score: 6.0, evidence_classes: %w[conditions status_events],
          confidence: 0.99 },
        { cause: "credential expired", score: 4.0, evidence_classes: %w[conditions] }
      ])

      top = concluded.top_hypothesis
      expect(top["cause"]).to eq("upstream node lost")
      # NOT the 0.99 the ranker asserted.
      expect(top["confidence"]).to eq(0.45)
      expect(top["confidence_state"]).to eq(Platform::Investigation::Confidence::MEASURED)
      expect(concluded).to be_concluded
      expect(concluded.completed_at).to be_present
    end

    it "derives candidates itself when no ranking is supplied" do
      concluded = service.conclude!(investigation)

      expect(concluded.top_hypothesis["cause"]).to include("ConnectionError")
    end

    # `nil` is "nobody looked"; `[]` is "somebody looked and found nothing".
    # Collapsing them would let core overrule the only thing that actually read
    # the evidence, and would make an agent's empty answer look identical to no
    # agent having run.
    it "respects an EMPTY ranking rather than deriving over the top of it" do
      concluded = service.conclude!(investigation, ranked: [])

      expect(concluded.hypotheses).to eq([])
      expect(concluded).to be_concluded
    end

    it "still derives when the ranking is nil — the other arm" do
      expect(service.conclude!(investigation, ranked: nil).hypotheses).not_to be_empty
    end

    it "reports not_measured, never a number, when there is nothing to go on" do
      investigation.update!(evidence: {})

      concluded = service.conclude!(investigation)

      expect(concluded.hypotheses).to eq([])
      expect(concluded.conclusion).to include("No candidate cause")
    end

    it "does not re-conclude an investigation that already concluded" do
      service.conclude!(investigation, conclusion: "first")

      expect(service.conclude!(investigation, conclusion: "second").conclusion).to eq("first")
    end

    it "records a learning through the existing extractor seam" do
      expect_any_instance_of(Ai::Learning::CompoundLearningService).to receive(:store_learning).once

      service.conclude!(investigation)
    end

    it "offers a routed lane when the top hypothesis names an action category" do
      expect(Platform::RemediationRouter).to receive(:route)
        .with(instance_of(Platform::ComponentStatus), signal_kind: "instance.silent")

      service.conclude!(investigation, ranked: [
        { cause: "node silent", score: 1.0, evidence_classes: %w[conditions],
          recommended_action_category: "instance.silent" }
      ])
    end

    it "offers nothing when it names none" do
      expect(Platform::RemediationRouter).not_to receive(:route)

      service.conclude!(investigation, ranked: [ { cause: "unclear", score: 1.0, evidence_classes: %w[conditions] } ])
    end
  end

  describe "#owner_agent_slug_for" do
    it "defaults to the Infrastructure Generalist when the contributor names none" do
      expect(service.owner_agent_slug_for("docker_host"))
        .to eq(described_class::DEFAULT_OWNER_AGENT_SLUG)
    end

    it "uses the contributor's own slug when it declares one" do
      contributor = Class.new(Platform::Status::Contributor) do
        def kind = "owned_kind"
        def owner_agent_slug = "storage-manager"
      end.new
      Platform::Status::Registry.register("owned_kind", contributor)

      expect(service.owner_agent_slug_for("owned_kind")).to eq("storage-manager")
    ensure
      Platform::Status::Registry.unregister("owned_kind")
    end
  end
end
