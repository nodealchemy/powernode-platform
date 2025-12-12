# frozen_string_literal: true

module Api
  module V1
    class InvitationsController < ApplicationController
      before_action :authenticate_request, except: [ :accept ]
      before_action :set_invitation, only: [ :show, :update, :destroy, :resend, :cancel ]
      before_action :authorize_invitations_access!, only: [ :index, :create, :resend ]
      before_action :authorize_invitation_management!, only: [ :update, :destroy, :cancel ]

      # GET /api/v1/invitations
      def index
        invitations = current_user.account.invitations.includes(:inviter)

        # Apply filters
        invitations = invitations.where(status: params[:status]) if params[:status].present?
        invitations = invitations.where("expires_at >= ?", Time.current) if params[:include_expired] == false || params[:include_expired] == "false"

        # Order by creation date (newest first)
        invitations = invitations.order(created_at: :desc)

        render_success(
          invitations.map { |inv| invitation_json(inv) },
          meta: { total: invitations.count }
        )
      end

      # GET /api/v1/invitations/:id
      def show
        render_success(invitation_json(@invitation, include_token: false))
      end

      # POST /api/v1/invitations
      def create
        invitation = current_user.account.invitations.new(invitation_params)
        invitation.inviter = current_user

        if invitation.save
          # Send invitation email via worker
          WorkerJobService.enqueue_notification_email("invitation", {
            invitation_id: invitation.id,
            invitation_token: invitation.token
          })

          render_success(
            invitation_json(invitation, include_token: true),
            status: :created
          )
        else
          render_validation_error(invitation.errors)
        end
      end

      # PATCH /api/v1/invitations/:id
      def update
        if @invitation.update(update_params)
          render_success(
            invitation_json(@invitation)
          )
        else
          render_validation_error(@invitation.errors)
        end
      end

      # DELETE /api/v1/invitations/:id
      def destroy
        @invitation.destroy
        render_success
      end

      # POST /api/v1/invitations/:id/resend
      def resend
        unless @invitation.pending? && !@invitation.expired?
          return render_error("Can only resend pending, non-expired invitations", status: :unprocessable_content)
        end

        # Reset expiration to 7 days from now
        @invitation.update(expires_at: 7.days.from_now)

        # Resend invitation email via worker
        WorkerJobService.enqueue_notification_email("invitation", {
          invitation_id: @invitation.id,
          invitation_token: @invitation.token
        })

        render_success(
          invitation_json(@invitation)
        )
      end

      # POST /api/v1/invitations/:id/cancel
      def cancel
        if @invitation.cancel!
          render_success(
            invitation_json(@invitation)
          )
        else
          render_error("Failed to cancel invitation. It may be expired or already accepted.", status: :unprocessable_content)
        end
      end

      # POST /api/v1/invitations/accept
      # Public endpoint - accepts invitation token
      def accept
        token = params[:token]
        return render_error("Token is required", status: :bad_request) if token.blank?

        invitation = Invitation.find_by_token(token)
        return render_not_found("Invitation") unless invitation

        # Validate invitation status
        return render_error("Invitation has expired", status: :unprocessable_content) if invitation.expired?
        return render_error("Invitation has already been accepted", status: :unprocessable_content) if invitation.accepted?
        return render_error("Invitation has been cancelled", status: :unprocessable_content) if invitation.cancelled?

        # Create user account (in transaction)
        user = nil
        ActiveRecord::Base.transaction do
          user = User.create!(
            account: invitation.account,
            email: invitation.email,
            name: "#{invitation.first_name} #{invitation.last_name}",
            password: params[:password],
            password_confirmation: params[:password_confirmation],
            status: "active",
            email_verified_at: Time.current # Auto-verify since they accepted invitation
          )

          # Assign roles from invitation
          invitation.role_names.each do |role_name|
            role = Role.find_by(name: role_name)
            user.add_role(role.name) if role
          end

          # Mark invitation as accepted
          invitation.accept!
        end

        render_success(
          {
            user: user_json(user),
            message: "Invitation accepted successfully"
          },
          status: :created
        )
      rescue ActiveRecord::RecordInvalid => e
        render_error("Failed to create user: #{e.message}", status: :unprocessable_content)
      end

      private

      def set_invitation
        @invitation = current_user.account.invitations.find_by(id: params[:id])
        render_not_found("Invitation") unless @invitation
      end

      def authorize_invitations_access!
        unless current_user.has_permission?("team.invite") || current_user.has_permission?("users.create")
          render_forbidden
        end
      end

      def authorize_invitation_management!
        # Only the inviter or admins can manage invitations
        unless @invitation.inviter_id == current_user.id ||
               current_user.has_permission?("users.manage") ||
               current_user.has_permission?("team.manage")
          render_forbidden
        end
      end

      def invitation_params
        params.require(:invitation).permit(
          :email,
          :first_name,
          :last_name,
          :expires_at,
          role_names: []
        )
      end

      def update_params
        params.require(:invitation).permit(
          :first_name,
          :last_name,
          :expires_at,
          role_names: []
        )
      end

      def invitation_json(invitation, include_token: false)
        {
          id: invitation.id,
          email: invitation.email,
          first_name: invitation.first_name,
          last_name: invitation.last_name,
          status: invitation.status,
          role_names: invitation.role_names,
          expires_at: invitation.expires_at,
          accepted_at: invitation.accepted_at,
          inviter: {
            id: invitation.inviter_id,
            name: invitation.inviter.name,
            email: invitation.inviter.email
          },
          created_at: invitation.created_at,
          updated_at: invitation.updated_at
        }.tap do |json|
          # Only include token when creating invitation (for email link)
          json[:token] = invitation.token if include_token
        end
      end

      def user_json(user)
        {
          id: user.id,
          email: user.email,
          name: user.name
        }
      end
    end
  end
end
