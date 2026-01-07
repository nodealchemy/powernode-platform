# frozen_string_literal: true

module CiCd
  module GitProviders
    # Normalizes webhook payloads from different git providers into a common format
    class WebhookNormalizer
      # Normalized event types
      EVENT_PUSH = "push"
      EVENT_PULL_REQUEST = "pull_request"
      EVENT_PULL_REQUEST_REVIEW = "pull_request_review"
      EVENT_ISSUE = "issue"
      EVENT_ISSUE_COMMENT = "issue_comment"
      EVENT_CREATE = "create"
      EVENT_DELETE = "delete"
      EVENT_RELEASE = "release"
      EVENT_WORKFLOW_RUN = "workflow_run"

      # PR actions
      ACTION_OPENED = "opened"
      ACTION_CLOSED = "closed"
      ACTION_MERGED = "merged"
      ACTION_REOPENED = "reopened"
      ACTION_SYNCHRONIZE = "synchronize"
      ACTION_EDITED = "edited"
      ACTION_LABELED = "labeled"
      ACTION_UNLABELED = "unlabeled"
      ACTION_REVIEW_REQUESTED = "review_requested"

      class << self
        # Normalize a webhook payload
        # @param provider_type [Symbol] :gitea, :gitlab, or :github
        # @param event_type [String] The event type header from the webhook
        # @param payload [Hash] The webhook payload
        # @return [Hash] Normalized payload
        def normalize(provider_type:, event_type:, payload:)
          normalizer = case provider_type.to_sym
                       when :gitea then GiteaNormalizer.new
                       when :gitlab then GitlabNormalizer.new
                       when :github then GithubNormalizer.new
                       else
                         raise ArgumentError, "Unknown provider type: #{provider_type}"
                       end

          normalizer.normalize(event_type: event_type, payload: payload)
        end

        # Detect provider type from webhook headers
        # @param headers [Hash] HTTP headers from the webhook request
        # @return [Symbol, nil] Detected provider type or nil
        def detect_provider(headers)
          if headers["X-Gitea-Event"].present? || headers["X-Gitea-Delivery"].present?
            :gitea
          elsif headers["X-Gitlab-Event"].present? || headers["X-Gitlab-Token"].present?
            :gitlab
          elsif headers["X-GitHub-Event"].present? || headers["X-GitHub-Delivery"].present?
            :github
          end
        end

        # Get the event type from headers
        # @param headers [Hash] HTTP headers
        # @param provider_type [Symbol] Provider type
        # @return [String, nil] Event type
        def extract_event_type(headers:, provider_type:)
          case provider_type
          when :gitea
            headers["X-Gitea-Event"]
          when :gitlab
            headers["X-Gitlab-Event"]&.sub(" Hook", "")&.downcase&.gsub(" ", "_")
          when :github
            headers["X-GitHub-Event"]
          end
        end

        # Verify webhook signature
        # @param provider_type [Symbol] Provider type
        # @param payload [String] Raw payload body
        # @param signature [String] Signature from headers
        # @param secret [String] Webhook secret
        # @return [Boolean] Whether signature is valid
        def verify_signature(provider_type:, payload:, signature:, secret:)
          return true if secret.blank?
          return false if signature.blank?

          case provider_type
          when :gitea, :github
            expected = "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', secret, payload)}"
            ActiveSupport::SecurityUtils.secure_compare(expected, signature)
          when :gitlab
            ActiveSupport::SecurityUtils.secure_compare(secret, signature)
          else
            false
          end
        end
      end

      # Base normalizer class
      class BaseNormalizer
        def normalize(event_type:, payload:)
          {
            provider: provider_type,
            event: normalize_event_type(event_type),
            action: extract_action(event_type, payload),
            timestamp: Time.current.iso8601,
            delivery_id: extract_delivery_id(payload),
            repository: normalize_repository(payload),
            sender: normalize_sender(payload),
            **event_specific_data(event_type, payload)
          }.compact
        end

        protected

        def provider_type
          raise NotImplementedError
        end

        def normalize_event_type(event_type)
          raise NotImplementedError
        end

        def extract_action(event_type, payload)
          payload["action"]
        end

        def extract_delivery_id(payload)
          nil
        end

        def normalize_repository(payload)
          repo = payload["repository"] || {}
          {
            id: repo["id"],
            name: repo["name"],
            full_name: repo["full_name"],
            private: repo["private"],
            default_branch: repo["default_branch"],
            clone_url: repo["clone_url"],
            html_url: repo["html_url"]
          }
        end

        def normalize_sender(payload)
          sender = payload["sender"] || {}
          {
            id: sender["id"],
            login: sender["login"] || sender["username"],
            avatar_url: sender["avatar_url"]
          }
        end

        def event_specific_data(event_type, payload)
          {}
        end
      end

      # Gitea webhook normalizer
      class GiteaNormalizer < BaseNormalizer
        protected

        def provider_type
          :gitea
        end

        def normalize_event_type(event_type)
          case event_type
          when "push" then EVENT_PUSH
          when "pull_request" then EVENT_PULL_REQUEST
          when "pull_request_review" then EVENT_PULL_REQUEST_REVIEW
          when "issues" then EVENT_ISSUE
          when "issue_comment" then EVENT_ISSUE_COMMENT
          when "create" then EVENT_CREATE
          when "delete" then EVENT_DELETE
          when "release" then EVENT_RELEASE
          else event_type
          end
        end

        def event_specific_data(event_type, payload)
          case normalize_event_type(event_type)
          when EVENT_PUSH
            normalize_push_event(payload)
          when EVENT_PULL_REQUEST
            normalize_pr_event(payload)
          when EVENT_ISSUE, EVENT_ISSUE_COMMENT
            normalize_issue_event(payload)
          else
            {}
          end
        end

        def normalize_push_event(payload)
          {
            ref: payload["ref"],
            before: payload["before"],
            after: payload["after"],
            compare_url: payload["compare_url"],
            commits: (payload["commits"] || []).map do |c|
              {
                id: c["id"],
                message: c["message"],
                author: c.dig("author", "name") || c.dig("author", "username"),
                timestamp: c["timestamp"]
              }
            end,
            head_commit: payload["head_commit"] ? {
              id: payload["head_commit"]["id"],
              message: payload["head_commit"]["message"]
            } : nil,
            pusher: {
              name: payload.dig("pusher", "name") || payload.dig("pusher", "username")
            }
          }
        end

        def normalize_pr_event(payload)
          pr = payload["pull_request"] || {}
          {
            pull_request: {
              id: pr["id"],
              number: pr["number"],
              title: pr["title"],
              body: pr["body"],
              state: pr["state"],
              merged: pr["merged"],
              draft: pr["draft"],
              head: {
                ref: pr.dig("head", "ref"),
                sha: pr.dig("head", "sha")
              },
              base: {
                ref: pr.dig("base", "ref"),
                sha: pr.dig("base", "sha")
              },
              html_url: pr["html_url"],
              user: {
                login: pr.dig("user", "login")
              }
            }
          }
        end

        def normalize_issue_event(payload)
          issue = payload["issue"] || {}
          {
            issue: {
              id: issue["id"],
              number: issue["number"],
              title: issue["title"],
              body: issue["body"],
              state: issue["state"],
              html_url: issue["html_url"]
            },
            comment: payload["comment"] ? {
              id: payload["comment"]["id"],
              body: payload["comment"]["body"],
              user: { login: payload.dig("comment", "user", "login") }
            } : nil
          }
        end
      end

      # GitLab webhook normalizer
      class GitlabNormalizer < BaseNormalizer
        protected

        def provider_type
          :gitlab
        end

        def normalize_event_type(event_type)
          case event_type&.downcase&.gsub(" ", "_")
          when "push", "push_hook" then EVENT_PUSH
          when "merge_request", "merge_request_hook" then EVENT_PULL_REQUEST
          when "note", "note_hook" then EVENT_ISSUE_COMMENT
          when "issue", "issue_hook" then EVENT_ISSUE
          when "tag_push", "tag_push_hook" then EVENT_CREATE
          when "release", "release_hook" then EVENT_RELEASE
          when "pipeline", "pipeline_hook" then EVENT_WORKFLOW_RUN
          else event_type
          end
        end

        def extract_action(event_type, payload)
          # GitLab uses object_attributes.action or object_attributes.state
          payload.dig("object_attributes", "action") ||
            payload.dig("object_attributes", "state") ||
            payload["action"]
        end

        def normalize_repository(payload)
          project = payload["project"] || payload["repository"] || {}
          {
            id: project["id"],
            name: project["name"],
            full_name: project["path_with_namespace"],
            private: project["visibility"] == "private",
            default_branch: project["default_branch"],
            clone_url: project["http_url"] || project["git_http_url"],
            html_url: project["web_url"]
          }
        end

        def normalize_sender(payload)
          user = payload["user"] || {}
          {
            id: user["id"],
            login: user["username"],
            avatar_url: user["avatar_url"]
          }
        end

        def event_specific_data(event_type, payload)
          case normalize_event_type(event_type)
          when EVENT_PUSH
            normalize_push_event(payload)
          when EVENT_PULL_REQUEST
            normalize_mr_event(payload)
          when EVENT_ISSUE_COMMENT
            normalize_note_event(payload)
          else
            {}
          end
        end

        def normalize_push_event(payload)
          {
            ref: payload["ref"],
            before: payload["before"],
            after: payload["after"],
            commits: (payload["commits"] || []).map do |c|
              {
                id: c["id"],
                message: c["message"],
                author: c.dig("author", "name"),
                timestamp: c["timestamp"]
              }
            end,
            pusher: {
              name: payload.dig("user_name") || payload.dig("user", "name")
            }
          }
        end

        def normalize_mr_event(payload)
          mr = payload["object_attributes"] || {}
          {
            pull_request: {
              id: mr["id"],
              number: mr["iid"],
              title: mr["title"],
              body: mr["description"],
              state: mr["state"] == "opened" ? "open" : mr["state"],
              merged: mr["state"] == "merged",
              draft: mr["work_in_progress"] || mr["draft"],
              head: {
                ref: mr["source_branch"],
                sha: mr["last_commit"]&.dig("id")
              },
              base: {
                ref: mr["target_branch"],
                sha: nil
              },
              html_url: mr["url"],
              user: {
                login: payload.dig("user", "username")
              }
            }
          }
        end

        def normalize_note_event(payload)
          attrs = payload["object_attributes"] || {}
          {
            issue: payload["issue"] ? {
              id: payload["issue"]["id"],
              number: payload["issue"]["iid"],
              title: payload["issue"]["title"]
            } : nil,
            merge_request: payload["merge_request"] ? {
              id: payload["merge_request"]["id"],
              number: payload["merge_request"]["iid"],
              title: payload["merge_request"]["title"]
            } : nil,
            comment: {
              id: attrs["id"],
              body: attrs["note"],
              user: { login: payload.dig("user", "username") }
            }
          }
        end
      end

      # GitHub webhook normalizer
      class GithubNormalizer < BaseNormalizer
        protected

        def provider_type
          :github
        end

        def normalize_event_type(event_type)
          case event_type
          when "push" then EVENT_PUSH
          when "pull_request" then EVENT_PULL_REQUEST
          when "pull_request_review" then EVENT_PULL_REQUEST_REVIEW
          when "issues" then EVENT_ISSUE
          when "issue_comment" then EVENT_ISSUE_COMMENT
          when "create" then EVENT_CREATE
          when "delete" then EVENT_DELETE
          when "release" then EVENT_RELEASE
          when "workflow_run" then EVENT_WORKFLOW_RUN
          else event_type
          end
        end

        def event_specific_data(event_type, payload)
          case normalize_event_type(event_type)
          when EVENT_PUSH
            normalize_push_event(payload)
          when EVENT_PULL_REQUEST
            normalize_pr_event(payload)
          when EVENT_ISSUE, EVENT_ISSUE_COMMENT
            normalize_issue_event(payload)
          else
            {}
          end
        end

        def normalize_push_event(payload)
          {
            ref: payload["ref"],
            before: payload["before"],
            after: payload["after"],
            compare_url: payload["compare"],
            commits: (payload["commits"] || []).map do |c|
              {
                id: c["id"],
                message: c["message"],
                author: c.dig("author", "name"),
                timestamp: c["timestamp"]
              }
            end,
            head_commit: payload["head_commit"] ? {
              id: payload["head_commit"]["id"],
              message: payload["head_commit"]["message"]
            } : nil,
            pusher: {
              name: payload.dig("pusher", "name")
            }
          }
        end

        def normalize_pr_event(payload)
          pr = payload["pull_request"] || {}
          {
            pull_request: {
              id: pr["id"],
              number: pr["number"],
              title: pr["title"],
              body: pr["body"],
              state: pr["state"],
              merged: pr["merged"],
              draft: pr["draft"],
              head: {
                ref: pr.dig("head", "ref"),
                sha: pr.dig("head", "sha")
              },
              base: {
                ref: pr.dig("base", "ref"),
                sha: pr.dig("base", "sha")
              },
              html_url: pr["html_url"],
              user: {
                login: pr.dig("user", "login")
              }
            }
          }
        end

        def normalize_issue_event(payload)
          issue = payload["issue"] || {}
          {
            issue: {
              id: issue["id"],
              number: issue["number"],
              title: issue["title"],
              body: issue["body"],
              state: issue["state"],
              html_url: issue["html_url"]
            },
            comment: payload["comment"] ? {
              id: payload["comment"]["id"],
              body: payload["comment"]["body"],
              user: { login: payload.dig("comment", "user", "login") }
            } : nil
          }
        end
      end
    end
  end
end
