# frozen_string_literal: true

module Api
  module V1
    module Marketing
      module Public
        class LeadsController < ApplicationController
          # Public lead-capture endpoints — no authentication required.
          # Skips the JWT-based :authenticate_request callback defined in the
          # Authentication concern (included via ApplicationController).
          skip_before_action :authenticate_request, raise: false

          # POST /api/v1/marketing/public/leads/waitlist
          def waitlist
            email = params[:email].to_s.strip.downcase
            return render_error("Email is required", :unprocessable_entity) if email.blank?

            unless email.match?(URI::MailTo::EMAIL_REGEXP)
              return render_error("Invalid email format", :unprocessable_entity)
            end

            signup = ::Marketing::WaitlistSignup.find_or_initialize_by(email: email)

            if signup.persisted?
              # Idempotent: re-submitting the same email succeeds without leaking the prior signup time.
              return render_success(
                { already_subscribed: true, status: signup.status },
                message: "You're already on the waitlist."
              )
            end

            signup.assign_attributes(
              source: params[:source].to_s.presence || "homepage",
              ip_address: request.remote_ip,
              user_agent: request.user_agent.to_s[0, 500],
              referrer: request.referer.to_s[0, 500],
              metadata: extract_utm_params
            )

            if signup.save
              # Auto-confirm on creation: transition to confirmed and sync to
              # the "Cloud Waitlist" EmailList for nurture campaigns. confirm!
              # rescues sync failures internally, so this won't fail the
              # user-facing flow if EmailList machinery is unhealthy.
              signup.confirm!

              Rails.logger.info(
                "[Marketing] WaitlistSignup created+confirmed id=#{signup.id} " \
                "source=#{signup.source} subscriber=#{signup.email_subscriber_id || 'none'}"
              )
              render_success(
                { id: signup.id, email: signup.email, status: signup.status },
                message: "You're on the waitlist. We'll be in touch."
              )
            else
              render_error(
                signup.errors.full_messages.first || "Could not add to waitlist",
                :unprocessable_entity
              )
            end
          end

          private

          def extract_utm_params
            params.permit(:utm_source, :utm_medium, :utm_campaign, :utm_term, :utm_content).to_h
          end
        end
      end
    end
  end
end
