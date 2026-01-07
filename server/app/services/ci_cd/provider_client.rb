# frozen_string_literal: true

module CiCd
  # Client for interacting with Git providers (Gitea, GitHub, GitLab)
  class ProviderClient
    class ApiError < StandardError; end
    class AuthenticationError < ApiError; end
    class NotFoundError < ApiError; end
    class RateLimitError < ApiError; end

    attr_reader :provider

    def initialize(provider)
      @provider = provider
    end

    # Test the connection to the provider
    # @return [Hash] Connection test result
    def test_connection
      case provider.provider_type
      when "gitea"
        test_gitea_connection
      when "github"
        test_github_connection
      when "gitlab"
        test_gitlab_connection
      else
        { success: false, message: "Unknown provider type: #{provider.provider_type}" }
      end
    rescue StandardError => e
      { success: false, message: e.message, details: { error_class: e.class.name } }
    end

    # List repositories from the provider
    # @param page [Integer] Page number
    # @param per_page [Integer] Items per page
    # @return [Array<Hash>] List of repositories
    def list_repositories(page: 1, per_page: 50)
      case provider.provider_type
      when "gitea"
        list_gitea_repositories(page: page, per_page: per_page)
      when "github"
        list_github_repositories(page: page, per_page: per_page)
      when "gitlab"
        list_gitlab_repositories(page: page, per_page: per_page)
      else
        []
      end
    end

    # Get repository details
    # @param full_name [String] Full repository name (owner/repo)
    # @return [Hash] Repository details
    def get_repository(full_name)
      case provider.provider_type
      when "gitea"
        get_gitea_repository(full_name)
      when "github"
        get_github_repository(full_name)
      when "gitlab"
        get_gitlab_repository(full_name)
      else
        raise ApiError, "Unknown provider type"
      end
    end

    # Create a pull request
    # @param repository [String] Repository full name
    # @param title [String] PR title
    # @param body [String] PR body
    # @param head [String] Source branch
    # @param base [String] Target branch
    # @return [Hash] Created PR details
    def create_pull_request(repository:, title:, body:, head:, base:)
      case provider.provider_type
      when "gitea"
        create_gitea_pull_request(repository, title, body, head, base)
      when "github"
        create_github_pull_request(repository, title, body, head, base)
      when "gitlab"
        create_gitlab_merge_request(repository, title, body, head, base)
      else
        raise ApiError, "Unknown provider type"
      end
    end

    # Post a comment on an issue or PR
    # @param repository [String] Repository full name
    # @param number [Integer] Issue/PR number
    # @param body [String] Comment body
    # @return [Hash] Created comment details
    def post_comment(repository:, number:, body:)
      case provider.provider_type
      when "gitea"
        post_gitea_comment(repository, number, body)
      when "github"
        post_github_comment(repository, number, body)
      when "gitlab"
        post_gitlab_comment(repository, number, body)
      else
        raise ApiError, "Unknown provider type"
      end
    end

    # Get diff for a PR
    # @param repository [String] Repository full name
    # @param number [Integer] PR number
    # @return [String] Diff content
    def get_pr_diff(repository:, number:)
      case provider.provider_type
      when "gitea"
        get_gitea_pr_diff(repository, number)
      when "github"
        get_github_pr_diff(repository, number)
      when "gitlab"
        get_gitlab_mr_diff(repository, number)
      else
        raise ApiError, "Unknown provider type"
      end
    end

    # Update commit status
    # @param repository [String] Repository full name
    # @param sha [String] Commit SHA
    # @param state [String] Status state (pending, success, failure, error)
    # @param context [String] Status context
    # @param description [String] Status description
    # @param target_url [String, nil] Target URL
    def update_commit_status(repository:, sha:, state:, context:, description:, target_url: nil)
      case provider.provider_type
      when "gitea"
        update_gitea_status(repository, sha, state, context, description, target_url)
      when "github"
        update_github_status(repository, sha, state, context, description, target_url)
      when "gitlab"
        update_gitlab_status(repository, sha, state, context, description, target_url)
      else
        raise ApiError, "Unknown provider type"
      end
    end

    private

    def base_url
      provider.base_url.chomp("/")
    end

    def api_token
      provider.api_token
    end

    def headers
      {
        "Authorization" => "token #{api_token}",
        "Content-Type" => "application/json",
        "Accept" => "application/json"
      }
    end

    # Gitea API methods
    def test_gitea_connection
      response = make_request(:get, "#{base_url}/api/v1/user")

      if response.code.to_i == 200
        user = JSON.parse(response.body)
        { success: true, message: "Connected as #{user['username']}", details: { user: user["username"] } }
      else
        { success: false, message: "Failed to connect: #{response.code}" }
      end
    end

    def list_gitea_repositories(page:, per_page:)
      response = make_request(:get, "#{base_url}/api/v1/user/repos?page=#{page}&limit=#{per_page}")
      handle_response(response)
    end

    def get_gitea_repository(full_name)
      owner, repo = full_name.split("/")
      response = make_request(:get, "#{base_url}/api/v1/repos/#{owner}/#{repo}")
      handle_response(response)
    end

    def create_gitea_pull_request(repository, title, body, head, base)
      owner, repo = repository.split("/")
      data = { title: title, body: body, head: head, base: base }
      response = make_request(:post, "#{base_url}/api/v1/repos/#{owner}/#{repo}/pulls", data.to_json)
      handle_response(response)
    end

    def post_gitea_comment(repository, number, body)
      owner, repo = repository.split("/")
      data = { body: body }
      response = make_request(:post, "#{base_url}/api/v1/repos/#{owner}/#{repo}/issues/#{number}/comments", data.to_json)
      handle_response(response)
    end

    def get_gitea_pr_diff(repository, number)
      owner, repo = repository.split("/")
      response = make_request(:get, "#{base_url}/api/v1/repos/#{owner}/#{repo}/pulls/#{number}.diff",
                              nil, { "Accept" => "text/plain" })
      response.body
    end

    def update_gitea_status(repository, sha, state, context, description, target_url)
      owner, repo = repository.split("/")
      data = {
        state: state,
        context: context,
        description: description,
        target_url: target_url
      }.compact
      response = make_request(:post, "#{base_url}/api/v1/repos/#{owner}/#{repo}/statuses/#{sha}", data.to_json)
      handle_response(response)
    end

    # GitHub API methods
    def test_github_connection
      response = make_request(:get, "https://api.github.com/user")

      if response.code.to_i == 200
        user = JSON.parse(response.body)
        { success: true, message: "Connected as #{user['login']}", details: { user: user["login"] } }
      else
        { success: false, message: "Failed to connect: #{response.code}" }
      end
    end

    def list_github_repositories(page:, per_page:)
      response = make_request(:get, "https://api.github.com/user/repos?page=#{page}&per_page=#{per_page}")
      handle_response(response)
    end

    def get_github_repository(full_name)
      response = make_request(:get, "https://api.github.com/repos/#{full_name}")
      handle_response(response)
    end

    def create_github_pull_request(repository, title, body, head, base)
      data = { title: title, body: body, head: head, base: base }
      response = make_request(:post, "https://api.github.com/repos/#{repository}/pulls", data.to_json)
      handle_response(response)
    end

    def post_github_comment(repository, number, body)
      data = { body: body }
      response = make_request(:post, "https://api.github.com/repos/#{repository}/issues/#{number}/comments", data.to_json)
      handle_response(response)
    end

    def get_github_pr_diff(repository, number)
      response = make_request(:get, "https://api.github.com/repos/#{repository}/pulls/#{number}",
                              nil, { "Accept" => "application/vnd.github.v3.diff" })
      response.body
    end

    def update_github_status(repository, sha, state, context, description, target_url)
      data = {
        state: state,
        context: context,
        description: description,
        target_url: target_url
      }.compact
      response = make_request(:post, "https://api.github.com/repos/#{repository}/statuses/#{sha}", data.to_json)
      handle_response(response)
    end

    # GitLab API methods
    def test_gitlab_connection
      response = make_request(:get, "#{base_url}/api/v4/user", nil, gitlab_headers)

      if response.code.to_i == 200
        user = JSON.parse(response.body)
        { success: true, message: "Connected as #{user['username']}", details: { user: user["username"] } }
      else
        { success: false, message: "Failed to connect: #{response.code}" }
      end
    end

    def list_gitlab_repositories(page:, per_page:)
      response = make_request(:get, "#{base_url}/api/v4/projects?membership=true&page=#{page}&per_page=#{per_page}",
                              nil, gitlab_headers)
      handle_response(response)
    end

    def get_gitlab_repository(full_name)
      encoded = CGI.escape(full_name)
      response = make_request(:get, "#{base_url}/api/v4/projects/#{encoded}", nil, gitlab_headers)
      handle_response(response)
    end

    def create_gitlab_merge_request(repository, title, body, head, base)
      encoded = CGI.escape(repository)
      data = { title: title, description: body, source_branch: head, target_branch: base }
      response = make_request(:post, "#{base_url}/api/v4/projects/#{encoded}/merge_requests", data.to_json, gitlab_headers)
      handle_response(response)
    end

    def post_gitlab_comment(repository, number, body)
      encoded = CGI.escape(repository)
      data = { body: body }
      response = make_request(:post, "#{base_url}/api/v4/projects/#{encoded}/merge_requests/#{number}/notes",
                              data.to_json, gitlab_headers)
      handle_response(response)
    end

    def get_gitlab_mr_diff(repository, number)
      encoded = CGI.escape(repository)
      response = make_request(:get, "#{base_url}/api/v4/projects/#{encoded}/merge_requests/#{number}/changes",
                              nil, gitlab_headers)
      changes = handle_response(response)
      changes["changes"]&.map { |c| c["diff"] }&.join("\n")
    end

    def update_gitlab_status(repository, sha, state, context, description, target_url)
      encoded = CGI.escape(repository)
      # GitLab uses different state names
      gitlab_state = case state
                     when "pending" then "pending"
                     when "success" then "success"
                     when "failure" then "failed"
                     when "error" then "failed"
                     else "pending"
                     end

      data = {
        state: gitlab_state,
        name: context,
        description: description,
        target_url: target_url
      }.compact
      response = make_request(:post, "#{base_url}/api/v4/projects/#{encoded}/statuses/#{sha}",
                              data.to_json, gitlab_headers)
      handle_response(response)
    end

    def gitlab_headers
      {
        "PRIVATE-TOKEN" => api_token,
        "Content-Type" => "application/json",
        "Accept" => "application/json"
      }
    end

    def make_request(method, url, body = nil, custom_headers = nil)
      uri = URI(url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = 10
      http.read_timeout = 30

      request = case method
                when :get
                  Net::HTTP::Get.new(uri)
                when :post
                  Net::HTTP::Post.new(uri)
                when :patch
                  Net::HTTP::Patch.new(uri)
                when :put
                  Net::HTTP::Put.new(uri)
                when :delete
                  Net::HTTP::Delete.new(uri)
                end

      (custom_headers || headers).each { |k, v| request[k] = v }
      request.body = body if body

      http.request(request)
    end

    def handle_response(response)
      case response.code.to_i
      when 200, 201, 202
        JSON.parse(response.body)
      when 401
        raise AuthenticationError, "Authentication failed"
      when 403
        if response["X-RateLimit-Remaining"]&.to_i == 0
          raise RateLimitError, "Rate limit exceeded"
        else
          raise ApiError, "Access forbidden"
        end
      when 404
        raise NotFoundError, "Resource not found"
      else
        raise ApiError, "API error: #{response.code} - #{response.body}"
      end
    end
  end
end
