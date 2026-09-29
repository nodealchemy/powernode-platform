# frozen_string_literal: true

module Ai
  module DevLoop
    # IMP-6d060f65ccae — did the commit a dev-improve task reports as its result
    # actually LAND? dev_complete_task used to store `commit_sha` verbatim, so a
    # PASSED task could name a commit that existed only in the executor's
    # worktree; that is how commits ended up stranded behind a green ledger.
    #
    # A sha is landed when either
    #   * a dev_merge.succeeded audit row in this account names it (as the merged
    #     sha or as the pointer-bump commit) — the merge path's own record; or
    #   * it is reachable from the target branch on the loop's repository, read
    #     through the existing git-provider client (bounded pages; there is no
    #     compare-to-branch endpoint to lean on).
    #
    # Never raises and never refuses: the caller records the verdict and downgrades
    # evidence, it does not fail the completion. `landed` is nil only when there is
    # nothing to check (no commit_sha).
    class LandingCheck
      TARGET_BRANCH = "develop"
      PAGE_SIZE = 50
      MAX_PAGES = 10
      SHA_PATTERN = /\A\h{7,40}\z/

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
        unless @sha.match?(SHA_PATTERN)
          return Result.new(landed: false, via: "invalid_sha",
                            warning: "commit_sha #{@sha[0, 60].inspect} is not a git sha, so it cannot have landed")
        end
        return Result.new(landed: true, via: "dev_merge_audit") if merge_audited?

        reachable_on_host
      end

      private

      def merge_audited?
        pattern = "#{@sha}%"
        ::AuditLog.where(account_id: @account.id, action: "dev_merge.succeeded")
                  .where("metadata->'outcome'->>'merged_sha' LIKE :p OR metadata->'outcome'->>'pointer_commit_sha' LIKE :p",
                         p: pattern)
                  .exists?
      end

      def reachable_on_host
        repository = candidate_repository
        return unhosted("no git repository in this account matches the loop, so #{TARGET_BRANCH} could not be read") unless repository

        client = ::Devops::Git::ApiClient.for(repository.credential)
        (1..MAX_PAGES).each do |page|
          commits = Array(client.list_commits(repository.owner, repository.name,
                                              sha: TARGET_BRANCH, page: page, per_page: PAGE_SIZE))
          return Result.new(landed: true, via: "git_host") if commits.any? { |c| names_sha?(c) }
          break if commits.size < PAGE_SIZE
        end

        Result.new(landed: false, via: "git_host",
                   warning: "commit #{@sha} is not reachable from #{TARGET_BRANCH} on #{repository.full_name} " \
                            "(first #{MAX_PAGES * PAGE_SIZE} commits checked) — it may exist only in a worktree; " \
                            "push it, or report the sha of the commit that landed")
      rescue StandardError => e
        Rails.logger.warn("[LandingCheck] #{e.class}: #{e.message}")
        unhosted("the landing of commit #{@sha} could not be verified on the git host (#{e.class})")
      end

      def unhosted(reason)
        Result.new(landed: false, via: "unverified", warning: "#{reason} — recorded as not landed")
      end

      def names_sha?(commit)
        return false unless commit.respond_to?(:[])

        candidate = commit["sha"] || commit[:sha] || commit["id"] || commit[:id]
        candidate.to_s.downcase.start_with?(@sha)
      end

      # The loop's own repository, then its mission's. Both only when the
      # repository AND its credential belong to this account.
      def candidate_repository
        scope = ::Devops::GitRepository.where(account_id: @account.id)
        full_name = @loop_record.repository_full_name
        found = scope.find_by(full_name: full_name) if full_name.present?
        found ||= scope.find_by(id: @loop_record.mission&.repository&.id) if @loop_record.mission
        return nil unless found&.credential && found.credential.account_id == @account.id

        found
      end
    end
  end
end
