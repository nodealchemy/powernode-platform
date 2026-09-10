# frozen_string_literal: true

require "rails_helper"

# Component status plane, increment A3 — the one-line registration seam and the
# end-to-end proof that a sweep over real seeded records produces a row of every
# core kind with a verdict derived from the source.
RSpec.describe Platform::Status::Contributors do
  let(:account) { create(:account) }
  let(:registry) { Platform::Status::Registry }

  # Every kind A3 owns (design §4.4, "Core registers:").
  let(:core_kinds) do
    %w[
      agent_circuit_breaker
      ai_provider
      docker_host
      integration_instance
      kubernetes_cluster
      provider_circuit_breaker
    ]
  end

  around do |example|
    saved = registry.contributors
    registry.reset!
    example.run
  ensure
    registry.reset!
    saved.each { |kind, contributor| registry.register(kind, contributor) }
  end

  describe ".register_all!" do
    it "registers exactly the six core kinds" do
      expect(described_class.register_all!).to eq(core_kinds)
      expect(registry.kinds.sort).to eq(core_kinds)
    end

    it "is idempotent — a second call replaces rather than duplicating" do
      described_class.register_all!
      first = registry.contributors

      described_class.register_all!
      second = registry.contributors

      expect(second.keys.sort).to eq(first.keys.sort)
      expect(second.size).to eq(core_kinds.size)
      # A fresh instance each time, so a reloaded class takes effect.
      expect(second["ai_provider"]).not_to equal(first["ai_provider"])
    end

    it "skips files in the directory that are not contributors" do
      # EnumConditions lives beside the contributors and defines no KIND.
      expect(described_class.contributor_classes).not_to include(described_class::EnumConditions)
      expect(described_class.contributor_classes.map { |k| k::KIND }.sort).to eq(core_kinds)
    end

    it "never registers a contributor that inherits its parent's KIND" do
      # The `false` on const_defined? is what stops a subclass silently
      # re-registering under its parent's key.
      subclass = Class.new(Platform::Status::Contributors::DockerHost)

      expect(subclass.const_defined?(:KIND, false)).to be(false)
      expect(subclass.const_defined?(:KIND)).to be(true)
    end
  end

  describe "the boot hook" do
    it "is wired from an initializer that runs on every reload" do
      initializer = Rails.root.join("config/initializers/platform_status_contributors.rb").read

      expect(initializer).to include("Rails.application.config.to_prepare")
      expect(initializer).to include("Platform::Status::Contributors.register_all!")
    end
  end

  describe "a sweep over real records" do
    let!(:healthy_provider) do
      create(:ai_provider, account: account, requires_auth: false, is_active: true).tap do |provider|
        provider.update_column(:metadata, { "health_metrics" => {
          "last_check_timestamp" => 1.minute.ago.iso8601, "last_check_success" => true
        } })
      end
    end
    let!(:unhealthy_provider) do
      # Requires auth, has no active credential — degraded from a real column.
      create(:ai_provider, account: account, requires_auth: true).tap do |provider|
        provider.update_column(:metadata, { "health_metrics" => {
          "last_check_timestamp" => 1.minute.ago.iso8601, "last_check_success" => true
        } })
      end
    end

    let!(:healthy_integration) do
      create(:devops_integration_instance, account: account, status: "active",
                                           health_status: "healthy", last_health_check_at: 1.minute.ago)
    end
    let!(:unhealthy_integration) do
      create(:devops_integration_instance, :errored, account: account,
                                                     last_health_check_at: 1.minute.ago)
    end

    let!(:healthy_host) { create(:devops_docker_host, :connected, account: account) }
    let!(:unhealthy_host) { create(:devops_docker_host, :error, account: account) }

    let!(:healthy_cluster) { create(:devops_kubernetes_cluster, :active, account: account) }
    let!(:unhealthy_cluster) { create(:devops_kubernetes_cluster, :degraded, account: account) }

    let(:agent) { create(:ai_agent, account: account) }
    let!(:healthy_breaker) do
      create(:ai_circuit_breaker, account: account, agent: agent, action_type: "execute_tool")
    end
    let!(:unhealthy_breaker) do
      create(:ai_circuit_breaker, :open, account: account, agent: agent, action_type: "spawn_task")
    end

    let(:breaker_provider_id) { SecureRandom.uuid }

    before do
      allow(::Ai::ProviderCircuitBreakerService).to receive(:all_provider_stats).and_return([
        { provider_id: breaker_provider_id, provider_name: "Shared Provider", service_name: "Shared Provider",
          resource_id: "provider:#{breaker_provider_id}", state: "open", failure_count: 5,
          success_count: 0, consecutive_failures: 5, consecutive_successes: 0,
          last_failure_time: 1.minute.ago, last_success_time: nil,
          state_changed_at: 1.minute.ago, next_retry_at: 1.minute.from_now,
          config: {}, can_attempt: false }
      ])
      described_class.register_all!
    end

    def rows_for(kind)
      Platform::ComponentStatus.where(component_kind: kind)
    end

    it "produces a row for every core kind" do
      Platform::Status::SweepService.run_once!(account)

      expect(Platform::ComponentStatus.distinct.pluck(:component_kind).sort).to eq(core_kinds)
    end

    it "derives a healthy and an unhealthy verdict per kind from the seeded records" do
      Platform::Status::SweepService.run_once!(account)

      verdicts = Platform::ComponentStatus.pluck(:component_kind, :component_ref, :verdict)
                                          .to_h { |kind, ref, verdict| [ [ kind, ref ], verdict ] }

      expect(verdicts[[ "ai_provider", healthy_provider.id ]]).to eq(Platform::ComponentStatus::OK)
      expect(verdicts[[ "ai_provider", unhealthy_provider.id ]]).to eq(Platform::ComponentStatus::DEGRADED)

      expect(verdicts[[ "integration_instance", healthy_integration.id ]]).to eq(Platform::ComponentStatus::OK)
      expect(verdicts[[ "integration_instance", unhealthy_integration.id ]]).to eq(Platform::ComponentStatus::DOWN)

      expect(verdicts[[ "docker_host", healthy_host.id ]]).to eq(Platform::ComponentStatus::OK)
      expect(verdicts[[ "docker_host", unhealthy_host.id ]]).to eq(Platform::ComponentStatus::DOWN)

      expect(verdicts[[ "kubernetes_cluster", healthy_cluster.id ]]).to eq(Platform::ComponentStatus::OK)
      expect(verdicts[[ "kubernetes_cluster", unhealthy_cluster.id ]]).to eq(Platform::ComponentStatus::DEGRADED)

      expect(verdicts[[ "agent_circuit_breaker", healthy_breaker.id ]]).to eq(Platform::ComponentStatus::OK)
      expect(verdicts[[ "agent_circuit_breaker", unhealthy_breaker.id ]]).to eq(Platform::ComponentStatus::DEGRADED)

      expect(verdicts[[ "provider_circuit_breaker", breaker_provider_id ]])
        .to eq(Platform::ComponentStatus::DEGRADED)
    end

    it "renders every row without knowing the kind — name, icon, label and links" do
      Platform::Status::SweepService.run_once!(account)

      Platform::ComponentStatus.find_each do |row|
        expect(row.display_name).to be_present, "#{row.component_kind} has no display name"
        expect(row.presentation["icon"]).to be_present, "#{row.component_kind} has no icon"
        expect(row.presentation["label"]).to be_present, "#{row.component_kind} has no label"
        expect(row.presentation["group_order"]).to be_a(Integer)
        expect(row.conditions).not_to be_empty, "#{row.component_kind} produced no conditions"
        expect(row.actions).to eq([]), "#{row.component_kind} declared a write action in A3"
      end
    end

    it "scopes account-scoped kinds to the swept account and leaves the shared kind null" do
      other = create(:account)
      create(:devops_docker_host, :connected, account: other)

      Platform::Status::SweepService.run_once!(account)

      expect(rows_for("docker_host").pluck(:account_id).uniq).to eq([ account.id ])
      expect(rows_for("provider_circuit_breaker").pluck(:account_id).uniq).to eq([ nil ])
    end

    it "reaps the row of a component whose record is gone" do
      Platform::Status::SweepService.run_once!(account)
      expect(rows_for("docker_host").where(component_ref: unhealthy_host.id)).to exist

      unhealthy_host.destroy!
      later = Time.current + (Platform::Status::SweepService.reap_after_seconds + 60).seconds
      Platform::Status::SweepService.run_once!(account, now: later)

      expect(rows_for("docker_host").where(component_ref: unhealthy_host.id)).not_to exist
      expect(rows_for("docker_host").where(component_ref: healthy_host.id)).to exist
    end
  end
end
