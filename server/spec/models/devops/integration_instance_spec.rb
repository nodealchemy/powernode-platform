# frozen_string_literal: true

require "rails_helper"

RSpec.describe Devops::IntegrationInstance, type: :model do
  describe "#record_execution!" do
    let(:instance) { create(:devops_integration_instance) } # counters at 0, avg 0

    context "on the very first execution" do
      # Regression: the running-average divided by `execution_count` (still 0 on
      # the first call, since the +1 lives only in the unsaved updates hash),
      # producing an infinite value that overflowed the decimal(10,2) column
      # (PG::NumericValueOutOfRange). It must divide by execution_count + 1.
      it "does not overflow and records the duration as the average" do
        expect do
          instance.record_execution!(success: true, duration_ms: 100)
        end.not_to raise_error

        instance.reload
        expect(instance.execution_count).to eq(1)
        expect(instance.success_count).to eq(1)
        expect(instance.average_duration_ms.to_f).to eq(100.0)
      end
    end

    context "across multiple executions" do
      it "maintains a correct running average" do
        instance.record_execution!(success: true, duration_ms: 100) # avg 100 over 1
        instance.record_execution!(success: true, duration_ms: 300) # (100*1 + 300) / 2 = 200

        instance.reload
        expect(instance.execution_count).to eq(2)
        expect(instance.average_duration_ms.to_f).to eq(200.0)
      end
    end

    context "on failure" do
      it "tracks failure counters and the last error without touching the average" do
        instance.record_execution!(success: false, duration_ms: nil, error: "boom")

        instance.reload
        expect(instance.execution_count).to eq(1)
        expect(instance.failure_count).to eq(1)
        expect(instance.consecutive_failures).to eq(1)
        expect(instance.last_error).to eq("boom")
      end
    end
  end

  # A8: the three health columns had exactly one writer (`#update_health!`) and
  # zero call sites. `#record_health_probe!` is that call site — it derives the
  # verdict from the probe outcome plus the failure streak and writes THROUGH
  # `#update_health!`, which stays the single writer of the columns.
  describe "#record_health_probe!" do
    let(:instance) { create(:devops_integration_instance, status: "active", health_status: nil, last_health_check_at: nil) }

    it "records a passing probe as healthy and clears the streak" do
      instance.update!(health_metrics: { described_class::PROBE_FAILURE_KEY => 2 }, last_error: "stale")

      expect(instance.record_health_probe!(success: true)).to be false

      instance.reload
      expect(instance.health_status).to eq("healthy")
      expect(instance.probe_failure_streak).to eq(0)
      expect(instance.last_error).to be_nil
      expect(instance.last_health_check_at).to be_present
      expect(instance.status).to eq("active")
    end

    it "records a failing probe below the threshold as degraded" do
      expect(instance.record_health_probe!(success: false, error: "refused")).to be false

      instance.reload
      expect(instance.health_status).to eq("degraded")
      expect(instance.probe_failure_streak).to eq(1)
      expect(instance.last_error).to eq("refused")
      expect(instance.status).to eq("active")
    end

    it "reaches unhealthy and pauses at the threshold" do
      threshold = described_class.health_failure_threshold
      paused = (1..threshold).map { instance.record_health_probe!(success: false, error: "refused") }

      expect(paused).to eq([ *Array.new(threshold - 1, false), true ])
      instance.reload
      expect(instance.health_status).to eq("unhealthy")
      expect(instance.status).to eq("paused")
    end

    it "merges probe metrics into health_metrics without dropping prior keys" do
      instance.update!(health_metrics: { "keep" => "me" })

      instance.record_health_probe!(success: true, metrics: { "response_time_ms" => 12 })

      expect(instance.reload.health_metrics).to include("keep" => "me", "response_time_ms" => 12)
    end

    # GUARD THE DECISION, not the mechanism. `#pause!` is a bare `update!`, so the
    # guard has to sit where the auto-pause is DECIDED, or a sweep would drag a
    # disabled integration back to `paused` and undo an operator's retirement.
    it "does not auto-pause an integration that is not active" do
      instance.update!(status: "disabled")

      described_class.health_failure_threshold.times do
        expect(instance.record_health_probe!(success: false, error: "refused")).to be false
      end

      expect(instance.reload.status).to eq("disabled")
    end
  end

  # Review F3. Before the review, probes and executions shared the
  # `consecutive_failures` COLUMN, and the coupling broke both directions: a
  # passing probe wiped an execution streak of 4 (delaying the `>= 5` auto-error
  # rung), and a failing probe inflated it (tripping that rung early). Both arms
  # of the separation are asserted here — neither counter moves the other.
  describe "the probe streak and the execution streak are separate" do
    let(:instance) { create(:devops_integration_instance, status: "active") }

    it "does not touch consecutive_failures when a probe fails or succeeds" do
      instance.update!(consecutive_failures: 4)

      expect { instance.record_health_probe!(success: false, error: "refused") }
        .not_to change { instance.reload.consecutive_failures }
      expect { instance.record_health_probe!(success: true) }
        .not_to change { instance.reload.consecutive_failures }

      expect(instance.consecutive_failures).to eq(4)
    end

    it "does not touch the probe streak when an execution fails or succeeds" do
      instance.record_health_probe!(success: false, error: "refused")
      expect(instance.reload.probe_failure_streak).to eq(1)

      expect { instance.record_execution!(success: false, error: "boom") }
        .not_to change { instance.reload.probe_failure_streak }
      expect { instance.record_execution!(success: true) }
        .not_to change { instance.reload.probe_failure_streak }

      expect(instance.probe_failure_streak).to eq(1)
    end
  end

  describe ".health_failure_threshold" do
    it "falls back to the built-in default when no SiteSetting row exists" do
      expect(described_class.health_failure_threshold)
        .to eq(described_class::DEFAULT_HEALTH_FAILURE_THRESHOLD)
    end

    it "reads the SiteSetting when one is present" do
      SiteSetting.set(described_class::HEALTH_FAILURE_THRESHOLD_SETTING, 7, setting_type: "integer")

      expect(described_class.health_failure_threshold).to eq(7)
    end

    it "ignores a non-positive setting rather than pausing on every probe" do
      SiteSetting.set(described_class::HEALTH_FAILURE_THRESHOLD_SETTING, 0, setting_type: "integer")

      expect(described_class.health_failure_threshold)
        .to eq(described_class::DEFAULT_HEALTH_FAILURE_THRESHOLD)
    end
  end

  # IMP-01a04d08-ea13: IntegrationCredential used `has_many :instances,
  # dependent: :nullify`, so destroying a credential by any path other than
  # RegistryService#delete_credential's in-use guard left an instance with no
  # credential. Its template still required one, so every later update! failed
  # validation. That included pausing it: the operator could not pause a broken
  # instance, which stayed active. The credential now refuses that destroy
  # (restrict_with_error). An instance already orphaned (legacy data) can be
  # paused or disabled, since it cannot run in either state. Activating it still
  # requires the credential.
  describe "the credential requirement and resting statuses (IMP-01a04d08-ea13)" do
    let(:account)    { create(:account) }
    let(:template)   { create(:devops_integration_template, credential_requirements: { "type" => "api_key" }) }
    let(:credential) { create(:devops_integration_credential, account: account) }
    let(:instance) do
      create(:devops_integration_instance, account: account, template: template, credential: credential, status: "active")
    end

    def orphaned
      instance.update_column(:integration_credential_id, nil)
      instance.reload
    end

    it "lets an operator pause an instance whose required credential is gone" do
      row = orphaned

      expect(row.update(status: "paused")).to be(true), row.errors.full_messages.inspect
      expect(row.reload.status).to eq("paused")
    end

    it "lets it be disabled as well" do
      row = orphaned

      expect(row.update(status: "disabled")).to be(true), row.errors.full_messages.inspect
    end

    it "still refuses to activate it without the credential" do
      row = orphaned
      row.update!(status: "paused")

      expect(row.update(status: "active")).to be(false)
      expect(row.errors[:credential]).to include("is required for this integration type")
      expect(row.reload.status).to eq("paused")
    end
  end

  # IMP-01a08da1: the credential check ran on EVERY save. An active instance
  # whose credential stopped satisfying its template (the template was
  # tightened, or the credential went away) therefore failed validation on the
  # health probe's own write. #record_health_probe! raised, health stayed as it
  # was, the probe streak never climbed, and the threshold never auto-paused
  # the instance. The check now runs only on the saves it judges: creating the
  # row, or changing its status, credential or template.
  describe "the credential check runs only on the saves it judges (IMP-01a08da1)" do
    let(:account)    { create(:account) }
    let(:template)   { create(:devops_integration_template, credential_requirements: { "type" => "api_key" }) }
    let(:credential) { create(:devops_integration_credential, account: account) }
    let(:instance) do
      create(:devops_integration_instance, account: account, template: template, credential: credential, status: "active")
    end

    # Valid when activated, then the template demands a credential type this
    # one is not. update_column skips validation, as a template edit made
    # through its own model would for the instance.
    def broken
      instance
      template.update_column(:credential_requirements, { "type" => "oauth2" })
      instance.reload
    end

    it "records a telemetry-only update_health! on a broken instance" do
      row = broken

      expect { row.update_health!("degraded", "probe" => "timeout") }.not_to raise_error
      expect(row.reload.health_status).to eq("degraded")
      expect(row.health_metrics["probe"]).to eq("timeout")
    end

    it "records each failed probe, climbs the streak, and auto-pauses at the threshold" do
      row = broken
      threshold = described_class.health_failure_threshold

      (threshold - 1).times do |i|
        expect(row.record_health_probe!(success: false, error: "401")).to be(false)
        expect(row.reload.probe_failure_streak).to eq(i + 1)
        expect(row.health_status).to eq("degraded")
        expect(row.status).to eq("active")
      end

      expect(row.record_health_probe!(success: false, error: "401")).to be(true)
      row.reload
      expect(row.status).to eq("paused")
      expect(row.health_status).to eq("unhealthy")
      expect(row.probe_failure_streak).to eq(threshold)
      expect(row.last_error).to eq("401")
    end

    it "records a passing probe on a broken instance as healthy" do
      row = broken
      row.update_column(:health_status, "degraded")

      expect(row.record_health_probe!(success: true)).to be(false)
      expect(row.reload.health_status).to eq("healthy")
    end

    it "still refuses to reactivate a broken instance" do
      row = broken
      row.pause!

      expect(row.update(status: "active")).to be(false)
      expect(row.errors[:credential]).to include("must be of type oauth2")
      expect(row.reload.status).to eq("paused")
    end

    it "still refuses to swap a broken instance onto another wrong-type credential" do
      row = broken
      other = create(:devops_integration_credential, account: account)

      expect(row.update(integration_credential_id: other.id)).to be(false)
      expect(row.errors[:credential]).to include("must be of type oauth2")
      expect(row.reload.integration_credential_id).to eq(credential.id)
    end

    it "still refuses to move a valid instance onto a template its credential does not satisfy" do
      stricter = create(:devops_integration_template, credential_requirements: { "type" => "oauth2" })

      expect(instance.update(integration_template_id: stricter.id)).to be(false)
      expect(instance.errors[:credential]).to include("must be of type oauth2")
      expect(instance.reload.integration_template_id).to eq(template.id)
    end

    it "still refuses to create an instance without the credential its template requires" do
      row = build(:devops_integration_instance, account: account, template: template, status: "pending")

      expect(row.save).to be(false)
      expect(row.errors[:credential]).to include("is required for this integration type")
    end

    it "keeps every other validation on a telemetry save" do
      expect { instance.update_health!("bogus") }.to raise_error(ActiveRecord::RecordInvalid, /Health status/)
      expect(instance.reload.health_status).to eq("healthy")
    end
  end
end
