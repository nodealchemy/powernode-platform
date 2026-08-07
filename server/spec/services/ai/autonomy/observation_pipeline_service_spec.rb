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
end
