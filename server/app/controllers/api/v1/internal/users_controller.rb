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

      # IMP-df4aa2b46dbc finding 1 — API keys created by this user carry no
      # coupling to the user's own status: ApiKey#active? is `is_active &&
      # !expired?`, and the only consumer (Api::V1::A2aController
      # #authenticate_api_key) authenticates on `active?` alone, so a key
      # this user created kept working indefinitely after erasure. Scoped to
      # created_by_id — not account-wide, and does not need an explicit
      # account_id filter to stay that way: a user can only ever be
      # created_by on keys in their own account, so this cannot reach
      # another user's key by construction (review correction,
      # IMP-df4aa2b46dbc non-blocking 6: the ORIGINAL comment here called
      # this "account-scoped", which named the wrong mechanism — there is no
      # account_id anywhere in the WHERE clause).
      #
      # `update_all`, not a find_each/update! loop (review correction,
      # IMP-df4aa2b46dbc non-blocking 4): `update!` runs ApiKey's full
      # validation set, including an expires_at comparison validation, on
      # rows this code does not own — one legacy row failing validation
      # raises RecordInvalid and rolls back the WHOLE anonymize transaction,
      # permanently failing that user's erasure on every retry. ApiKey's
      # only update callback (log_status_change) is a Rails.logger.info
      # line — losing it under update_all is not load-bearing.
      #
      # ALL keys created by this user, not only the currently-active ones
      # (review correction, IMP-df4aa2b46dbc blocker 2): last_used_ip is the
      # SAME PII class already scrubbed on user_tokens/mcp_sessions below,
      # and an already-deactivated key kept it under the old is_active:true
      # filter. `allowed_ips` is deliberately RETAINED as configuration
      # history — a deliberate retention decision, reviewed and accepted,
      # NOT a claim that it carries no PII (review round 3 wording
      # correction: for a personal key this range is frequently the user's
      # own home or office network, so this is a real retention trade-off,
      # not an exploitability argument).
      ApiKey.where(created_by_id: @user.id).update_all(is_active: false, last_used_ip: nil)

      # IMP-df4aa2b46dbc finding 4 — none of these tables are touched by
      # anonymize-in-place today. User declares `dependent: :destroy` for
      # each of them, but that only fires on an actual `user.destroy!`,
      # which this design never calls (anonymize-in-place, see the class
      # doc above) — so the PII on these rows survived every erasure path
      # unless removed here explicitly.
      #
      # None of UserToken, McpSession, ImpersonationSession, ApiKey, or
      # Notification includes Auditable (review correction, IMP-df4aa2b46dbc
      # non-blocking 7) — these scrubbing writes cannot copy PII into
      # audit_logs the way @user.update! above could without the
      # audit_extra_redactions guard set at the top of this method. Adding
      # `include Auditable` to any of them later would need that SAME
      # guard; do not do it silently.
      #
      # `update_all`, not `update!` (review correction, IMP-df4aa2b46dbc
      # non-blocking 4): UserToken validates token_digest/token_type/
      # expires_at presence on every save, and a legacy row with a null
      # expires_at would raise RecordInvalid mid-transaction, permanently
      # failing this user's erasure on retry. UserToken's only callbacks
      # (set_default_expiration, cleanup_expired_tokens) are create-only, so
      # nothing meaningful is skipped.
      #
      # `revoked` is a NULLABLE boolean (schema: default false, no
      # `null: false`) — review round 3 correction: `where(revoked: false)`
      # / `where(revoked: true)` BOTH exclude a NULL row in SQL, so the
      # original two-call split here matched neither call and left such a
      # row's PII forever. Not a live-credential hole (UserToken.active,
      # the scope find_by_token/authenticate go through, also excludes NULL
      # via `where(revoked: false)`), but it is permanent PII retention, and
      # `cleanup_expired` filters on `revoked = true` too, so the row is
      # never reaped either. `revoked: [false, nil]` catches both; the
      # second call below drops the revoked filter entirely so it always
      # scrubs PII regardless of the column's value, including on a row the
      # first call already touched (harmless re-write) and on an
      # already-true row it does not.
      UserToken.where(user_id: @user.id, revoked: [ false, nil ]).update_all(
        revoked: true,
        revoked_at: Time.current,
        revoked_reason: "gdpr_anonymize",
        last_used_ip: nil,
        user_agent: nil,
        name: nil # user-supplied token label (review correction, non-blocking 1)
      )
      UserToken.where(user_id: @user.id).update_all(
        last_used_ip: nil,
        user_agent: nil,
        name: nil
      )

      # `update_all`, not `update!` (review round 3 correction — this
      # reverses round 2's own comment here, which claimed
      # `after_update :deactivate_agent_on_end` "deactivates the linked AI
      # client agent". Traced now: Ai::McpClientIdentityService
      # .deactivate_agent (mcp_client_identity_service.rb:41-51) is, in its
      # OWN doc comment, "intentionally a no-op beyond logging — the agent
      # stays active with its workspace team memberships, conversation/
      # message FKs, and sequence number intact." It is the SAME class of
      # effect as ApiKey#log_status_change, which this diff already
      # correctly dismissed as not load-bearing on the table above. It is
      # weaker still on this exact path: the callback early-returns on
      # `revoked? && reactivatable?` (mcp_session.rb:174), and a
      # freshly-revoked, unexpired session IS reactivatable, so a session
      # revoked for the FIRST time here returns before the log line; an
      # ALREADY-revoked session never fires the callback at all
      # (`saved_change_to_status?` is false). So `update!` bought nothing but
      # one conditional log line.
      #
      # Unlike UserToken's genuinely-reachable nullable expires_at (below),
      # attempting to red-first "a legacy row makes update! raise here"
      # found no reachable case for THIS table (verified by trying, not
      # assumed): session_token's presence/uniqueness are backed by DB-level
      # NOT NULL + a unique index, which make the REALISTIC violations
      # unreachable (review round 3b trim: NOT NULL does not enforce
      # `validates :presence` — a raw-SQL empty string satisfies the column
      # and still fails the model — so this is not a strict impossibility
      # claim, just an unreachable-in-practice one; moot for behavior either
      # way, since update_all skips validations regardless of which kind of
      # row it meets). `status` is always overwritten to a valid value by
      # this very write, so a corrupted pre-existing value gets fixed, not
      # tripped over. `must_have_a_principal` cannot fire because the
      # `user_id: @user.id` scope this query runs under already guarantees
      # the one condition it checks. `update_all` is used here for
      # CONSISTENCY with the two tables above (same shape, same reasoning
      # family) and because it is simply unnecessary overhead to run
      # McpSession's full validation set on a write that cannot fail it —
      # not because a reachable erasure-breaking bug was found and fixed.
      #
      # Split into two calls, same shape as UserToken above, to preserve an
      # existing revoked_at rather than clobber it: a row not already
      # "revoked" gets a fresh timestamp; an already-revoked row keeps its
      # original one and only has its PII scrubbed.
      #
      # Second call carries NO status filter (review round 3b correction) —
      # same reasoning as UserToken's second call above: with the filter,
      # this table would only be correct BY SEQUENCE (call 1 must run first
      # and normalize every row to "revoked" for call 2 to reach them all),
      # not by construction. That is the exact property the UserToken fix
      # removed when its own revoked filter was dropped from the PII-scrub
      # call. The call writes only nils/{}, so dropping the filter costs
      # nothing and makes both tables read identically, correct regardless
      # of whether a future edit changes call 1's predicate.
      #
      # client_info/metadata (jsonb) scrubbed to {} (review correction,
      # IMP-df4aa2b46dbc non-blocking 2, deliberate yes): both can carry
      # client hostnames and device identifiers, the same class of PII as
      # ip_address/user_agent/display_name on this same row.
      McpSession.where(user_id: @user.id).where.not(status: "revoked").update_all(
        status: "revoked",
        revoked_at: Time.current,
        ip_address: nil,
        user_agent: nil,
        display_name: nil,
        client_info: {},
        metadata: {}
      )
      McpSession.where(user_id: @user.id).update_all(
        ip_address: nil,
        user_agent: nil,
        display_name: nil,
        client_info: {},
        metadata: {}
      )

      # Only the rows where THIS user is the IMPERSONATOR carry their own
      # ip_address/user_agent. On a row where they are the TARGET, those
      # columns describe the OTHER party's session — not this user's PII —
      # so they are left untouched (team review, IMP-df4aa2b46dbc).
      #
      # `reason` deliberately left untouched on BOTH row types (team
      # decision, IMP-df4aa2b46dbc review): it is operator-authored free
      # text that can name the erased user on a row where they are the
      # TARGET, and is text THEY wrote on a row where they are the
      # IMPERSONATOR. Considered and deferred as a policy call (same bucket
      # as the sole-owner question, finding 5) rather than folded into this
      # task as a free-text redaction policy.
      @user.impersonation_sessions_as_impersonator.update_all(ip_address: nil, user_agent: nil)

      @user.notifications.delete_all
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
    begin
      unless Security::JwtService.blacklist_user_tokens(@user.id, reason: "gdpr_anonymize")
        raise "Failed to revoke JWTs for user #{@user.id} during anonymization"
      end
    ensure
      # IMP-df4aa2b46dbc finding 3 (blocker 1 fix, review round 2) — this
      # MUST run even when the JWT revocation above raises. Before this fix
      # the disconnect sat AFTER the raise: on any blacklist_user_tokens
      # failure (e.g. a Redis blip), the anonymization/key-deactivation/PII
      # scrub above had ALREADY COMMITTED (the transaction closes above,
      # before this method ever reaches this line), JWTs were NOT revoked,
      # and the disconnect never ran — leaving the erased user's live
      # ActionCable socket open indefinitely, which is the entire premise
      # finding 3 exists to close (authenticate_user only runs once, at
      # handshake). The request 500s and reports failure while the erasure
      # has actually applied — and DataDeletionJob's retry is not
      # unconditionally safe here (see the comment on the raise above), so
      # the retry that would eventually reach this line may never come.
      #
      # Kept OUTSIDE the @user.transaction block above (unchanged): a
      # broadcast from inside that transaction would announce a state that
      # can still roll back.
      #
      # `current_worker: nil` is REQUIRED here, not optional decoration:
      # ApplicationCable::Connection declares `identified_by :current_user`
      # AND `identified_by :current_worker`, and RemoteConnection#valid_identifiers?
      # requires every declared identifier's key present in `where(...)`, not
      # just the one being searched on — `where(current_user: @user)` alone
      # raises ActionCable::RemoteConnections::RemoteConnection
      # ::InvalidIdentifiersError (verified via `rails runner`, not assumed).
      # This does not broaden the match: connection_identifier is built via
      # `identifiers.filter_map { ... }`, which drops nil values, so a real
      # user-only connection (whose own @current_worker is also nil) computes
      # the identical identifier either way.
      #
      # Decision (non-blocking item 5, IMP-df4aa2b46dbc review): a failure
      # from THIS call is allowed to propagate, same as blacklist_user_tokens
      # above — both are "close a live access surface" failures of the same
      # severity class, and `disconnect`'s broadcast has no success/failure
      # signal of its own beyond raising, unlike blacklist_user_tokens'
      # explicit boolean.
      #
      # Review round 3 correction: if both this and the JWT revocation fail
      # in the SAME request, Ruby's `ensure` semantics mean THIS exception
      # would otherwise replace the JWT one in what propagates — losing
      # "Failed to revoke JWTs", the one fact the operator most needs (the
      # erasure committed but tokens are still live). Both exceptions being
      # Redis-shaped does not make them interchangeable. Logged explicitly
      # here, before attempting the disconnect, so the JWT failure is on
      # record even if the disconnect's own exception is what propagates.
      #
      # `$!` scope (review round 3b addition): nil on the success path, and
      # inside THIS ensure it holds the in-flight exception from the begin
      # block directly above — but `$!` is a thread-global that reflects
      # whichever rescue/ensure frame is CURRENTLY unwinding, so code
      # running inside an ENCLOSING, still-active rescue frame could see
      # that outer frame's exception instead of this method's own. Rails'
      # normal action-dispatch path does not put this method inside such a
      # frame, so that case does not arise here; the worst case if it ever
      # did is one spuriously-attributed error log line, not a behavior
      # change — but the boundary is worth stating rather than leaving the
      # next reader to re-derive it.
      Rails.logger.error("[Api::V1::Internal::UsersController#anonymize] JWT revocation failed for user #{@user.id}: #{$!.message}") if $!
      ActionCable.server.remote_connections.where(current_user: @user, current_worker: nil).disconnect
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
