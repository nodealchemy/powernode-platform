# frozen_string_literal: true

require "net/http"
require "json"

module Ai
  module CodeFactory
    class RerunCoordinatorService
      class RerunError < StandardError; end

      RERUN_MARKER = "[code-factory-rerun]"

      def initialize(account:)
        @account = account
        @logger = Rails.logger
      end

      # Request a CI rerun with SHA-deduped marker
      def request_rerun(pr_number:, head_sha:, reason:, repository: nil)
        if has_existing_rerun_request?(pr_number: pr_number, head_sha: head_sha, repository: repository)
          @logger.info("[CodeFactory::RerunCoordinator] Skipping duplicate rerun request for PR ##{pr_number} sha:#{head_sha[0..7]}")
          return { requested: false, reason: "Duplicate rerun request" }
        end

        comment_body = "#{RERUN_MARKER} sha:#{head_sha} - #{reason}"

        post_pr_comment(pr_number: pr_number, body: comment_body, repository: repository)

        @logger.info("[CodeFactory::RerunCoordinator] Rerun requested for PR ##{pr_number} sha:#{head_sha[0..7]}")
        { requested: true, comment: comment_body }
      rescue StandardError => e
        @logger.error("[CodeFactory::RerunCoordinator] Error requesting rerun: #{e.message}")
        raise RerunError, e.message
      end

      # Check if a rerun request already exists for this SHA
      def has_existing_rerun_request?(pr_number:, head_sha:, repository: nil)
        comments = fetch_pr_comments(pr_number: pr_number, repository: repository)
        comments.any? { |c| c.to_s.include?("#{RERUN_MARKER} sha:#{head_sha}") }
      rescue StandardError => e
        @logger.warn("[CodeFactory::RerunCoordinator] Could not check existing reruns: #{e.message}")
        false
      end

      private

      def post_pr_comment(pr_number:, body:, repository:)
        credential = resolve_credential(repository)
        return unless credential

        owner, repo_name = repository.full_name.split("/", 2)
        api_base = credential.provider.effective_api_base_url.chomp("/")
        uri = URI("#{api_base}/repos/#{owner}/#{repo_name}/issues/#{pr_number}/comments")

        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"
        http.open_timeout = 10
        http.read_timeout = 30

        request = Net::HTTP::Post.new(uri)
        request["Authorization"] = "token #{credential.access_token}"
        request["Content-Type"] = "application/json"
        request["Accept"] = "application/json"
        request.body = { body: body }.to_json

        response = http.request(request)
        unless response.is_a?(Net::HTTPSuccess)
          @logger.warn("[CodeFactory::RerunCoordinator] Failed to post PR comment: #{response.code} #{response.body}")
        end
      end

      def fetch_pr_comments(pr_number:, repository:)
        credential = resolve_credential(repository)
        return [] unless credential

        owner, repo_name = repository.full_name.split("/", 2)
        api_base = credential.provider.effective_api_base_url.chomp("/")
        uri = URI("#{api_base}/repos/#{owner}/#{repo_name}/issues/#{pr_number}/comments")

        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"
        http.open_timeout = 10
        http.read_timeout = 30

        request = Net::HTTP::Get.new(uri)
        request["Authorization"] = "token #{credential.access_token}"
        request["Accept"] = "application/json"

        response = http.request(request)
        return [] unless response.is_a?(Net::HTTPSuccess)

        JSON.parse(response.body).map { |c| c["body"] }
      rescue StandardError
        []
      end

      def resolve_credential(repository)
        return nil unless repository

        credential = repository.credential
        return nil unless credential&.can_be_used?

        credential
      rescue StandardError => e
        @logger.warn("[CodeFactory::RerunCoordinator] Could not resolve credential: #{e.message}")
        nil
      end
    end
  end
end
