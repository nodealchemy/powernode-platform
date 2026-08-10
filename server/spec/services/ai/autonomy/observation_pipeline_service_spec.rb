# frozen_string_literal: true

require "rails_helper"

# Sensor::Base#build_observation returns nil when it finds a duplicate inside
# the 15-minute dedup window, and three of the ten sensors (goal_progress,
# governance, stigmergic_signal) end #collect without .compact, so they hand
# the pipeline an array containing nils.
#
# MEASURED, not assumed: Ai::AgentObservation.create!(nil) raises
# ActiveRecord::RecordInvalid — NOT ArgumentError — so the inner rescue does
# catch it and the remaining observations for that agent still persist. The
# originating finding claimed an ArgumentError escaping to the per-agent
# rescue and abandoning the rest; that is wrong, and the real cost is a wasted
# INSERT attempt plus a spurious "Failed to create observation" warning on
# every dedup hit. Because the dedup window equals the pipeline's cron period,
# that noise is routine, and it is indistinguishable in the log from a genuine
# validation failure — which is the part worth fixing.
RSpec.describe Ai::Autonomy::ObservationPipelineService do
  let(:account) { create(:account) }
  let(:agent)   { create(:ai_agent, account: account) }
  let(:service) { described_class.new(account: account, agent: agent) }

  # A sensor that returns exactly what a deduped real sensor returns: a nil
  # alongside a usable observation.
  let(:sensor_class) do
    valid = {
      account: account,
      agent: agent,
      sensor_type: "governance",
      observation_type: "opportunity",
      severity: "info",
      title: "a real observation"
    }
    Class.new do
      define_singleton_method(:name) { "SpecDedupingSensor" }
      define_method(:initialize) { |account:, agent:| }
      define_method(:collect) { [ nil, valid ] }
    end
  end

  before { allow(service).to receive(:resolve_sensors).and_return([ sensor_class ]) }

  it "never attempts to persist a nil observation" do
    # The collaborator assertion is the point: the outcome below passes either
    # way, because create!(nil) is rescued. What is actually wrong is that the
    # attempt happens at all.
    expect(Ai::AgentObservation).not_to receive(:create!).with(nil)

    service.run
  end

  it "still persists the real observations alongside a deduped nil" do
    created = service.run

    expect(created.size).to eq(1)
    expect(created.first.title).to eq("a real observation")
  end

  it "logs no failure warning when the only skipped entry was a dedup nil" do
    expect(Rails.logger).not_to receive(:warn).with(/Failed to create observation/)

    service.run
  end

  # A sensor whose every row fails validation is INDISTINGUISHABLE from a sensor
  # that legitimately had nothing to report: both contribute zero observations,
  # and the only trace is a per-row warning that reads exactly like a routine
  # dedup rejection. That is why CodeChangeSensor's enum mismatch survived from
  # the day it was written — it rejected 100% of its output for its whole life
  # and no signal anywhere said so; it was found by reading code.
  #
  # Observations are the O in the OODA path, so a silently dead sensor degrades
  # every downstream agent decision with no error to trace it to.
  describe "rejected-observation accounting" do
    def sensor_returning(rows)
      Class.new do
        define_singleton_method(:name) { "SpecDeadSensor" }
        define_method(:initialize) { |account:, agent:| }
        define_method(:collect) { rows }
      end
    end

    # Rows that cannot validate: sensor_type is outside SENSOR_TYPES, which is
    # exactly the CodeChangeSensor failure.
    def invalid_row
      { account: account, agent: agent, sensor_type: "not_a_real_sensor_type",
        observation_type: "opportunity", severity: "info", title: "doomed" }
    end

    it "reports how many observations each sensor had rejected" do
      allow(service).to receive(:resolve_sensors).and_return([ sensor_returning([ invalid_row, invalid_row ]) ])

      result = service.run

      expect(result.rejected_count).to eq(2)
      expect(result.rejected_by_sensor["SpecDeadSensor"]).to eq(2)
    end

    # THE load-bearing one: a fully-dead sensor must be distinguishable from a
    # quiet one. Both return zero observations, so only a distinct signal can
    # separate them — and separating them is the entire point of the task.
    it "emits a distinct signal for a sensor that produced nothing but rejections" do
      allow(service).to receive(:resolve_sensors).and_return([ sensor_returning([ invalid_row ]) ])

      expect(Rails.logger).to receive(:error).with(/SpecDeadSensor.*rejected/i)

      service.run
    end

    it "does NOT emit that signal for a sensor that simply had nothing to report" do
      allow(service).to receive(:resolve_sensors).and_return([ sensor_returning([]) ])

      expect(Rails.logger).not_to receive(:error)

      result = service.run
      expect(result.rejected_count).to eq(0)
    end

    # A sensor that mostly works but drops one row is a different condition from
    # a dead one, and must not be reported as dead.
    it "does not call a partially-rejecting sensor dead" do
      valid = { account: account, agent: agent, sensor_type: "governance",
                observation_type: "opportunity", severity: "info", title: "real" }
      allow(service).to receive(:resolve_sensors).and_return([ sensor_returning([ valid, invalid_row ]) ])

      expect(Rails.logger).not_to receive(:error)

      result = service.run
      expect(result.size).to eq(1)
      expect(result.rejected_count).to eq(1)
    end

    # run_for_account is what the cron calls; the count has to survive that hop
    # or nothing an operator reads will ever show it.
    it "surfaces rejections in the run_for_account summary" do
      allow_any_instance_of(described_class).to receive(:resolve_sensors)
        .and_return([ sensor_returning([ invalid_row ]) ])
      create(:ai_ralph_loop, account: account, default_agent: agent,
                             scheduling_mode: "autonomous", schedule_paused: false, status: "running")

      summary = described_class.run_for_account(account)

      expect(summary[:observations_rejected]).to eq(1)
    end
  end
end
