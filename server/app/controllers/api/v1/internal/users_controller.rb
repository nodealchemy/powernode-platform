# frozen_string_literal: true

# Internal API controller for worker service to fetch and manage user data
class Api::V1::Internal::UsersController < Api::V1::Internal::InternalBaseController
  before_action :set_user, only: [ :show, :destroy, :anonymize, :anonymize_audit_logs,
                                    :delete_consents, :delete_terms_acceptances,
                                    :delete_password_histories, :delete_roles ]

  # GET /api/v1/internal/users/:id
  def show
    render_success(
      data: {
        id: @user.id,
        email: @user.email,
        name: @user.name,
        reset_token: @user.instance_variable_get(:@reset_token),
        email_verified: @user.email_verified?,
        created_at: @user.created_at,
        last_login_at: @user.last_login_at
      }
    )
  end

  # DELETE /api/v1/internal/users/:id
  def destroy
    @user.destroy
    render_success(message: "User deleted successfully")
  end

  # PATCH /api/v1/internal/users/:user_id/anonymize
  def anonymize
    @user.update(
      email: "deleted_#{@user.id}@anonymized.local",
      name: "Deleted User",
      phone: nil
    )
    render_success(message: "User anonymized successfully")
  end

  # PATCH /api/v1/internal/users/:user_id/anonymize_audit_logs
  def anonymize_audit_logs
    AuditLog.where(user_id: @user.id).update_all(
      ip_address: "0.0.0.0",
      user_agent: "anonymized"
    )
    render_success(message: "User audit logs anonymized")
  end

  # DELETE /api/v1/internal/users/:user_id/consents
  def delete_consents
    count = Consent.where(user_id: @user.id).delete_all
    render_success(message: "Deleted #{count} consent records")
  end

  # DELETE /api/v1/internal/users/:user_id/terms_acceptances
  def delete_terms_acceptances
    count = TermsAcceptance.where(user_id: @user.id).delete_all if defined?(TermsAcceptance)
    render_success(message: "Deleted #{count || 0} terms acceptance records")
  end

  # DELETE /api/v1/internal/users/:user_id/password_histories
  def delete_password_histories
    count = PasswordHistory.where(user_id: @user.id).delete_all if defined?(PasswordHistory)
    render_success(message: "Deleted #{count || 0} password history records")
  end

  # DELETE /api/v1/internal/users/:user_id/roles
  def delete_roles
    count = @user.user_roles.delete_all if @user.respond_to?(:user_roles)
    render_success(message: "Deleted #{count || 0} user role records")
  end

  private

  def set_user
    @user = User.find(params[:id] || params[:user_id])
  rescue ActiveRecord::RecordNotFound
    render_not_found("User")
  end
end
