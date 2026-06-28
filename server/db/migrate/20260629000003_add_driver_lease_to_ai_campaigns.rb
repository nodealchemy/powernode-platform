# frozen_string_literal: true

# Single-driver lease for Autonomous Improvement Campaigns: an advisory, expiring
# claim so exactly one driver — a Claude Code session OR the platform executor —
# works a campaign's branch + ledger at a time. Concurrent drivers on the same
# campaign/<id> branch race on git and the progress ledger; the lease lets a second
# driver detect the campaign is already being driven and back off. Advisory
# (cooperative): drivers check it before driving; it does not lock git itself.
class AddDriverLeaseToAiCampaigns < ActiveRecord::Migration[8.0]
  def change
    add_column :ai_campaigns, :driver_lease_holder, :string
    add_column :ai_campaigns, :driver_lease_expires_at, :datetime
  end
end
