# frozen_string_literal: true

module Api
  module V1
    module Chat
      class WebhooksController < ApplicationController
        include SecureParams

        # Skip authentication for webhook endpoints - they use signature verification
        skip_before_action :authenticate_request, only: %i[receive verify]
        skip_before_action :verify_authenticity_token, only: %i[receive verify], raise: false

        # Rate limit webhooks to prevent abuse
        before_action :apply_webhook_rate_limit, only: [ :receive ]

        # POST /api/v1/chat/webhooks/:token
        # Main webhook endpoint for receiving messages from chat platforms
        def receive
          channel = ::Chat::Channel.find_by!(webhook_token: params[:token])

          # Check channel-specific rate limit
          check_channel_rate_limit!(channel)

          # Verify webhook signature
          verification_service = ::Chat::WebhookVerificationService.new(channel)
          unless verification_service.verify!(request)
            render_error("Invalid signature", status: :unauthorized)
            return
          end

          # Process the webhook
          gateway_service = ::Chat::GatewayService.new(channel)
          result = gateway_service.process_webhook(request)

          if result[:success]
            # Return platform-appropriate response
            render_success(result[:response] || { status: "ok" })
          else
            Rails.logger.warn "Chat webhook processing failed: #{result[:error]}"
            render_error(result[:error], status: :unprocessable_entity)
          end
        rescue ActiveRecord::RecordNotFound
          render_error("Invalid webhook token", status: :not_found)
        rescue StandardError => e
          Rails.logger.error "Chat webhook error: #{e.message}"
          render_error("Internal error", status: :internal_server_error)
        end

        # GET /api/v1/chat/webhooks/:token/verify
        # Webhook verification endpoint (used by some platforms during setup)
        def verify
          channel = ::Chat::Channel.find_by!(webhook_token: params[:token])

          case channel.platform
          when "telegram"
            # Telegram doesn't need verification
            render_success({ status: "ok" })
          when "discord"
            # Discord sends a PING that needs to be ACKed
            if params[:type] == 1 # PING
              render json: { type: 1 }
            else
              render_success({ status: "ok" })
            end
          when "slack"
            # Slack URL verification challenge
            if params[:challenge].present?
              render json: { challenge: params[:challenge] }
            else
              render_success({ status: "ok" })
            end
          when "whatsapp"
            # WhatsApp verification
            if params["hub.mode"] == "subscribe" && params["hub.verify_token"] == channel.configuration["verify_token"]
              render plain: params["hub.challenge"]
            else
              render plain: "Verification failed", status: :forbidden
            end
          when "mattermost"
            # Mattermost token verification
            if params[:token] == channel.configuration["outgoing_token"]
              render_success({ status: "ok" })
            else
              render_error("Invalid token", status: :forbidden)
            end
          else
            render_success({ status: "ok" })
          end
        rescue ActiveRecord::RecordNotFound
          render_error("Invalid webhook token", status: :not_found)
        end

        private

        def apply_webhook_rate_limit
          check_rate_limit!(category: :chat_webhook, key: "ip:#{request.remote_ip}")
        rescue Security::RateLimiter::RateLimitExceeded => e
          response.headers["Retry-After"] = e.retry_after.to_s
          render_error("Too many requests", status: :too_many_requests)
        end

        def check_channel_rate_limit!(channel)
          limit = channel.rate_limit_per_minute || 60

          result = Security::RateLimiter.check!(
            key: "channel:#{channel.id}",
            category: :chat_webhook,
            account_id: channel.account_id,
            custom_limit: { limit: limit, window: 60 }
          )

          response.headers["X-RateLimit-Limit"] = result[:limit].to_s
          response.headers["X-RateLimit-Remaining"] = result[:remaining].to_s
        rescue Security::RateLimiter::RateLimitExceeded => e
          Rails.logger.warn "Channel rate limit exceeded for channel #{channel.id}"
          response.headers["Retry-After"] = e.retry_after.to_s
          render_error("Channel rate limit exceeded", status: :too_many_requests)
        end
      end
    end
  end
end
