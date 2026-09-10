# frozen_string_literal: true

require "rails_helper"

# Component status plane, increment A1 — rollup, impact and root cause.
RSpec.describe Platform::Status::Rollup do
  let(:account) { create(:account) }

  def component(ref, verdict: "ok", kind: "fake_kind", depends_on: [], transitioned_at: nil, held: false)
    conditions = []
    if transitioned_at
      conditions << { "type" => "Reachable", "status" => false, "reason" => "Down",
                      "last_transition_at" => transitioned_at }
    end
    conditions << { "type" => "Held", "status" => true, "reason" => "Cordoned" } if held

    create(:platform_component_status,
           account: account,
           component_kind: kind,
           component_ref: ref,
           verdict: verdict,
           dependencies: depends_on.map { |k, r| { "kind" => k, "ref" => r, "relation" => "requires" } },
           conditions: conditions)
  end

  describe ".rollup" do
    it "carries the held count BESIDE the operational verdict — a drain never turns the header amber" do
      component("a")
      component("b", verdict: "held", held: true)
      component("c", verdict: "held", held: true)

      result = described_class.rollup(Platform::ComponentStatus.for_account(account))

      expect(result[:verdict]).to eq("ok")
      expect(result[:held_count]).to eq(2)
      expect(result[:total]).to eq(3)
    end

    it "does let an UNHELD failure raise it, with the held count still carried" do
      component("a", verdict: "held", held: true)
      component("b", verdict: "down")

      result = described_class.rollup(Platform::ComponentStatus.for_account(account))

      expect(result[:verdict]).to eq("down")
      expect(result[:held_count]).to eq(1)
    end

    # A1 review L2 — the case the ruling exists for.
    it "keeps a held-AND-down component out of the headline and IN the held count" do
      component("drained", verdict: "down", held: true)
      component("healthy", verdict: "ok")

      result = described_class.rollup(Platform::ComponentStatus.for_account(account))

      # A planned drain of a node that is (correctly) down does not go red...
      expect(result[:verdict]).to eq("ok")
      # ...it is counted as held, so the caption explains the drain...
      expect(result[:held_count]).to eq(1)
      # ...and the per-verdict breakdown still tells the truth about it, which
      # is why held_count and counts_by_verdict deliberately disagree.
      expect(result[:counts_by_verdict]["down"]).to eq(1)
      expect(result[:counts_by_verdict]["held"]).to eq(0)
    end

    it "does NOT count a component whose verdict is held but which carries no Held condition" do
      component("ladder_only", verdict: "held")

      result = described_class.rollup(Platform::ComponentStatus.for_account(account))

      expect(result[:held_count]).to eq(0)
    end

    it "counts every rung of the ladder, including the ones at zero" do
      component("a", verdict: "degraded")

      counts = described_class.rollup(Platform::ComponentStatus.for_account(account))[:counts_by_verdict]

      expect(counts.keys).to eq(Platform::ComponentStatus::VERDICTS)
      expect(counts["degraded"]).to eq(1)
      expect(counts["ok"]).to eq(0)
    end

    it "calls an EMPTY scope not_measured rather than ok" do
      expect(described_class.rollup(Platform::ComponentStatus.for_account(account))[:verdict]).to eq("not_measured")
    end
  end

  describe ".impact" do
    it "reverse-walks dependents to depth 4 and stops there" do
      # e -> d -> c -> b -> a -> root  (each depends on the next)
      root = component("root", verdict: "down")
      component("a", depends_on: [ %w[fake_kind root] ])
      component("b", depends_on: [ %w[fake_kind a] ])
      component("c", depends_on: [ %w[fake_kind b] ], verdict: "degraded")
      component("d", depends_on: [ %w[fake_kind c] ])
      component("e", depends_on: [ %w[fake_kind d] ])

      result = described_class.impact(root)

      expect(result[:components].map(&:component_ref)).to contain_exactly("a", "b", "c", "d")
      expect(result[:count]).to eq(4)
      expect(result[:worst_verdict]).to eq("degraded")
    end

    it "terminates on a cycle instead of walking forever" do
      a = component("a", depends_on: [ %w[fake_kind b] ])
      component("b", depends_on: [ %w[fake_kind a] ])

      result = described_class.impact(a)

      expect(result[:components].map(&:component_ref)).to eq(%w[b])
    end

    it "reports nothing — and not_measured, not ok — for a component nobody depends on" do
      lonely = component("lonely", verdict: "down")

      result = described_class.impact(lonely)

      expect(result[:count]).to eq(0)
      expect(result[:worst_verdict]).to eq("not_measured")
    end
  end

  describe ".root_cause_candidates" do
    it "names the upstream-most unhealthy component in a two-node chain" do
      # web depends on db; both are unhealthy, so db is where it starts.
      component("db", verdict: "down", transitioned_at: 1.hour.ago)
      web = component("web", verdict: "degraded", depends_on: [ %w[fake_kind db] ], transitioned_at: 5.minutes.ago)

      candidates = described_class.root_cause_candidates(web)

      expect(candidates.map(&:component_ref)).to eq(%w[db])
    end

    it "stops at the last UNHEALTHY hop — a healthy upstream is not a cause" do
      component("disk", verdict: "ok")
      component("db", verdict: "down", depends_on: [ %w[fake_kind disk] ])
      web = component("web", verdict: "degraded", depends_on: [ %w[fake_kind db] ])

      expect(described_class.root_cause_candidates(web).map(&:component_ref)).to eq(%w[db])
    end

    it "falls back to the component itself when nothing upstream is broken" do
      component("db", verdict: "ok")
      web = component("web", verdict: "down", depends_on: [ %w[fake_kind db] ])

      expect(described_class.root_cause_candidates(web).map(&:component_ref)).to eq(%w[web])
    end

    it "returns nothing for a healthy component" do
      component("db", verdict: "ok")
      web = component("web", verdict: "ok", depends_on: [ %w[fake_kind db] ])

      expect(described_class.root_cause_candidates(web)).to be_empty
    end

    it "ranks a shared cause above a narrow one, then the earliest transition" do
      # Two independent upstream failures; `shared` explains two dependents,
      # `narrow` explains one, so it ranks first despite breaking later.
      component("shared", verdict: "down", transitioned_at: 5.minutes.ago)
      component("narrow", verdict: "down", transitioned_at: 3.hours.ago)
      component("sibling", verdict: "degraded", depends_on: [ %w[fake_kind shared] ])
      web = component("web", verdict: "degraded",
                             depends_on: [ %w[fake_kind shared], %w[fake_kind narrow] ])

      expect(described_class.root_cause_candidates(web).map(&:component_ref)).to eq(%w[shared narrow])
    end

    # A1 review L5.
    it "falls back to the whole unhealthy cycle when no member is upstream-most" do
      # a and b depend on each other and are both unhealthy, so neither is
      # "upstream-most". Returning nothing would be a worse answer than
      # returning the cycle.
      component("a", verdict: "down", depends_on: [ %w[fake_kind b] ], transitioned_at: 2.hours.ago)
      b = component("b", verdict: "down", depends_on: [ %w[fake_kind a] ], transitioned_at: 1.hour.ago)

      candidates = described_class.root_cause_candidates(b)

      expect(candidates.map(&:component_ref)).to contain_exactly("a", "b")
    end

    # A1 review L3.
    it "sorts a component with NO transition timestamp LAST, not as the oldest" do
      # "we have no idea when this broke" must not outrank "this demonstrably
      # broke four hours ago".
      component("timed", verdict: "down", transitioned_at: 4.hours.ago)
      component("untimed", verdict: "not_measured")
      web = component("web", verdict: "degraded",
                             depends_on: [ %w[fake_kind untimed], %w[fake_kind timed] ])

      expect(described_class.root_cause_candidates(web).map(&:component_ref)).to eq(%w[timed untimed])
    end

    it "ranks by the earliest transition when the out-degrees tie" do
      component("first", verdict: "down", transitioned_at: 4.hours.ago)
      component("second", verdict: "down", transitioned_at: 10.minutes.ago)
      web = component("web", verdict: "degraded",
                             depends_on: [ %w[fake_kind second], %w[fake_kind first] ])

      expect(described_class.root_cause_candidates(web).map(&:component_ref)).to eq(%w[first second])
    end
  end
end
