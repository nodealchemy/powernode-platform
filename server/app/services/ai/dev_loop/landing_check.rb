# frozen_string_literal: true

require "timeout"

module Ai
  module DevLoop
    # IMP-6d060f65ccae — did the commit a dev-improve task reports as its result
    # actually LAND? dev_complete_task used to store `commit_sha` verbatim, so a
    # PASSED task could name a commit that existed only in the executor's
    # worktree; that is how commits ended up stranded behind a green ledger.
    #
    # Three verdicts, kept apart because they call for different handling:
    #   true          the FULL 40-hex sha is on record as landed — a dev_merge.succeeded
    #                 audit row for one of THIS loop's repositories names it (as the merged
    #                 sha for the merged repository, or the pointer-bump commit for the
    #                 parent), or the loop's repository proves it reachable from develop;
    #   false         the git host ANSWERED and the sha is not reachable (or it is not a
    #                 sha at all): it is not on develop;
    #   "unverified"  the check could not run — no repository resolves for the loop, the
    #                 host is unreachable or timed out, or the sha is abbreviated. Nothing is
    #                 known, so the caller must NOT treat it as evidence of stranding.
    # nil means there was nothing to check (no commit_sha).
    #
    # Prefix matching is deliberately absent: an abbreviated sha is ambiguous across
    # repositories and could name someone else's commit.
    #
    # Scope: this proves the reported commit is on develop, not that it is THIS task's
    # commit — an executor could report any landed sha. Tying the sha to the task (its key
    # in the commit or merge row) is a follow-up.
    #
    # Never raises and never refuses.
    class LandingCheck
      TARGET_BRANCH = "develop"
      PAGE_SIZE = 50
      MAX_PAGES = 10
      # Wall-clock ceiling for the whole host walk. dev_complete_task runs this inline, and a
      # client that times out first would leave a completion committed but unreported.
      HOST_DEADLINE = 10
      FULL_SHA = /\A\h{40}\z/
      HEX = /\A\h+\z/

      UNVERIFIED = "unverified"

      Result = Struct.new(:landed, :via, :warning, keyword_init: true)

      def self.call(account:, loop_record:, commit_sha:)
        new(account: account, loop_record: loop_record, commit_sha: commit_sha).call
      end

      def initialize(account:, loop_record:, commit_sha:)
        @account = account
        @loop_record = loop_record
        @sha = commit_sha.to_s.strip.downcase
      end

      def call
        if @sha.empty?
          return Result.new(landed: nil, via: "no_commit_sha",
                            warning: "no commit_sha was reported, so the landing of this pass could not be checked")
        end
        unless @sha.match?(HEX)
          return Result.new(landed: false, via: "invalid_sha",
                            warning: "commit_sha #{@sha[0, 60].inspect} is not a git sha, so it cannot have landed")
        end
        unless @sha.match?(FULL_SHA)
          return unverified("invalid_sha", "commit_sha is abbreviated; report the full 40-character sha so its landing can be checked")
        end

        repositories = candidate_repositories
        return unverified("no_repository", "no git repository in this account resolves for the loop, so the landing of #{@sha} could not be checked") if repositories.empty?
        return Result.new(landed: true, via: "dev_merge_audit") if merge_audited?(repositories)

        reachable_on_host(repositories.first)
      end

      private

      def unverified(via, warning)
        Result.new(landed: UNVERIFIED, via: via, warning: "#{warning} — recorded as unverified, not as unlanded")
      end

      # The audit row's `repository` is what the caller typed (id or full_name); the pointer bump
      # names its parent the same way. merged_sha belongs to the first, pointer_commit_sha to the second.
      def merge_audited?(repositories)
        names = repositories.flat_map { |r| [ r.id.to_s, r.full_name.to_s ] }.uniq
        rows = ::AuditLog.where(account_id: @account.id, action: "dev_merge.succeeded")
        rows.where("metadata->'outcome'->>'merged_sha' = :sha AND metadata->>'repository' IN (:names)", sha: @sha, names: names)
            .or(rows.where("metadata->'outcome'->>'pointer_commit_sha' = :sha AND metadata->'pointer_bump'->>'parent_repository' IN (:names)",
                           sha: @sha, names: names))
            .exists?
      end

      def reachable_on_host(repository)
        client = ::Devops::Git::ApiClient.for(repository.credential)
        found = ::Timeout.timeout(HOST_DEADLINE) { walk(client, repository) }
        return Result.new(landed: true, via: "git_host") if found

        Result.new(landed: false, via: "git_host",
                   warning: "commit #{@sha} is not reachable from #{TARGET_BRANCH} on #{repository.full_name} " \
                            "(first #{MAX_PAGES * PAGE_SIZE} commits checked) — it may exist only in a worktree; " \
                            "push it, or report the sha of the commit that landed")
      rescue ::Timeout::Error
        unverified("host_timeout", "the git host did not answer within #{HOST_DEADLINE}s")
      rescue StandardError => e
        Rails.logger.warn("[LandingCheck] #{e.class}: #{e.message}")
        unverified("host_error", "the landing of commit #{@sha} could not be verified on the git host (#{e.class})")
      end

      def walk(client, repository)
        (1..MAX_PAGES).each do |page|
          commits = Array(client.list_commits(repository.owner, repository.name,
                                              sha: TARGET_BRANCH, page: page, per_page: PAGE_SIZE))
          return true if commits.any? { |c| names_sha?(c) }
          # An empty page is the end; a short page is not (the host may cap the page size below ours).
          break if commits.empty?
        end
        false
      end

      def names_sha?(commit)
        return false unless commit.respond_to?(:[])

        (commit["sha"] || commit[:sha] || commit["id"] || commit[:id]).to_s.downcase == @sha
      end

      # The loop's own repository, then its mission's. Both only when the repository AND its
      # credential belong to this account. A loop with no repository_url and no mission
      # repository (the dev-improve loop) yields none.
      def candidate_repositories
        scope = ::Devops::GitRepository.where(account_id: @account.id)
        found = []
        full_name = @loop_record.repository_full_name
        found << scope.find_by(full_name: full_name) if full_name.present?
        mission_repo = @loop_record.mission&.repository
        found << scope.find_by(id: mission_repo.id) if mission_repo
        found.compact.uniq.select { |r| r.credential && r.credential.account_id == @account.id }
      end
    end
  end
end
