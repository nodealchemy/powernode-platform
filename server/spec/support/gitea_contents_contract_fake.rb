# frozen_string_literal: true

require "open3"
require "base64"

# A Gitea REST endpoint backed by a REAL git repository on disk, for specs that
# must drive Devops::Git::GiteaApiClient (and GitToolExecutor through it) with no
# Gitea server. Every SHA it returns is one git produced with its own plumbing
# (hash-object, read-tree, update-index, write-tree, commit-tree, update-ref), so
# a spec reads results back with the git CLI, never from the platform's record.
#
# It is a CONTRACT fake, not a permissive stub. Each rule names its source, and a
# request that breaks one gets the status Gitea returns, never a 200:
#
#   [S] go-gitea/gitea modules/structs/repo_file.go — FileOptions,
#       CreateFileOptions, UpdateFileOptions ("content must be base64 encoded /
#       required: true"), FileResponse, FileCommitResponse, ContentsResponse.
#   [R] go-gitea/gitea routers/api/v1/repo/file.go — CreateFile swagger responses
#       201/403/404/422/423, UpdateFile 200/201/403/404/422/423;
#       handleChangeRepoFilesError maps a SHA mismatch and "file already exists"
#       to 422 and not-exist to 404 (there is no 409 on main); base64Reader
#       failure answers 422.
#   [C] the platform client this fake serves:
#       app/services/devops/git/gitea_api_client.rb and api_client.rb, and
#       app/services/ai/ralph/git_tool_executor.rb.
#
# Anything outside the surface it implements answers 501 and is recorded in
# #unhandled, so a spec can assert the client used only contract-backed calls.
class GiteaContentsContractFake
  # The exact keys GiteaApiClient#create_file / #update_file send
  # (gitea_api_client.rb:114-136) [C]. The drift guard pins them by EQUALITY, so
  # a change to the client's request shape fails a spec instead of passing here.
  CLIENT_CREATE_KEYS = %w[content message branch].freeze
  CLIENT_UPDATE_KEYS = %w[content message sha branch].freeze

  # json names of FileOptions + CreateFileOptions / UpdateFileOptions [S]. Gitea's
  # JSON binding ignores unknown keys, so this fake accepts them too but records
  # them in #unknown_keys for a spec to assert none were sent.
  FILE_OPTION_KEYS = %w[message branch new_branch force_push author committer dates signoff].freeze
  CREATE_KEYS = (FILE_OPTION_KEYS + %w[content]).freeze
  UPDATE_KEYS = (FILE_OPTION_KEYS + %w[content sha from_path]).freeze

  attr_reader :requests, :unhandled, :unknown_keys, :writes_refused

  def initialize(repo_path:, api_base:, owner:, repo:, token:, git_env: {})
    @repo_path = repo_path
    @api_path = URI(api_base).path
    @prefix = "/repos/#{owner}/#{repo}/"
    @token = token
    @git_env = git_env
    @requests = []
    @unhandled = []
    @unknown_keys = []
    @writes_refused = []
    @fail_next_write = nil
    @before_next_write = nil
  end

  # The next POST/PUT answers this status (after it is authenticated) instead of
  # committing — a provider outage or a server-side conflict.
  def fail_next_write(status:, message:)
    @fail_next_write = { status: status, message: message }
  end

  # Runs once, before the next write is validated — e.g. a concurrent commit that
  # makes the writer's sha stale.
  def before_next_write(&block)
    @before_next_write = block
  end

  # WebMock `to_return { |request| fake.call(request) }` entry point.
  def call(request)
    path = Addressable::URI.unencode(request.uri.path.delete_prefix(@api_path))
    body = parse_body(request)
    @requests << { method: request.method, path: path, body: body }

    # Auth: the client sends "Authorization: token <t>" (gitea_api_client.rb:825) [C].
    return reply(401, "message" => "token is required") unless request.headers["Authorization"] == "token #{@token}"
    return reply(404, "message" => "repository not found") unless path.start_with?(@prefix)

    route(request.method, path.delete_prefix(@prefix), request, body)
  end

  # Commit one file onto a branch with git plumbing; returns the commit SHA.
  def commit!(branch:, path:, content:, message:)
    parent = git!("rev-parse", "--verify", "refs/heads/#{branch}")
    blob = git!("hash-object", "-w", "--stdin", input: content)
    index = File.join(File.dirname(@repo_path), "index-#{SecureRandom.hex(6)}")
    index_env = { "GIT_INDEX_FILE" => index }
    git!("read-tree", parent, env: index_env)
    git!("update-index", "--add", "--cacheinfo", "100644,#{blob},#{path}", env: index_env)
    tree = git!("write-tree", env: index_env)
    commit = git!("commit-tree", tree, "-p", parent, "-m", message)
    git!("update-ref", "refs/heads/#{branch}", commit, parent)
    commit
  ensure
    FileUtils.rm_f(index) if index
  end

  private

  def route(method, rest, request, body)
    if method == :get && (m = rest.match(%r{\Abranches/(.+)\z}))
      branch_reply(m[1])
    elsif method == :get && (m = rest.match(%r{\Acontents/(.+)\z}))
      contents_reply(query(request)["ref"].presence || "main", m[1])
    elsif %i[post put].include?(method) && (m = rest.match(%r{\Acontents/(.+)\z}))
      write_reply(method, m[1], request, body)
    elsif method == :get && (m = rest.match(%r{\Agit/commits/(\h{40})\z}))
      commit_reply(m[1])
    elsif method == :get && (m = rest.match(%r{\Acommits/(\h{40})\.diff\z}))
      { status: 200, headers: { "Content-Type" => "text/plain" }, body: git!("diff", "#{m[1]}^", m[1], strip: false) }
    else
      @unhandled << [ method, rest ]
      reply(501, "message" => "not implemented by GiteaContentsContractFake: #{method} #{rest}")
    end
  end

  # Branch: Gitea's Branch.commit is a PayloadCommit, keyed "id" with no "sha"
  # (modules/structs/repo_branch.go, hook.go) [S]; the client reads commit.id
  # first (gitea_api_client.rb resolve_ref) [C]. Missing → 404 [R].
  def branch_reply(branch)
    sha = git_try("rev-parse", "--verify", "--quiet", "refs/heads/#{branch}")
    return reply(404, "message" => "branch does not exist [name: #{branch}]") unless sha

    reply(200, "name" => branch, "commit" => { "id" => sha })
  end

  # ContentsResponse [S]; the client decodes content only when encoding is
  # "base64" and reads sha/type/size (gitea_api_client.rb normalize_gitea_file_content) [C].
  def contents_reply(ref, file_path)
    commit = git_try("rev-parse", "--verify", "--quiet", "#{ref}^{commit}")
    blob = commit && git_try("rev-parse", "--verify", "--quiet", "#{commit}:#{file_path}")
    return reply(404, "message" => "object does not exist [id: #{ref}, rel_path: #{file_path}]") unless blob

    content = git!("cat-file", "blob", blob, strip: false)
    reply(200, "name" => File.basename(file_path), "path" => file_path, "sha" => blob, "type" => "file",
               "size" => content.bytesize, "encoding" => "base64", "content" => Base64.strict_encode64(content))
  end

  def write_reply(method, file_path, request, body)
    @before_next_write&.call
    @before_next_write = nil

    if (failure = @fail_next_write)
      @fail_next_write = nil
      return refuse(failure[:status], failure[:message])
    end

    # The client's Faraday connection encodes JSON (api_client.rb build_connection,
    # `conn.request :json`) [C]; a non-JSON body cannot bind to the options struct.
    return refuse(422, "request body must be a JSON object") unless json_request?(request) && body.is_a?(Hash)

    allowed = method == :post ? CREATE_KEYS : UPDATE_KEYS
    @unknown_keys.concat(body.keys - allowed)

    # content: required, base64 [S]; invalid base64 → 422 (base64Reader) [R].
    return refuse(422, "content is required") if body["content"].blank?

    content = strict_base64(body["content"])
    return refuse(422, "content is not valid base64") unless content

    # branch: the named branch must exist; not-exist → 404 [R].
    branch = body["branch"].presence || "main"
    parent = git_try("rev-parse", "--verify", "--quiet", "refs/heads/#{branch}")
    return refuse(404, "branch does not exist [name: #{branch}]") unless parent

    existing = git_try("rev-parse", "--verify", "--quiet", "#{parent}:#{file_path}")
    if method == :post
      # "file already exists" → 422 [R].
      return refuse(422, "repository file already exists [path: #{file_path}]") if existing
    else
      # sha: the client always sends the blob sha it read (gitea_api_client.rb
      # update_file; git_tool_executor.rb handle_write_file) [C] — main no longer
      # binds it Required [S], but a missing sha would disable the conflict check
      # the platform relies on, so it is refused here. Mismatch → 422 [R].
      return refuse(422, "sha is required") if body["sha"].blank?
      return refuse(422, "file does not exist [path: #{file_path}]") unless existing
      if sha_mismatch?(existing, body["sha"])
        return refuse(422, "sha does not match [given: #{body['sha']}, expected: #{existing}]")
      end
    end

    commit = commit!(branch: branch, path: file_path, content: content, message: body["message"].to_s)
    blob = git!("rev-parse", "#{commit}:#{file_path}")

    # FileResponse { content: ContentsResponse, commit: FileCommitResponse } [S];
    # create 201, update 200 [R]; the client reads commit.sha
    # (git_tool_executor.rb extract_commit_sha) [C].
    reply(method == :post ? 201 : 200,
          "content" => { "name" => File.basename(file_path), "path" => file_path, "sha" => blob,
                         "type" => "file", "size" => content.bytesize },
          "commit" => { "sha" => commit, "message" => body["message"].to_s,
                        "parents" => [ { "sha" => parent } ], "tree" => { "sha" => git!("rev-parse", "#{commit}^{tree}") } },
          "verification" => { "verified" => false, "reason" => "gpg.error.not_signed_commit" })
  end

  # Commit detail: the client reads sha, parents, commit.{message,author,committer},
  # files and stats (gitea_api_client.rb normalize_gitea_commit_detail) [C].
  def commit_reply(sha)
    return reply(404, "message" => "commit does not exist [id: #{sha}]") unless git_try("cat-file", "-e", "#{sha}^{commit}")

    parents = git!("rev-list", "--parents", "-n", "1", sha).split.drop(1)
    files = git!("diff-tree", "--no-commit-id", "--name-status", "-r", sha).lines.map do |line|
      status, name = line.strip.split("\t", 2)
      { "filename" => name, "status" => status == "A" ? "added" : "modified" }
    end
    person = { "name" => "gitea", "email" => "gitea@contract-fake.test", "date" => Time.current.iso8601 }
    reply(200, "sha" => sha, "parents" => parents.map { |p| { "sha" => p } },
               "commit" => { "message" => git!("log", "-1", "--format=%B", sha), "author" => person, "committer" => person },
               "files" => files, "stats" => {})
  end

  # The writer's sha must be the file's CURRENT blob sha — the optimistic-lock
  # check that turns a concurrent edit into a 422 instead of a lost update [R].
  def sha_mismatch?(existing, given)
    existing != given
  end

  def refuse(status, message)
    @writes_refused << { status: status, message: message }
    reply(status, "message" => message)
  end

  def reply(status, body)
    { status: status, headers: { "Content-Type" => "application/json" }, body: body.to_json }
  end

  def parse_body(request)
    return nil if request.body.blank?

    JSON.parse(request.body)
  rescue JSON::ParserError
    request.body
  end

  def json_request?(request)
    request.headers["Content-Type"].to_s.start_with?("application/json")
  end

  def query(request)
    Rack::Utils.parse_query(request.uri.query.to_s)
  end

  def strict_base64(value)
    return nil unless value.is_a?(String)

    Base64.strict_decode64(value)
  rescue ArgumentError
    nil
  end

  def git!(*args, input: nil, env: {}, strip: true)
    out, err, status = Open3.capture3(@git_env.merge(env), "git", "-C", @repo_path, *args, stdin_data: input.to_s)
    raise "git #{args.join(' ')} failed: #{err}" unless status.success?

    strip ? out.strip : out
  end

  def git_try(*args)
    git!(*args)
  rescue RuntimeError
    nil
  end
end
