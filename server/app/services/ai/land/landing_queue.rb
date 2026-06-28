# frozen_string_literal: true

require "digest"

module Ai
  module Land
    # Serializes campaign landings per target branch. Multiple campaigns run
    # concurrently; only the land step is serialized so merges don't race each
    # other on the same branch. Under a per-target pg advisory xact lock, picks
    # the highest-priority/oldest queued land — but only when no land is already
    # active for that target. A parked land yields its slot to the next queued one.
    class LandingQueue
      # Max concurrently-active lands per target branch (the merge bottleneck).
      MAX_ACTIVE_PER_TARGET = 1

      # Returns the next land to drive (now transitioned to :staging), or nil if
      # the target is busy or the queue is empty. Acquires a per-target advisory
      # lock so concurrent pollers can't both pick.
      def self.next_for(target_branch:, account: nil)
        Ai::CampaignLand.transaction do
          ActiveRecord::Base.connection.execute(
            "SELECT pg_advisory_xact_lock(#{lock_key(target_branch)})"
          )

          active = Ai::CampaignLand.active_for(target_branch)
          active = active.where(account_id: account.id) if account
          return nil if active.count >= MAX_ACTIVE_PER_TARGET

          scope = Ai::CampaignLand.queued.where(target_branch: target_branch)
          scope = scope.where(account_id: account.id) if account
          land = scope.order(priority: :desc, queued_at: :asc).first
          return nil unless land

          land.begin_staging!
          land
        end
      end

      # Stable signed-64-bit key from the branch name for pg_advisory_xact_lock.
      def self.lock_key(target_branch)
        Digest::SHA256.hexdigest("ai_campaign_land:#{target_branch}").to_i(16) % (2**63)
      end
    end
  end
end
