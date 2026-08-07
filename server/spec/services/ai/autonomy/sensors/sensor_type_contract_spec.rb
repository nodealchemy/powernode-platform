# frozen_string_literal: true

require "rails_helper"

# CodeChangeSensor#sensor_type returned "code_changes" while
# Ai::AgentObservation::SENSOR_TYPES lists "code_change" singular, so the
# inclusion validation rejected every row that sensor produced.
# ObservationPipelineService rescues ActiveRecord::RecordInvalid and logs a
# warning, so the sensor failed SILENTLY — it has never persisted a single
# observation, and nothing anywhere said so.
#
# The one-character fix is not the deliverable. A sweep over every sensor is:
# the mismatch was invisible precisely because nothing asserted the contract
# between a sensor's declared type and the enum that gates persistence, so
# the next sensor added with a plural name would fail the same silent way.
RSpec.describe "sensor_type contract", type: :model do
  # Discovered from disk rather than a hardcoded list — a sensor added later
  # is covered automatically, which is the whole point of a sweep.
  def sensor_classes
    Dir[Rails.root.join("app/services/ai/autonomy/sensors/*.rb")]
      .map { |p| File.basename(p, ".rb") }
      .reject { |n| n == "base" }
      .map { |n| "Ai::Autonomy::Sensors::#{n.camelize}".safe_constantize }
      .compact
  end

  it "finds the sensors on disk (guards against the sweep silently covering nothing)" do
    expect(sensor_classes.size).to be >= 10
  end

  it "declares a sensor_type that Ai::AgentObservation will actually accept" do
    offenders = sensor_classes.filter_map do |klass|
      declared = klass.allocate.sensor_type
      next if Ai::AgentObservation::SENSOR_TYPES.include?(declared)

      "#{klass.name} declares #{declared.inspect}"
    end

    expect(offenders).to be_empty,
      "these sensors declare a sensor_type outside AgentObservation::SENSOR_TYPES, so every " \
      "observation they produce fails validation and is swallowed by the pipeline's rescue:\n" \
      "  #{offenders.join("\n  ")}\n" \
      "Valid types: #{Ai::AgentObservation::SENSOR_TYPES.join(', ')}"
  end

  # The behaviour the enum gates, asserted end to end rather than by string
  # comparison: a row carrying the sensor's declared type must persist.
  it "persists an observation carrying CodeChangeSensor's declared sensor_type" do
    account = create(:account)
    agent   = create(:ai_agent, account: account)

    observation = Ai::AgentObservation.new(
      account: account,
      agent: agent,
      sensor_type: Ai::Autonomy::Sensors::CodeChangeSensor.allocate.sensor_type,
      observation_type: "opportunity",
      severity: "info",
      title: "Git event: push on some/repo"
    )

    expect(observation).to be_valid, observation.errors.full_messages.join("; ")
    expect { observation.save! }.not_to raise_error
  end
end
