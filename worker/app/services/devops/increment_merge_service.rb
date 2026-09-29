# frozen_string_literal: true

require "tmpdir"
require "fileutils"
require "uri"
require_relative "git_cli"
require_relative "commit_message_hygiene"

module Devops
  # The worker half of dev_merge_increment (the server half is
  # Ai::Tools::DevMergeTool, which dispatches only an APPROVED merge).
  #
  #   0. validate        the payload is re-checked here, before any git runs:
  #                      target_branch, source_ref, expected_source_sha,
  #                      submodule_path and the presence of forbidden_names,
  #                      with the SAME literals the server uses (a server spec
  #                      pins them equal). The worker is a second trust
  #                      boundary.
  #   1. verify_source   source_ref still resolves to expected_source_sha,
  #                      asked of the provider API (Devops::GitOperationsService)
  #                      and again of the fetched ref. Refused if it moved.
  #   2. fast_forward    every configured remote's target_branch must be the
  #                      expected SHA or an ancestor of it. Checked on EVERY
  #                      remote before pushing to ANY. Never forced.
  #   3. pointer_bump    optional, and BUILT here, before anything is pushed:
  #                      in the parent repository, check that .gitmodules maps
  #                      submodule_path to the repository being merged, then
  #                      move ONE gitlink through plumbing (read-tree /
  #                      update-index --cacheinfo / write-tree / commit-tree),
  #                      verify that path is the only change, and plan the
  #                      parent remotes the same fast-forward-only way.
  #   4. commit_hygiene  every commit each push would PUBLISH — per remote,
  #                      <that remote's tip>..<sha>, parent ranges included —
  #                      is checked for AI attribution and private-extension
  #                      names. One hit refuses the whole merge before a
  #                      single push. Refused, never rewritten.
  #   5. push            per remote, first re-read that remote's CURRENT head
  #                      (ls-remote): a remote that moved since the plan to a
  #                      non-ancestor is refused. Then <sha>:refs/heads/<target>
  #                      with --force-with-lease pinned to that exact head, so
  #                      the remote refuses it if the ref moved in between. Any remote that did not take it makes the
  #                      merge FAILED, and the pointer is then not pushed.
  #
  # Returns the report the job posts to the server and NEVER raises: a
  # refusal carries its reason, and any other exception becomes a failed
  # report naming only the exception class (a message can carry a provider's
  # response body or a URL). The per-remote entries are recorded as each push
  # happens, so a crash mid-loop still reports the remotes already pushed.
  #
  # `remote_resolver.call(repository_id)` answers
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
    # The server's literals (Ai::Tools::DevMergeTool), repeated here because
    # the worker shares no code with the server; dev_merge_tool_spec pins each
    # pair equal.
    TARGET_BRANCH = %r{\A(?:develop|master|release/[A-Za-z0-9][A-Za-z0-9._-]*)\z}
    REF = %r{\A(?!.*\.\.)(?!.*//)(?!.*@\{)(?!.*\.lock\z)[A-Za-z0-9][A-Za-z0-9._/-]*(?<![/.])\z}
    SHA = %r{\A\h{40}\z}
    SUBMODULE_PATH = %r{\A(?!-)(?!.*(?:\A|/)\.{1,2}(?:/|\z))[A-Za-z0-9._-]+(?:/[A-Za-z0-9._-]+)*\z}
    REMOTE_OK = %w[pushed up_to_date].freeze
    # Any control character but tab, newline and carriage return. A commit
    # carrying one is refused outright: it has no place in a published
    # message, and it is the input that could confuse a parser.
    CONTROL_CHARACTER = /[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]/

    def initialize(payload:, remote_resolver:, git_ops_factory:, workdir: nil, logger: nil,
                   git_timeout: GitCli::DEFAULT_TIMEOUT, allowed_protocols: GitCli::DEFAULT_PROTOCOLS)
      @payload = payload
      @remote_resolver = remote_resolver
      @git_ops_factory = git_ops_factory
      @workdir = workdir
      @logger = logger || Logger.new($stdout)
      @git_timeout = git_timeout
      @allowed_protocols = allowed_protocols
      @report = { "status" => "failed", "remotes" => [], "pointer_remotes" => [] }
    end

    def call
      @stage = "validate"
      validate_payload!
      with_workspace do |git|
        @git = git
        run!
      end
      @report.merge("status" => "succeeded", "stage" => nil).compact
    rescue Refusal => e
      failed(e.stage, e.message)
    rescue StandardError => e
      # Class only: a message can hold a provider body or a URL.
      failed(@stage, e.class.name)
    end

    attr_reader :git

    private

    def failed(stage, error)
      @report.merge("status" => "failed", "stage" => stage, "error" => error).compact
    end

    def expected
      @payload["expected_source_sha"].to_s.downcase
    end

    def target
      @payload["target_branch"].to_s
    end

    def forbidden_names
      @payload["forbidden_names"]
    end

    def validate_payload!
      refuse = ->(reason) { raise Refusal.new("validate", reason) }
      refuse.call("target_branch #{target.inspect} is not develop, master or release/<version>") unless target.match?(TARGET_BRANCH)
      refuse.call("source_ref is not a valid branch name") unless @payload["source_ref"].to_s.match?(REF)
      refuse.call("expected_source_sha is not a full 40-character SHA") unless expected.match?(SHA)
      refuse.call("no forbidden_names were dispatched; refusing to publish unchecked") unless forbidden_names.is_a?(Array)
      refuse.call("no remotes were dispatched") unless @payload["remotes"].is_a?(Array) && @payload["remotes"].any?

      bump = @payload["pointer_bump"]
      return if bump.nil?

      refuse.call("pointer_bump is not an object") unless bump.is_a?(Hash)
      return if bump["submodule_path"].to_s.match?(SUBMODULE_PATH)

      refuse.call("pointer_bump.submodule_path is not a valid relative path")
    end

    def run!
      remotes = @payload["remotes"].map { |r| resolve(r) }

      @stage = "verify_source"
      verify_source!(remotes.first)

      @stage = "fast_forward"
      plans = fast_forward_plans(remotes, expected, ref_prefix: "merge")

      bump = prepare_pointer_bump!(remotes) if @payload["pointer_bump"].is_a?(Hash)

      @stage = "commit_hygiene"
      check_published_ranges!(plans, expected)
      check_published_ranges!(bump[:plans], bump[:commit]) if bump

      @stage = "push"
      @report["merged_sha"] = expected
      push_all(plans, expected, into: "remotes")
      failed_remotes!("remotes", plans.size, "push", "remote(s) did not take the push")
      return unless bump

      @stage = "pointer_push"
      @report["pointer_commit_sha"] = bump[:commit]
      push_all(bump[:plans], bump[:commit], into: "pointer_remotes")
      failed_remotes!("pointer_remotes", bump[:plans].size, "pointer_push", "parent remote(s) did not take the pointer bump")
    end

    def failed_remotes!(key, total, stage, what)
      failed = @report[key].reject { |r| REMOTE_OK.include?(r["status"]) }
      raise Refusal.new(stage, "#{failed.size} of #{total} #{what}") if failed.any?
    end

    # ---- 1-2: the increment -------------------------------------------------

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

    # For each remote, [remote, plan, tip]: :up_to_date when its target
    # already IS `sha`, :push when its target is an ancestor of `sha`.
    # Anything else refuses the whole operation before a single push.
    def fast_forward_plans(remotes, sha, ref_prefix:)
      remotes.each_with_index.map do |remote, i|
        local = "refs/dev-merge/#{ref_prefix}-#{i}"
        fetch!(remote, "refs/heads/#{target}", local)
        tip = rev_parse(local)
        if tip == sha
          [ remote, :up_to_date, tip ]
        elsif ancestor?(tip, sha)
          [ remote, :push, tip ]
        else
          raise Refusal.new("fast_forward",
                            "#{target} on #{remote[:full_name]} (#{tip[0, 12]}) is not an ancestor of " \
                            "#{sha[0, 12]}; refusing a non-fast-forward")
        end
      end
    end

    # ---- 3: the parent's gitlink ----------------------------------------------

    def prepare_pointer_bump!(merged_remotes)
      bump = @payload["pointer_bump"]
      @stage = "pointer_bump"
      path = bump["submodule_path"].to_s
      parents = Array(bump["remotes"]).map { |r| resolve(r) }
      raise Refusal.new("pointer_bump", "no parent remotes were dispatched") if parents.empty?

      fetch!(parents.first, "refs/heads/#{target}", "refs/dev-merge/parent")
      parent_tip = rev_parse("refs/dev-merge/parent")
      current = gitlink_at(parent_tip, path)
      belongs_to_merged_repository!(parent_tip, path, merged_remotes)

      commit = current == expected ? parent_tip : pointer_commit(parent_tip, path, bump["summary"])

      @stage = "pointer_fast_forward"
      { commit: commit, plans: fast_forward_plans(parents, commit, ref_prefix: "parent") }
    end

    # .gitmodules at the parent tip must map `path` to the repository being
    # merged (its primary or one of its mirrors, compared as owner/name).
    # Otherwise this merge would record repository A's SHA at repository B's
    # path and publish a broken checkout.
    def belongs_to_merged_repository!(parent_tip, path, merged_remotes)
      url = gitmodules_url_for(parent_tip, path)
      raise Refusal.new("pointer_bump", "#{path} has no .gitmodules entry on #{target}") if url.nil?

      names = merged_remotes.map { |r| r[:full_name].to_s.downcase }
      return if names.include?(repository_path_of(url))

      raise Refusal.new("pointer_bump", "#{path} does not belong to the repository being merged (.gitmodules maps it " \
                                        "elsewhere)")
    end

    def gitmodules_url_for(tree_ish, path)
      blob = "#{tree_ish}:.gitmodules"
      listed = git.run("config", "--blob", blob, "--get-regexp", '^submodule\..*\.path$')
      return nil unless listed.success?

      name = listed.stdout.split("\n").filter_map do |line|
        key, value = line.split(" ", 2)
        key[/\Asubmodule\.(.+)\.path\z/, 1] if value.to_s.strip == path
      end.first
      return nil if name.nil?

      found = git.run("config", "--blob", blob, "--get", "submodule.#{name}.url")
      found.success? ? found.stdout.strip : nil
    end

    # owner/name from an https, ssh or scp-style remote URL.
    def repository_path_of(url)
      path = url.match?(%r{\A[a-z][a-z0-9+.-]*://}i) ? URI.parse(url).path.to_s : url.sub(/\A[^:]+:/, "")
      path.sub(%r{\A/+}, "").sub(/\.git\z/, "").downcase
    rescue URI::InvalidURIError
      nil
    end

    # The SHA the gitlink at `path` records, refusing when `path` is not a
    # gitlink at all — this job moves an existing submodule pointer, it never
    # creates one or overwrites a file.
    def gitlink_at(tree_ish, path)
      entry = git!("ls-tree", "--end-of-options", tree_ish, "--", path).stdout.strip
      mode, type, sha = entry.split(/\s+/, 4)
      return sha.to_s.downcase if mode == "160000" && type == "commit"

      raise Refusal.new("pointer_bump", "#{path} is not a submodule gitlink on #{target}")
    end

    def pointer_commit(parent_tip, path, summary)
      message = CommitMessageHygiene.pointer_bump_message(
        scope: File.basename(path), short_sha: expected[0, SHORT_SHA],
        summary: summary.to_s.strip.empty? ? subject_of(expected) : summary,
        forbidden_names: forbidden_names
      )

      index = File.join(@workspace, "pointer.index")
      index_env = { "GIT_INDEX_FILE" => index }
      git!("read-tree", "--end-of-options", parent_tip, env: index_env)
      git!("update-index", "--cacheinfo", "160000,#{expected},#{path}", env: index_env)
      tree = git!("write-tree", env: index_env).stdout.strip
      commit = git!("commit-tree", "-p", parent_tip, "-F", "-", "--end-of-options", tree,
                    env: identity_env, stdin: message).stdout.strip

      changed = git!("diff-tree", "-r", "--no-commit-id", "--name-only", "--end-of-options",
                     parent_tip, commit, "--").stdout.split("\n")
      unless changed == [ path ]
        raise Refusal.new("pointer_bump", "the pointer commit changed #{changed.size} path(s), not only #{path}")
      end

      commit
    rescue CommitMessageHygiene::Refused => e
      raise Refusal.new("pointer_bump", e.message)
    end

    def subject_of(sha)
      git!("log", "-1", "--format=%s", "--end-of-options", sha, "--").stdout.strip
    end

    def identity_env
      committer = @payload["committer"].is_a?(Hash) ? @payload["committer"] : {}
      name = committer["name"].to_s
      email = committer["email"].to_s
      raise Refusal.new("pointer_bump", "no committer identity was dispatched") if name.empty? || email.empty?

      { "GIT_AUTHOR_NAME" => name, "GIT_AUTHOR_EMAIL" => email,
        "GIT_COMMITTER_NAME" => name, "GIT_COMMITTER_EMAIL" => email }
    end

    # ---- 4: what each push would publish -------------------------------------

    # Per remote, because a remote that is further behind publishes more
    # commits. Names the offending commit and the remote, never the matched
    # name.
    #
    # BYTE-SAFE. The commits come from rev-list (one 40-hex SHA per line) and
    # each is read raw with cat-file, so nothing a commit contains can shift a
    # field boundary. (An earlier cut split a single `git log` stream on
    # \x1e/\x00, and a message containing \x1e split one commit into two
    # records, hiding whatever followed the byte.)
    def check_published_ranges!(plans, sha)
      plans.each do |remote, plan, tip|
        next unless plan == :push

        commits = git!("rev-list", "--end-of-options", "#{tip}..#{sha}", "--").stdout.split("\n")
        commits.each do |commit|
          raise Refusal.new("commit_hygiene", "rev-list returned #{commit.inspect}") unless commit.match?(SHA)

          reason = publication_problem(*commit_text(commit))
          next if reason.nil?

          raise Refusal.new("commit_hygiene", "commit #{commit[0, 12]} bound for #{remote[:full_name]} #{reason}; " \
                                              "refusing the whole merge")
        end
      end
    end

    # [message, [author, committer]] from the raw commit object: headers up to
    # the first blank line, the message after it.
    def commit_text(commit)
      raw = git!("cat-file", "commit", commit).stdout.b
      headers, message = raw.split("\n\n", 2)
      identity = headers.to_s.split("\n").filter_map do |line|
        line.sub(/\A(?:author|committer) /n, "") if line.match?(/\A(?:author|committer) /n)
      end
      [ message.to_s, identity ]
    end

    def publication_problem(message, identity)
      if [ message, *identity ].any? { |text| text.match?(CONTROL_CHARACTER) }
        return "contains a control character"
      end

      message = message.dup.force_encoding(Encoding::UTF_8).scrub
      identity = identity.map { |text| text.dup.force_encoding(Encoding::UTF_8).scrub }
      if message.lines.any? { |line| CommitMessageHygiene.attribution_line?(line) } ||
         identity.any? { |value| value.to_s.match?(CommitMessageHygiene::MODEL_WORDS) }
        return "carries AI attribution"
      end
      return "names a private extension" if CommitMessageHygiene.names_private?([ message, *identity ].join("\n"),
                                                                                 forbidden_names)

      nil
    end

    # ---- 5: push ---------------------------------------------------------------

    # Per remote, never short-circuited: the report must say what EVERY
    # remote did, because a partial push is the failure this reports. Each
    # entry is recorded as soon as its remote is done.
    #
    # The plan was made from a fetch that may now be stale, so each remote's
    # head is read again immediately before its push, and a remote that has
    # moved to anything that is not an ancestor of `sha` is REFUSED rather
    # than pushed. (A head this scratch repository has never seen cannot be
    # an ancestor of `sha`, whose history it holds, so the ancestry check
    # answers false for it too.)
    def push_all(plans, sha, into:)
      plans.each do |remote, _plan, _tip|
        @report[into] << push_one(remote, sha)
      end
    end

    def push_one(remote, sha)
      entry = { "repository_id" => remote[:repository_id], "full_name" => remote[:full_name] }
      head = remote_head(remote)
      return entry.merge("status" => "up_to_date") if head == sha

      unless head && ancestor?(head, sha)
        return entry.merge("status" => "refused",
                           "error" => "#{target} on #{remote[:full_name]} moved to " \
                                      "#{head ? head[0, 12] : 'nothing'} since the plan and is not an ancestor " \
                                      "of #{sha[0, 12]}; refusing a non-fast-forward")
      end

      # The lease makes the REMOTE enforce the head just read: if the ref is
      # not exactly `head` when the push lands, the remote refuses it. It is
      # not a force — `head` was verified above to be an ancestor of `sha`,
      # so the only update the lease can permit is a fast-forward.
      result = git.run("push", "--porcelain", "--force-with-lease=refs/heads/#{target}:#{head}", "--",
                       remote[:url], "#{sha}:refs/heads/#{target}",
                       auth_header: remote[:auth_header], secrets: remote[:secrets])
      return entry.merge("status" => "pushed") if result.success?

      if "#{result.stdout}\n#{result.stderr}".include?("stale info")
        return entry.merge("status" => "refused",
                           "error" => "#{target} on #{remote[:full_name]} moved after its head (#{head[0, 12]}) was " \
                                      "read; the remote refused the push against that lease")
      end

      entry.merge("status" => "failed", "error" => result.stderr.strip[0, 500])
    end

    # The remote's target head right now, or nil when it cannot be read.
    def remote_head(remote)
      result = git.run("ls-remote", "--", remote[:url], "refs/heads/#{target}",
                       auth_header: remote[:auth_header], secrets: remote[:secrets])
      return nil unless result.success?

      line = result.stdout.split("\n").map(&:split).find { |_sha, ref| ref == "refs/heads/#{target}" }
      line&.first&.downcase
    end

    # ---- plumbing ---------------------------------------------------------------

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
      result = git.run("fetch", "--no-tags", "--quiet", "--", remote[:url], "#{ref}:#{local}",
                       auth_header: remote[:auth_header], secrets: remote[:secrets])
      return if result.success?

      raise Refusal.new(@stage, "could not fetch #{ref} from #{remote[:full_name]}: #{result.stderr.strip[0, 300]}")
    end

    def rev_parse(ref)
      git!("rev-parse", "--verify", "--end-of-options", "#{ref}^{commit}").stdout.strip.downcase
    end

    def ancestor?(ancestor, descendant)
      git.run("merge-base", "--is-ancestor", "--end-of-options", ancestor, descendant).success?
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
      cli = GitCli.new(git_dir: repo, timeout: @git_timeout, allowed_protocols: @allowed_protocols)
      init = Open3.capture3(GitCli::BASE_ENV, "git", "init", "--bare", "--quiet", repo)
      raise Refusal.new("workspace", "could not create a workspace") unless init.last.success?

      yield cli
    ensure
      FileUtils.remove_entry(base) if base && @workdir.nil? && File.exist?(base)
    end
  end
end
