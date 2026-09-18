# frozen_string_literal: true

# Internal API controller for worker service to fetch and manage user data
class Api::V1::Internal::UsersController < Api::V1::Internal::InternalBaseController
  before_action :set_user, only: [ :show, :anonymize, :anonymize_audit_logs,
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
        # Plaintext in the DB (users.email_verification_token). Served here so
        # the worker can read it instead of receiving it as a Sidekiq job
        # argument, which is logged twice and persisted in the Redis payload.
        # The password-reset token has no equivalent: it is stored only as a
        # BCrypt digest, so it cannot be served and must travel in args.
        email_verification_token: @user.email_verification_token,
        email_verified: @user.email_verified?,
        created_at: @user.created_at,
        last_login_at: @user.last_login_at
      }
    )
  end

  # PATCH /api/v1/internal/users/:user_id/anonymize
  #
  # Design = anonymize-in-place: this owns the FULL field list for GDPR
  # anonymization (IMP-7ff4be3454a6). Callers (DataDeletionJob,
  # AccountTerminationJob) pass no body — any per-call payload here would be
  # meaningless, since every field below is fixed by the design, not by the
  # caller. `update!` (not `update`) so a validation failure raises and
  # surfaces as a non-2xx to the worker's BackendApiClient (which raises
  # ApiError on any non-2xx — see #handle_response) instead of silently
  # rendering "successfully" over an unmodified row.
  #
  # `status: inactive` (no new status, no migration — operator direction).
  # Verified before this fix (not just assumed) that `inactive` blocks every
  # non-operator path back to a working session: login (Auth::SessionsController
  # #create checks user.active?), the JWT bearer check on every authenticated
  # request (Authentication#authenticate_request checks @current_user.active?
  # LIVE per request, so an already-issued token stops working), JWT refresh
  # and 2FA verification (JwtService#refresh_access_token / #verify_2fa_token
  # both raise unless user&.active?), and password reset (#forgot only sends
  # the email if user.active?; a completed reset still leaves status
  # untouched, so login stays blocked regardless). Invitation re-accept mints
  # a brand-new User row against the invitation's email, not this one, since
  # the email column below is overwritten with the placeholder. There is no
  # user-facing SSO/OAuth login path in this codebase to check. The only
  # surviving path — Api::V1::UsersController#activate — is itself gated by
  # `admin.user.manage`, an explicit operator-gated admin action; left as-is
  # per operator direction.
  def anonymize
    # Transactional: #update! setting `password:` fires PasswordSecurity's
    # before_update :track_password_change, which writes the OUTGOING
    # password_digest — the bcrypt digest of the user's REAL previous
    # password — into a fresh password_histories row (password_security.rb
    # #track_password_change). That row, plus any of the user's last-12
    # history rows already on disk, are exactly the credential material this
    # endpoint exists to erase, so they must not survive it: deleted in the
    # SAME transaction as the update, not as an afterthought outside it.
    # Auditable's automatic "updated" audit row (fired by @user.update! below,
    # via after_update) must not become an unredacted second copy of the PII
    # this endpoint exists to erase — the controller's own log_internal_audit
    # ("user.anonymize") call below is the intended record of the event.
    # Auditable#audit_extra_redactions is the per-instance, per-write seam for
    # exactly this (see its declaration in auditable.rb for why it exists
    # instead of a class-wide filter_attributes change or toggling
    # Auditable.logging_enabled): every field this write changes — PII, a
    # credential, or simply pre-erasure STATE that shouldn't outlive the
    # erasure event in a durable audit row — whether or not it is ALREADY
    # covered by User's global redaction (email/name via `encrypts`,
    # password_digest via ALWAYS_REDACTED_ATTRIBUTES,
    # two_factor_secret/backup_codes/last_login_ip via `encrypts`,
    # email_verified/email_verification_token/etc. via the "email" substring
    # filter). Listed here even where redundant with that global coverage —
    # and status/two_factor_enabled/two_factor_enabled_at/
    # reset_token_expires_at/password_changed_at, none of which any existing
    # rule touches — so this line is a complete, self-contained statement of
    # what this specific write must not archive.
    @user.audit_extra_redactions = %w[
      email name preferences notification_preferences authorized_keys
      last_login_ip email_verification_token status two_factor_enabled
      two_factor_enabled_at reset_token_expires_at password_changed_at
    ]

    @user.transaction do
      @user.update!(
        email: "deleted_#{@user.id}@anonymized.local",
        name: "Deleted User",
        status: "inactive",
        password: unusable_random_password,
        email_verified: false,
        email_verified_at: nil,
        two_factor_secret: nil,
        two_factor_enabled: false,
        two_factor_enabled_at: nil,
        backup_codes: nil,
        two_factor_backup_codes_generated_at: nil,
        last_login_ip: nil,
        preferences: {},
        notification_preferences: {},
        reset_token_digest: nil,
        reset_token_expires_at: nil,
        email_verification_token: nil,
        email_verification_sent_at: nil,
        email_verification_token_expires_at: nil,
        # OpenSSH public keys distributed to every node in the account (see
        # User#authorized_keys). System::Node#authorized_keys already
        # excludes non-active users (account.users.active.find_each), so
        # status: inactive alone drops this user's keys from the next
        # reconciliation — clearing the column here is defense in depth,
        # not load-bearing.
        authorized_keys: []
      )

      @user.password_histories.delete_all
    end

    # Revoke every already-issued JWT (access + refresh) for this user via the
    # existing blacklist seam — no new revocation mechanism. User-level marker
    # revokes anything issued before now; a legitimate re-login after this
    # point (there isn't one, since login/refresh/authenticate_request all
    # gate on status) would still mint fresh, unaffected tokens. Its return
    # value is checked and is now a deliberate boolean, not an accidental one
    # (Security::JwtBlacklistService returns an explicit true/false as of
    # this same fix) — an ignored return here would let the endpoint report
    # "successfully" over a user whose stolen/leaked tokens are still valid.
    #
    # #anonymize ITSELF is idempotent (a retry just re-applies the same field
    # values and re-deletes an already-empty password_histories), so raising
    # here to force a retry of THIS endpoint is safe. Whether that retry is
    # safe end-to-end depends on the CALLER, and differs between the two:
    # AccountTerminationJob retries the whole per-user step from scratch
    # (delete_user_data has no completed/in-progress marker of its own), so a
    # retry here is safe there too. DataDeletionJob's retry is NOT
    # unconditionally safe: it re-reads the deletion_request's `status` and
    # SKIPS reprocessing a request already marked 'processing' (see
    # #execute's `unless deletion_request['status'] == 'approved'` guard) —
    # so a retry after this raises can find the request stuck in
    # 'processing' from the failed attempt and skip it rather than
    # re-attempting the anonymize call. Pre-existing, not introduced by this
    # fix, and out of scope here; tracked as offer 01a0b5c4-b71a.
    unless Security::JwtService.blacklist_user_tokens(@user.id, reason: "gdpr_anonymize")
      raise "Failed to revoke JWTs for user #{@user.id} during anonymization"
    end

    log_internal_audit("user.anonymize", "User", @user.id, account_id: @user.account_id)
    render_success(message: "User anonymized successfully")
  end

  # PATCH /api/v1/internal/users/:user_id/anonymize_audit_logs
  def anonymize_audit_logs
    count = AuditLog.where(user_id: @user.id).update_all(
      ip_address: "0.0.0.0",
      user_agent: "anonymized"
    )
    log_internal_audit("user.anonymize_audit_logs", "User", @user.id, account_id: @user.account_id, records_affected: count)
    render_success(message: "User audit logs anonymized")
  end

  # DELETE /api/v1/internal/users/:user_id/consents
  #
  # `data: { count: }` added (IMP-b33a3ecca331 review, S5): the worker reads
  # this count back (Compliance::DataDeletionJob#delete_data_type) to record
  # how many records were actually deleted — a message-only response gave it
  # nothing structured to read, so that read always saw 0.
  def delete_consents
    count = UserConsent.where(user_id: @user.id).delete_all
    log_internal_audit("user.delete_consents", "User", @user.id, account_id: @user.account_id, records_deleted: count)
    render_success(data: { count: count }, message: "Deleted #{count} consent records")
  end

  # DELETE /api/v1/internal/users/:user_id/terms_acceptances
  def delete_terms_acceptances
    count = TermsAcceptance.where(user_id: @user.id).delete_all if defined?(TermsAcceptance)
    log_internal_audit("user.delete_terms_acceptances", "User", @user.id, account_id: @user.account_id, records_deleted: count || 0)
    render_success(message: "Deleted #{count || 0} terms acceptance records")
  end

  # DELETE /api/v1/internal/users/:user_id/password_histories
  def delete_password_histories
    count = PasswordHistory.where(user_id: @user.id).delete_all if defined?(PasswordHistory)
    log_internal_audit("user.delete_password_histories", "User", @user.id, account_id: @user.account_id, records_deleted: count || 0)
    render_success(message: "Deleted #{count || 0} password history records")
  end

  # DELETE /api/v1/internal/users/:user_id/roles
  def delete_roles
    count = @user.user_roles.delete_all if @user.respond_to?(:user_roles)
    log_internal_audit("user.delete_roles", "User", @user.id, account_id: @user.account_id, records_deleted: count || 0)
    render_success(message: "Deleted #{count || 0} user role records")
  end

  private

  def set_user
    @user = User.find(params[:user_id] || params[:id])
  rescue ActiveRecord::RecordNotFound
    render_not_found("User")
  end

  # Unusable, validation-passing password for #anonymize.
  # Security::PasswordStrengthService requires every character class
  # (upper/lower/digit/special) AND rejects fixed weak patterns — 3+ repeated
  # characters, or a "123"/"abc"/"qwe"/"asd" substring. A fixed "Aa1!" prefix
  # guarantees the character classes regardless of the random suffix, but a
  # PURELY random suffix (hex or alphanumeric) still has a real per-call
  # chance of tripping the repeated-character/sequential-pattern rejection —
  # measured empirically via a flake in this method's own request spec.
  # Validating in a loop against the SAME service the model uses makes this
  # correct by construction rather than by probability.
  def unusable_random_password
    20.times do
      candidate = "Aa1!#{SecureRandom.alphanumeric(40)}"
      return candidate if Security::PasswordStrengthService.validate_password(candidate)[:valid]
    end

    # Not reachable in practice: alphanumeric draws from a 62-symbol alphabet,
    # so a rejection-worthy pattern in 40 characters is rare enough that 20
    # independent draws exhausting it all would mean something else is wrong.
    raise "Could not generate a valid anonymization password after 20 attempts"
  end
end
