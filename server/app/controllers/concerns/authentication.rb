# frozen_string_literal: true

module Authentication
  extend ActiveSupport::Concern

  # Raised by require_permission/require_any_permission/require_all_permissions
  # when the current entity lacks the permission.
  #
  # Inherits from Exception (NOT StandardError) DELIBERATELY. Many action bodies
  # wrap logic in `rescue StandardError` / `rescue => e`, and ApiResponse
  # registers a global `rescue_from StandardError` that renders a generic 500.
  # If this were a StandardError, an inline require_permission call inside such a
  # body — or that global handler — would swallow a clean 403 into a 500. Living
  # outside the StandardError hierarchy, it bypasses every `rescue StandardError`
  # and is handled ONLY by the dedicated rescue_from below, so the permission
  # check halts safely whether used as a before_action or (accidentally) inline.
  class PermissionDenied < Exception # rubocop:disable Lint/InheritException
    attr_reader :permission

    def initialize(message = "Permission denied", permission: nil)
      @permission = permission
      super(message)
    end
  end

  included do
    before_action :authenticate_request
    attr_reader :current_user, :current_account, :current_worker, :current_jwt_payload

    # Self-halting permission checks raise PermissionDenied; render the canonical
    # 403 shape here. Registered in Authentication (included before ApiResponse),
    # but since PermissionDenied is not a StandardError the ordering vs the global
    # rescue_from StandardError is irrelevant — only this handler matches it.
    rescue_from PermissionDenied do |exception|
      render_forbidden(exception.message) unless performed?
    end
  end

  private

  def authenticate_request
    header = request.headers["Authorization"]
    header = header.split(" ").last if header

    # Service auth via mTLS: with no bearer token, fall back to the reverse-
    # proxy-forwarded verified client-cert subject (worker → backend). Operator
    # controllers that use this filter already carve out worker callers via
    # `current_worker`; this sets it. mTLS-only controllers (Internal::*,
    # system worker_api) skip this filter and keep their own cert auth.
    unless header
      return if authenticate_worker_via_forwarded_cert

      return render_unauthorized("Access token required")
    end

    # JWT-only token authentication
    begin
      payload = Security::JwtService.decode(header)

      case payload[:type]
      when "access"
        handle_user_token(payload)
      when "worker"
        handle_worker_token(payload)
      when "impersonation"
        handle_impersonation_jwt_token(payload)
      else
        return render_unauthorized("Invalid token type")
      end

      # Validate user/account status for user tokens
      if @current_user
        return render_unauthorized("User inactive") unless @current_user.active?
        return render_unauthorized("No account associated") unless @current_account
        return render_unauthorized("Account suspended") unless @current_account.active?
        @current_user.record_login! if should_record_login?
      elsif @current_worker
        # Worker tokens are long-lived (30d). Re-validate the worker and its
        # account are still active on every request so a revoked/suspended worker
        # or a suspended account cannot keep operating until token expiry.
        return render_unauthorized("Worker inactive") unless @current_worker.active?
        return render_unauthorized("No account associated") unless @current_account
        return render_unauthorized("Account suspended") unless @current_account.active?
      end

      return
    rescue StandardError
      render_unauthorized("Invalid access token")
    end
  end

  # Resolve the worker from a reverse-proxy-forwarded mTLS client cert. Returns
  # true and sets @current_worker / @current_account on success.
  #
  # Routes through Security::MtlsTrust.verify_request — the SAME trust path the
  # worker_auth / Internal::* mTLS filters use — rather than parsing the raw
  # X-Forwarded-Tls-Client-Cert-Info header here: when a cert PEM is forwarded it
  # is cryptographically verified against OUR internal CA (a foreign-CA cert that
  # clones a worker's CN is rejected), falling back to the forwarded subject CN
  # only in the no-PEM posture where Traefik's chain-check is authoritative. This
  # closes the impersonation vector of trusting a client-forgeable Info header.
  def authenticate_worker_via_forwarded_cert
    cn = Security::MtlsTrust.verify_request(request)
    return false if cn.blank?

    worker = Worker.find_by(node_instance_id: cn)
    return false unless worker&.active?

    @current_worker = worker
    @current_account = worker.account
    request.env["powernode.internal_request"] = true
    true
  end

  def authenticate_optional
    header = request.headers["Authorization"]
    return unless header

    header = header.split(" ").last

    begin
      # JWT-only authentication
      payload = Security::JwtService.decode(header)

      case payload[:type]
      when "access"
        user = User.find(payload[:sub])
        if user&.active? && user.account&.active?
          @current_user = user
          @current_account = user.account
          @current_user.record_login! if should_record_login?
        end
      when "worker"
        worker = Worker.find(payload[:sub])
        if worker&.active? && worker.account&.active?
          @current_worker = worker
          @current_account = worker.account
        end
      when "impersonation"
        handle_impersonation_jwt_token(payload)
      end
    rescue StandardError
      @current_user = nil
      @current_account = nil
      @current_worker = nil
    end
  end

  def should_record_login?
    # Only record login once per hour to avoid excessive database writes
    # Don't record login for impersonation sessions
    return false if impersonating?

    current_user.last_login_at.nil? || current_user.last_login_at < 1.hour.ago
  end

  def handle_user_token(payload)
    @current_user = User.find(payload[:sub])
    @current_account = @current_user.account
    @current_jwt_payload = payload
    @impersonator = nil
    @impersonation_session = nil
  end

  def handle_worker_token(payload)
    @current_worker = Worker.find(payload[:sub])
    @current_account = @current_worker.account
    @current_jwt_payload = payload
  end

  def handle_impersonation_jwt_token(payload)
    # Get impersonation session ID from JWT metadata
    session_id = payload[:session_id]
    @impersonation_session = ImpersonationSession.find_by(id: session_id)

    unless @impersonation_session&.active?
      raise StandardError, "Invalid impersonation session"
    end

    if @impersonation_session.expired?
      @impersonation_session.end_session!
      raise StandardError, "Impersonation session expired"
    end

    # Set the impersonated user as current user
    @current_user = @impersonation_session.impersonated_user
    @current_account = @current_user.account
    @impersonator = @impersonation_session.impersonator

    # An impersonation session must not outlive the impersonator's own access.
    # Re-validate per request that the impersonator is still active AND still
    # authorized to impersonate this user; otherwise end the session. Without
    # this, deactivating or de-authorizing the impersonator leaves the session
    # fully usable until expiry (up to MAX_SESSION_DURATION).
    unless @impersonation_session.impersonator_currently_authorized?
      @impersonation_session.end_session!
      raise StandardError, "Impersonator no longer authorized"
    end

    @current_jwt_payload = payload

    # Add impersonation header for client identification
    response.set_header("X-Impersonation-Active", "true")
  end

  def impersonating?
    @impersonation_session.present?
  end

  def impersonator
    @impersonator
  end

  def impersonation_session
    @impersonation_session
  end

  # Permission checking methods (NEVER use roles for access control)
  # Self-halting: raises PermissionDenied (handled by the rescue_from above) so
  # the check halts whether used as a before_action OR inline in an action body.
  def require_permission(permission_name)
    return if has_permission?(permission_name)

    raise PermissionDenied.new("Permission denied: #{permission_name}", permission: permission_name)
  end

  def require_any_permission(*permission_names)
    return if permission_names.any? { |p| has_permission?(p) }

    raise PermissionDenied, "Permission denied: requires one of #{permission_names.join(', ')}"
  end

  def require_all_permissions(*permission_names)
    return if permission_names.all? { |p| has_permission?(p) }

    raise PermissionDenied, "Permission denied: requires all of #{permission_names.join(', ')}"
  end

  # Admin-surface guard shared by the admin/account/settings controllers.
  # `admin.access` is the baseline that always grants; callers pass any
  # resource-specific permissions that ALSO grant (e.g. "accounts.manage",
  # "settings.manage"). Centralizes the admin baseline so a permission rename
  # is a one-line change instead of four hand-rolled checks that drift.
  # Denies via PermissionDenied (→ 403), like every other permission check.
  def require_admin_access(*also_allow)
    require_any_permission("admin.access", *also_allow)
  end

  # Check if current entity (user or worker) has permission without rendering error
  def has_permission?(permission_name)
    # Account-switch / delegation session: the JWT carries a delegation_id and the
    # session's authority is the DELEGATION's scope — NOT the user's own-account
    # roles (User#has_permission? is not current_account-scoped, so falling through
    # would leak the user's own/global permissions into the delegated account).
    # Resolve from the live Account::Delegation so revocation/expiry takes effect
    # immediately, and do NOT fall through to current_user.
    if (delegation_id = @current_jwt_payload&.dig(:delegation_id)).present?
      return delegated_permission?(delegation_id, permission_name)
    end

    # For JWT tokens, check permissions directly from token payload (faster)
    if @current_jwt_payload&.dig(:permissions)&.include?(permission_name)
      return true
    end

    # Fallback to database checks
    return current_user.has_permission?(permission_name) if current_user
    return current_worker.has_permission?(permission_name) if current_worker
    false
  end

  # Resolve a permission for a delegated/account-switch session from the live
  # Account::Delegation's effective_permissions. Returns false for a missing,
  # revoked, or expired delegation so revocation is honored immediately (not
  # deferred to token expiry).
  def delegated_permission?(delegation_id, permission_name)
    delegation = ::Account::Delegation.find_by(id: delegation_id)
    return false unless delegation&.active?

    # Defense in depth: the delegation must actually delegate to THIS user. The
    # delegation_id is server-minted into the JWT bound to the switching user
    # (AccountSwitchService only embeds delegations from active_delegations.for_user),
    # so this always holds for a legitimately issued token — reject anything else.
    # (Target-account scoping is intentionally NOT asserted here: switched sessions
    # resolve current_account to the user's PRIMARY account, not the delegation
    # target, so a target == current_account check would forbid legitimate access.)
    return false unless current_user && delegation.delegated_user_id == current_user.id

    delegation.effective_permissions.include?(permission_name)
  end

  # LIVE controller-level permission check — not disposable back-compat.
  # Distinct from User#can?(permission_or_action, resource = nil): this one is
  # the controller-side single-arg form resolved against the request's entity
  # (user OR worker, delegation-aware). Called from controllers by the bare
  # name, so a plain grep for `.can?` will not find its callers.
  def can?(permission_name)
    has_permission?(permission_name)
  end

  # Check if current entity can access a resource action
  def can_access?(resource, action)
    has_permission?("#{resource}.#{action}")
  end

  # Note: render_unauthorized and render_forbidden are provided by ApiResponse concern
  # ApplicationController includes ApiResponse after Authentication, so those methods take precedence

  def extract_bearer_token
    auth_header = request.headers["Authorization"]
    return nil unless auth_header&.start_with?("Bearer ")

    auth_header.split(" ", 2).last
  end

  # Check if current request is from a worker
  def worker_authenticated?
    @current_worker.present?
  end
end
