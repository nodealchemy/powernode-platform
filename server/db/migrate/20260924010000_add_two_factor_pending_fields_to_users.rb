# frozen_string_literal: true

# IMP-99e8e4701150 — splits 2FA enrolment into PENDING vs CONFIRMED.
#
# `users.two_factor_secret` used to double as both "a secret was generated"
# and "2FA is active" (User#two_factor_enabled? read `two_factor_secret.present?`
# rather than the `two_factor_enabled` column that already existed alongside
# it) — so POST /two_factor/enable flipped a user into 2FA-enforced on login
# before they had proven they could actually generate a valid TOTP code,
# and it returned that account's backup codes in the SAME response. A client
# that never completed setup (dropped connection, closed the tab before
# scanning the QR code) was locked out at its next login with no working
# authenticator and backup codes it may never have seen.
#
# These two columns hold the secret from #start_two_factor_setup! until
# #confirm_two_factor_setup! proves the user's authenticator app has it (or
# the pending window lapses and a re-enable replaces it). `two_factor_secret`
# is written only on confirmation, from that point on meaning what its name
# says: the ACTIVE, confirmed secret.
class AddTwoFactorPendingFieldsToUsers < ActiveRecord::Migration[8.1]
  def change
    # Same treatment as the existing two_factor_secret column: `encrypts` is
    # declared on the model (User), not here — this migration only owns the
    # column shape.
    add_column :users, :two_factor_pending_secret, :string
    add_column :users, :two_factor_pending_expires_at, :datetime
  end
end
