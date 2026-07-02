# frozen_string_literal: true

require "rails_helper"

RSpec.describe Devops::Repository do
  describe "#enqueue_sync" do
    it "dispatches the provider sync through the worker HTTP seam (the API server runs no Sidekiq)" do
      # Devops::Repository is an orphaned model (no backing table); allocate an
      # instance so we can exercise #enqueue_sync without touching the DB.
      repo = described_class.allocate
      allow(repo).to receive(:id).and_return("repo-abc")
      allow(WorkerJobService).to receive(:enqueue_devops_provider_sync)

      repo.enqueue_sync

      expect(WorkerJobService).to have_received(:enqueue_devops_provider_sync).with("repo-abc")
    end
  end
end
