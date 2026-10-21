# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20261020140000_scrub_historical_execution_event_errors.rb")

# The boot-time migration must never lock or rewrite rows (IMP-dbabbea6f81c);
# the scrub is Ai::ExecutionEventErrorScrub, run by an operator task.
RSpec.describe ScrubHistoricalExecutionEventErrors do
  it "is a marker: it touches no rows and runs no DDL transaction lock" do
    expect(Ai::ExecutionEvent).not_to receive(:transaction)
    allow(subject).to receive(:say)

    expect { subject.up }.not_to raise_error
  end
end
