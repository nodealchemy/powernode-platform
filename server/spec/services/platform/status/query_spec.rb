# frozen_string_literal: true

require "rails_helper"

# Campaign 01a08c9b, increment A4 — the read side's one filter.
#
# The three-valued environment rule (design §4.6) is the whole reason this
# class exists, so every arm of it is asserted here rather than only through
# the REST door.
RSpec.describe Platform::Status::Query do
  let(:account) { create(:account) }
  let(:other_account) { create(:account) }
  let(:plane_a) { account.environments.find_by!(slug: "dev") }
  let(:plane_b) { account.environments.find_by!(slug: "prod") }

  def component(*traits, **attrs)
    create(:platform_component_status, *traits, **{ account: account }.merge(attrs))
  end

  def refs(query) = query.rows.map(&:component_ref)

  describe "base scope" do
    it "returns this account's rows and the shared ones, never another tenant's" do
      mine   = component(component_ref: "mine")
      shared = create(:platform_component_status, :shared, component_ref: "shared")
      create(:platform_component_status, account: other_account, component_ref: "theirs")

      expect(refs(described_class.new(account: account))).to contain_exactly(mine.component_ref, shared.component_ref)
    end
  end

  describe "the three-valued environment filter" do
    let!(:in_a)      { component(component_ref: "in-a", environment: plane_a) }
    let!(:in_b)      { component(component_ref: "in-b", environment: plane_b) }
    let!(:planeless) { component(component_ref: "planeless", environment: nil) }

    it "with no environment returns every row, on a plane or not" do
      expect(refs(described_class.new(account: account))).to contain_exactly("in-a", "in-b", "planeless")
    end

    it "with a plane returns that plane PLUS the plane-less rows, and never another plane's" do
      result = refs(described_class.new(account: account, environment: plane_a.slug))
      expect(result).to contain_exactly("in-a", "planeless")
      expect(result).not_to include("in-b")
    end

    it "with environment=none returns the plane-less rows ALONE" do
      expect(refs(described_class.new(account: account, environment: "none"))).to contain_exactly("planeless")
    end

    it "accepts an environment id as well as a slug" do
      expect(refs(described_class.new(account: account, environment: plane_b.id))).to contain_exactly("in-b", "planeless")
    end

    it "labels each row with the half it came from" do
      query = described_class.new(account: account, environment: plane_a.slug)
      labels = query.rows.to_h { |row| [ row.component_ref, described_class.plane_label(row) ] }
      expect(labels).to eq("in-a" => "in", "planeless" => "none")
    end

    it "refuses a plane this account does not have instead of falling back to the plane-less rows" do
      query = described_class.new(account: account, environment: "moon")
      expect(query.unknown_environment?).to be true
      expect(query.rows).to be_empty
    end

    it "does not resolve another account's plane" do
      foreign = other_account.environments.find_by!(slug: "dev")
      query = described_class.new(account: account, environment: foreign.id)
      expect(query.unknown_environment?).to be true
      expect(query.rows).to be_empty
    end
  end

  describe "kind and verdict filters" do
    let!(:provider) { component(component_kind: "ai_provider", component_ref: "openai", verdict: "down") }
    let!(:host)     { component(component_kind: "docker_host", component_ref: "host-1", verdict: "ok") }

    it "includes the matching kind and excludes the others" do
      result = refs(described_class.new(account: account, kind: "ai_provider"))
      expect(result).to include("openai")
      expect(result).not_to include("host-1")
    end

    it "includes the matching verdict and excludes the others" do
      result = refs(described_class.new(account: account, verdict: "down"))
      expect(result).to include("openai")
      expect(result).not_to include("host-1")
    end

    it "reports a verdict outside the ladder rather than answering as if unfiltered" do
      query = described_class.new(account: account, verdict: "on_fire")
      expect(query.known_verdict?).to be false
      expect(described_class.new(account: account, verdict: "down").known_verdict?).to be true
      expect(described_class.new(account: account).known_verdict?).to be true
    end
  end

  describe "ordering" do
    it "puts the worst verdict first and breaks ties deterministically" do
      component(component_kind: "b_kind", component_ref: "b1", verdict: "ok")
      component(component_kind: "a_kind", component_ref: "a1", verdict: "ok")
      component(component_kind: "z_kind", component_ref: "z1", verdict: "down")
      component(component_kind: "m_kind", component_ref: "m1", verdict: "degraded")
      component(:held, component_kind: "h_kind", component_ref: "h1")

      expect(refs(described_class.new(account: account))).to eq(%w[z1 m1 h1 a1 b1])
    end
  end

  describe "#applied_filters" do
    it "echoes what was asked, including the resolved plane id" do
      query = described_class.new(account: account, kind: "ai_provider", verdict: "ok", environment: plane_a.slug)
      expect(query.applied_filters).to eq(
        kind: "ai_provider", verdict: "ok", environment: plane_a.slug, environment_id: plane_a.id
      )
      expect(described_class.new(account: account).applied_filters).to eq({})
    end
  end
end
