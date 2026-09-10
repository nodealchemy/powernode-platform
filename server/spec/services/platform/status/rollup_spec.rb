# frozen_string_literal: true

require "rails_helper"

# Component status plane, increment A1 — rollup, impact and root cause.
RSpec.describe Platform::Status::Rollup do
  let(:account) { create(:account) }

  def component(ref, verdict: "ok", kind: "fake_kind", depends_on: [], transitioned_at: nil)
    create(:platform_component_status,
           account: account,
           component_kind: kind,
           component_ref: ref,
           verdict: verdict,
           dependencies: depends_on.map { |k, r| { "kind" => k, "ref" => r, "relation" => "requires" } },
           conditions: transitioned_at ? [ { "type" => "Reachable", "status" => false, "reason" => "Down",
                                             "last_transition_at" => transitioned_at } ] : [])
  end

  describe ".rollup" do
    it "carries the held count BESIDE the operational verdict — a drain never turns the header amber" do
      component("a")
      component("b", verdict: "held")
      component("c", verdict: "held")

      result = described_class.rollup(Platform::ComponentStatus.for_account(account))

      expect(result[:verdict]).to eq("ok")
      expect(result[:held_count]).to eq(2)
      expect(result[:total]).to eq(3)
    end

    it "does let a real failure raise it, with the held count still carried" do
      component("a", verdict: "held")
      component("b", verdict: "down")

      result = described_class.rollup(Platform::ComponentStatus.for_account(account))

      expect(result[:verdict]).to eq("down")
      expect(result[:held_count]).to eq(1)
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

    it "ranks by the earliest transition when the out-degrees tie" do
      component("first", verdict: "down", transitioned_at: 4.hours.ago)
      component("second", verdict: "down", transitioned_at: 10.minutes.ago)
      web = component("web", verdict: "degraded",
                             depends_on: [ %w[fake_kind second], %w[fake_kind first] ])

      expect(described_class.root_cause_candidates(web).map(&:component_ref)).to eq(%w[first second])
    end
  end
end
