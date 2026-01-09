# frozen_string_literal: true

module Auth
  class ImpersonationService
    class Error < StandardError
      def error_code
        "impersonation_error"
      end

      def http_status
        :bad_request
      end
    end

    class PermissionDeniedError < Error
      def error_code
        "permission_denied"
      end

      def http_status
        :forbidden
      end
    end

    class InvalidUserError < Error
      def error_code
        "invalid_user"
      end

      def http_status
        :unprocessable_content
      end
    end

    class SessionNotFoundError < Error
      def error_code
        "session_not_found"
      end

      def http_status
        :not_found
      end
    end

    class SelfImpersonationError < Error
      def error_code
        "self_impersonation_not_allowed"
      end

      def http_status
        :forbidden
      end
    end

    def initialize(current_user)
      @current_user = current_user
    end

    def start_impersonation(target_user_id:, reason: nil, ip_address: nil, user_agent: nil)
      target_user = User.find(target_user_id)

      validate_impersonation_request!(target_user)

      # Create new impersonation session
      session = ImpersonationSession.create_session!(
        impersonator: @current_user,
        impersonated_user: target_user,
        reason: reason,
        ip_address: ip_address,
        user_agent: user_agent
      )

      # Log the impersonation start
      AuditLog.create!(
        user: @current_user,
        account: @current_user.account,
        action: "impersonation_started",
        resource_type: "User",
        resource_id: target_user.id,
        source: "admin_panel",
        ip_address: ip_address,
        user_agent: user_agent,
        metadata: {
          impersonated_user_email: target_user.email,
          reason: reason,
          session_id: session.id
        }
      )

      # Generate impersonation token
      generate_impersonation_token(session, target_user)
    end

    def end_impersonation(token_or_session_token)
      # Try to find the token as a UserToken first (new system)
      user_token = UserToken.find_by_token(token_or_session_token)

      if user_token && user_token.token_type == "impersonation"
        # This is an impersonation UserToken - get session from metadata
        session_id = user_token.metadata["session_id"]
        session = ImpersonationSession.find_by(id: session_id)

        unless session
          raise ActiveRecord::RecordNotFound, "Impersonation session not found"
        end

        # Revoke the UserToken when ending impersonation
        user_token.revoke!(reason: "impersonation_ended")
      elsif token_or_session_token.include?(".")
        # Legacy JWT token handling (for any remaining old tokens)
        begin
          payload = Security::JwtService.decode(token_or_session_token)

          unless payload[:type] == "impersonation"
            raise PermissionDeniedError, "Invalid impersonation token"
          end

          session = ImpersonationSession.find(payload[:session_id])
        rescue JWT::DecodeError => e
          raise PermissionDeniedError, "Invalid impersonation token"
        rescue ActiveRecord::RecordNotFound
          raise ActiveRecord::RecordNotFound, "Impersonation session not found"
        end
      else
        # This is a session token, find by session_token field
        session = ImpersonationSession.active.find_by!(session_token: token_or_session_token)
      end

      unless session.active?
        raise PermissionDeniedError, "Impersonation session is not active"
      end

      unless session.impersonator == @current_user
        raise PermissionDeniedError, "You can only end your own impersonation sessions"
      end

      session.end_session!

      # Log the impersonation end
      AuditLog.create!(
        user: @current_user,
        account: @current_user.account,
        action: "impersonation_ended",
        resource_type: "User",
        resource_id: session.impersonated_user_id,
        source: "admin_panel",
        metadata: {
          impersonated_user_email: session.impersonated_user.email,
          duration: session.duration.to_i,
          session_id: session.id
        }
      )

      session
    end

    def list_active_sessions(account_id = nil)
      account_id ||= @current_user.account_id

      ImpersonationSession.active
                         .for_account(account_id)
                         .includes(:impersonator, :impersonated_user)
                         .recent
    end

    def get_session_history(account_id = nil, limit: 50)
      account_id ||= @current_user.account_id

      ImpersonationSession.for_account(account_id)
                         .includes(:impersonator, :impersonated_user)
                         .recent
                         .limit(limit)
    end

    def validate_impersonation_token(token)
      # Try to find the token as a UserToken first (new system)
      user_token = UserToken.find_by_token(token)

      if user_token && user_token.token_type == "impersonation"
        # This is an impersonation UserToken - get session from metadata
        session_id = user_token.metadata["session_id"]
        session = ImpersonationSession.find_by(id: session_id)

        return nil unless session

        # Check if UserToken is active (handles expiration)
        return nil unless user_token.active?

        # Check if session has expired
        if session.expired?
          session.end_session!
          user_token.revoke!(reason: "session_expired")
          return nil
        end

        # Check if session is still active (not manually ended)
        return nil unless session.active?

        return session
      end

      # Legacy JWT token handling (for any remaining old tokens)
      begin
        payload = Security::JwtService.decode(token)

        return nil unless payload[:type] == "impersonation"

        session = ImpersonationSession.find_by(id: payload[:session_id])
        return nil unless session

        # Check if session has expired
        if session.expired?
          session.end_session!
          return nil
        end

        # Check if session is still active (not manually ended)
        return nil unless session.active?

        session
      rescue StandardError
        nil
      end
    end

    def self.cleanup_expired_sessions
      ImpersonationSession.cleanup_expired_sessions
    end

    private

    def validate_impersonation_request!(target_user)
      # Check if current user has impersonation permission
      unless @current_user.has_permission?("admin.user.impersonate") || @current_user.owner? || @current_user.admin?
        raise PermissionDeniedError, "You do not have permission to impersonate other users"
      end

      # Check if target user exists and is in the same account (unless user is system admin)
      unless target_user.account == @current_user.account || @current_user.has_permission?("system.admin")
        raise InvalidUserError, "You can only impersonate users in your own account"
      end

      # Prevent self-impersonation
      if target_user == @current_user
        raise SelfImpersonationError, "You cannot impersonate yourself"
      end

      # Check if target user is active
      unless target_user.active?
        raise InvalidUserError, "Cannot impersonate inactive user"
      end

      # Prevent impersonating owners if current user is not owner (unless system admin)
      if target_user.owner? && !@current_user.owner? && !@current_user.has_permission?("system.admin")
        raise PermissionDeniedError, "Only owners can impersonate other owners"
      end

      # Prevent system administrators from impersonating other system administrators
      if target_user.admin? && @current_user.admin?
        raise PermissionDeniedError, "System administrators cannot impersonate other system administrators"
      end
    end

    def generate_impersonation_token(session, target_user)
      # Create an impersonation UserToken instead of JWT
      result = UserToken.create_token_for_user(
        target_user,
        type: "impersonation",
        name: "Impersonation by #{@current_user.email}",
        expires_in: ImpersonationSession::MAX_SESSION_DURATION
      )

      # Store session metadata in the token for authentication lookup
      user_token = result[:user_token]
      user_token.update!(
        metadata: {
          session_id: session.id,
          impersonator_id: @current_user.id
        }
      )

      result[:token]
    end
  end
end

