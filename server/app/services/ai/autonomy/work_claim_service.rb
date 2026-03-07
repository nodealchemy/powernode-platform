# frozen_string_literal: true

module Ai
  module Autonomy
    class WorkClaimService
      CLAIM_TTL = 1.hour
      CLAIM_PREFIX = "ai:work_claim:goal:"

      attr_reader :account

      def initialize(account:)
        @account = account
      end

      # Attempt to claim work on a goal atomically.
      # Uses Redis SETNX to prevent two agents from working on the same goal.
      #
      # @param goal_id [String] the goal to claim
      # @param agent_id [String] the claiming agent
      # @return [Boolean] true if claimed, false if already claimed
      def claim(goal_id:, agent_id:)
        key = claim_key(goal_id)
        result = redis.set(key, agent_id, nx: true, ex: CLAIM_TTL.to_i)
        result == true
      end

      # Release a claim on a goal.
      def release(goal_id:, agent_id:)
        key = claim_key(goal_id)
        current = redis.get(key)
        redis.del(key) if current == agent_id
      end

      # Extend the TTL of an existing claim.
      def extend_claim(goal_id:, agent_id:)
        key = claim_key(goal_id)
        current = redis.get(key)
        return false unless current == agent_id

        redis.expire(key, CLAIM_TTL.to_i)
        true
      end

      # Check who holds a claim on a goal.
      def claimed_by(goal_id:)
        redis.get(claim_key(goal_id))
      end

      # Check if a goal is claimed by any agent.
      def claimed?(goal_id:)
        redis.exists?(claim_key(goal_id))
      end

      private

      def claim_key(goal_id)
        "#{CLAIM_PREFIX}#{account.id}:#{goal_id}"
      end

      def redis
        @redis ||= Powernode::Redis.client
      end
    end
  end
end
