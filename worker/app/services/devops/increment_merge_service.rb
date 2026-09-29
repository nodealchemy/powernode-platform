# frozen_string_literal: true

require "tmpdir"
require "fileutils"
require_relative "git_cli"
require_relative "commit_message_hygiene"

module Devops
  # The worker half of dev_merge_increment (the server half is
  # Ai::Tools::DevMergeTool, which dispatches only an APPROVED merge).
  #
  #   1. verify_source   source_ref still resolves to expected_source_sha,
  #                      asked of the provider API (Devops::GitOperationsService)
  #                      and again of the fetched ref. Refused if it moved.
  #   2. fast_forward    every configured remote's target_branch must be the
  #                      expected SHA or an ancestor of it. Checked on EVERY
  #                      remote before pushing to ANY, so a non-fast-forward on
  #                      a mirror refuses the whole merge. Never forced.
  #   3. push            <sha>:refs/heads/<target> to each remote, no force.
  #                      A remote that did not take it makes the merge FAILED.
  #   4. pointer_bump    optional: in the parent repository, move ONE gitlink
  #                      (submodule_path) to the merged SHA through plumbing
  #                      (read-tree / update-index --cacheinfo / write-tree /
  #                      commit-tree), verify that path is the only change,
  #                      then fast-forward and push it to every parent remote
  #                      the same way. `git submodule` is never run.
  #
  # Returns the report the job posts to the server; never raises for a
  # refusal. `remote_resolver.call(repository_id)` answers
  # { url:, auth_header:, secrets:, api_config:, full_name: }, and
  # `git_ops_factory.call(api_config)` a Devops::GitOperationsService.
  class IncrementMergeService
    class Refusal < StandardError
      attr_reader :stage

      def initialize(stage, message)
        @stage = stage
        super(message)
      end
    end

    SHORT_SHA = 8

    def initialize(payload:, remote_resolver:, git_ops_factory:, workdir: nil, logger: nil, git_timeout: GitCli::DEFAULT_TIMEOUT)
      @payload = payload
      @remote_resolver = remote_resolver
      @git_ops_factory = git_ops_factory
      @workdir = workdir
      @logger = logger || Logger.new($stdout)
      @git_timeout = git_timeout
      @report = { "status" => "failed", "remotes" => [], "pointer_remotes" => [] }
    end

    def call
      with_workspace do |git|
        @git = git
        merge!
        bump_pointer! if @payload["pointer_bump"].is_a?(Hash)
      end
      @report.merge("status" => "succeeded", "stage" => nil).compact
    rescue Refusal => e
      @report.merge("status" => "failed", "stage" => e.stage, "error" => e.message).compact
    rescue GitCli::Refused, GitCli::Timeout => e
      @report.merge("status" => "failed", "stage" => @stage, "error" => e.message).compact
    end

    attr_reader :git

    private

    def expected
      @payload["expected_source_sha"].to_s.downcase
    end

    def target
      @payload["target_branch"].to_s
    end

    # ---- 1-3: the increment -------------------------------------------------

    def merge!
      remotes = @payload.fetch("remotes").map { |r| resolve(r) }
      raise Refusal.new("resolve", "no remotes were dispatched") if remotes.empty?

      @stage = "verify_source"
      verify_source!(remotes.first)

      @stage = "fast_forward"
      plans = fast_forward_plans(remotes, expected, ref_prefix: "merge")

      @stage = "push"
      @report["merged_sha"] = expected
      @report["remotes"] = push_all(plans, expected)
      failed = @report["remotes"].reject { |r| %w[pushed up_to_date].include?(r["status"]) }
      raise Refusal.new("push", "#{failed.size} of #{plans.size} remote(s) did not take the push") if failed.any?
    end

    def verify_source!(primary)
      source = @payload["source_ref"].to_s
      api_sha = @git_ops_factory.call(primary[:api_config])
                                .get_branch(repo: primary[:full_name], branch: source)
                                .dig(:commit, :sha).to_s.downcase
      unless api_sha == expected
        raise Refusal.new("verify_source",
                          "#{source} resolves to #{api_sha.empty? ? 'nothing' : api_sha[0, 12]}, not the reviewed " \
                          "#{expected[0, 12]}; refusing a source that moved")
      end

      fetch!(primary, "refs/heads/#{source}", "refs/dev-merge/source")
      fetched = rev_parse("refs/dev-merge/source")
      return if fetched == expected

      raise Refusal.new("verify_source", "#{source} moved to #{fetched[0, 12]} while it was being fetched; refusing")
    end

    # For each remote: :up_to_date when its target already IS `sha`, :push
    # when its target is an ancestor of `sha`. Anything else refuses the whole
    # operation before a single push.
    def fast_forward_plans(remotes, sha, ref_prefix:)
      remotes.each_with_index.map do |remote, i|
        local = "refs/dev-merge/#{ref_prefix}-#{i}"
        fetch!(remote, "refs/heads/#{target}", local)
        tip = rev_parse(local)
        if tip == sha
          [ remote, :up_to_date ]
        elsif ancestor?(tip, sha)
          [ remote, :push ]
        else
          raise Refusal.new("fast_forward",
                            "#{target} on #{remote[:full_name]} (#{tip[0, 12]}) is not an ancestor of " \
                            "#{sha[0, 12]}; refusing a non-fast-forward")
        end
      end
    end

    # Per remote, never short-circuited: the report must say what EVERY
    # remote did, because a partial push is the failure this reports.
    def push_all(plans, sha)
      plans.map do |remote, plan|
        entry = { "repository_id" => remote[:repository_id], "full_name" => remote[:full_name] }
        next entry.merge("status" => "up_to_date") if plan == :up_to_date

        result = git.run("push", "--porcelain", remote[:url], "#{sha}:refs/heads/#{target}",
                         auth_header: remote[:auth_header], secrets: remote[:secrets])
        if result.success?
          entry.merge("status" => "pushed")
        else
          entry.merge("status" => "failed", "error" => result.stderr.strip[0, 500])
        end
      end
    end

    # ---- 4: the parent's gitlink --------------------------------------------

    def bump_pointer!
      bump = @payload["pointer_bump"]
      @stage = "pointer_bump"
      path = bump["submodule_path"].to_s
      parents = Array(bump["remotes"]).map { |r| resolve(r) }
      raise Refusal.new("pointer_bump", "no parent remotes were dispatched") if parents.empty?

      fetch!(parents.first, "refs/heads/#{target}", "refs/dev-merge/parent")
      parent_tip = rev_parse("refs/dev-merge/parent")
      current = gitlink_at(parent_tip, path)

      commit = current == expected ? parent_tip : pointer_commit(parent_tip, path, bump["summary"])
      @report["pointer_commit_sha"] = commit

      @stage = "pointer_fast_forward"
      plans = fast_forward_plans(parents, commit, ref_prefix: "parent")

      @stage = "pointer_push"
      @report["pointer_remotes"] = push_all(plans, commit)
      failed = @report["pointer_remotes"].reject { |r| %w[pushed up_to_date].include?(r["status"]) }
      return if failed.empty?

      raise Refusal.new("pointer_push", "#{failed.size} of #{plans.size} parent remote(s) did not take the pointer bump")
    end

    # The SHA the gitlink at `path` records, refusing when `path` is not a
    # gitlink at all — this job moves an existing submodule pointer, it never
    # creates one or overwrites a file.
    def gitlink_at(tree_ish, path)
      entry = git!("ls-tree", tree_ish, "--", path).stdout.strip
      mode, type, sha = entry.split(/\s+/, 4)
      return sha.to_s.downcase if mode == "160000" && type == "commit"

      raise Refusal.new("pointer_bump", "#{path} is not a submodule gitlink on #{target}")
    end

    def pointer_commit(parent_tip, path, summary)
      message = CommitMessageHygiene.pointer_bump_message(
        scope: File.basename(path), short_sha: expected[0, SHORT_SHA],
        summary: summary.to_s.strip.empty? ? subject_of(expected) : summary,
        forbidden_names: @payload["forbidden_names"]
      )

      index = File.join(@workspace, "pointer.index")
      index_env = { "GIT_INDEX_FILE" => index }
      git!("read-tree", parent_tip, env: index_env)
      git!("update-index", "--cacheinfo", "160000,#{expected},#{path}", env: index_env)
      tree = git!("write-tree", env: index_env).stdout.strip
      commit = git!("commit-tree", tree, "-p", parent_tip, "-F", "-", env: identity_env, stdin: message).stdout.strip

      changed = git!("diff-tree", "-r", "--no-commit-id", "--name-only", parent_tip, commit).stdout.split("\n")
      unless changed == [ path ]
        raise Refusal.new("pointer_bump", "the pointer commit changed #{changed.size} path(s), not only #{path}")
      end

      commit
    rescue CommitMessageHygiene::Refused => e
      raise Refusal.new("pointer_bump", e.message)
    end

    def subject_of(sha)
      git!("log", "-1", "--format=%s", sha).stdout.strip
    end

    def identity_env
      committer = @payload["committer"].is_a?(Hash) ? @payload["committer"] : {}
      name = committer["name"].to_s
      email = committer["email"].to_s
      raise Refusal.new("pointer_bump", "no committer identity was dispatched") if name.empty? || email.empty?

      { "GIT_AUTHOR_NAME" => name, "GIT_AUTHOR_EMAIL" => email,
        "GIT_COMMITTER_NAME" => name, "GIT_COMMITTER_EMAIL" => email }
    end

    # ---- plumbing -------------------------------------------------------------

    def resolve(descriptor)
      remote = @remote_resolver.call(descriptor["repository_id"])
      remote.merge(repository_id: descriptor["repository_id"],
                   full_name: remote[:full_name] || descriptor["full_name"])
    rescue Refusal
      raise
    rescue StandardError => e
      raise Refusal.new("resolve", "could not resolve remote #{descriptor['full_name']}: #{e.class}")
    end

    def fetch!(remote, ref, local)
      result = git.run("fetch", "--no-tags", "--quiet", remote[:url], "#{ref}:#{local}",
                       auth_header: remote[:auth_header], secrets: remote[:secrets])
      return if result.success?

      raise Refusal.new(@stage, "could not fetch #{ref} from #{remote[:full_name]}: #{result.stderr.strip[0, 300]}")
    end

    def rev_parse(ref)
      git!("rev-parse", "--verify", "#{ref}^{commit}").stdout.strip.downcase
    end

    def ancestor?(ancestor, descendant)
      git.run("merge-base", "--is-ancestor", ancestor, descendant).success?
    end

    def git!(*args, env: {}, stdin: nil)
      result = git.run(*args, env: env, stdin: stdin)
      return result if result.success?

      raise Refusal.new(@stage, "git #{args.first} failed: #{result.stderr.strip[0, 300]}")
    end

    def with_workspace
      base = @workdir || Dir.mktmpdir("dev-merge")
      @workspace = base
      repo = File.join(base, "repo.git")
      cli = GitCli.new(git_dir: repo, timeout: @git_timeout)
      init = Open3.capture3(GitCli::BASE_ENV, "git", "init", "--bare", "--quiet", repo)
      raise Refusal.new("workspace", "could not create a workspace") unless init.last.success?

      yield cli
    ensure
      FileUtils.remove_entry(base) if base && @workdir.nil? && File.exist?(base)
    end
  end
end
