# frozen_string_literal: true

require "rails_helper"

# UserToken#has_permission? used to answer from `permissions` — a column holding
# the user's FULL permission set as it stood at mint time — before consulting the
# database. Two short-circuits read it:
#
#   * `return true if permissions&.include?("system.admin")` — a stale admin
#     snapshot answered true for ANY permission, for the token's whole lifetime.
#   * `return permissions&.include?(name) if permissions.present?` — the snapshot
#     answered VERBATIM, so it could wrongly DENY as well as wrongly allow. A
#     permission granted after the mint was invisible to the token.
#
# This is the same shape as the JWT `permissions` claim deleted in IMP-4b5fffbf5421
# (pinned by spec/controllers/concerns/jwt_permissions_claim_spec.rb), but in a
# PERSISTED store: reloading the record does not clear the snapshot, and
# UserToken#refresh! minted its successor with `permissions: permissions`, copying
# the snapshot forward, so nothing bounded the staleness — not even a token
# lifetime. LATENT, not an observed outage: `command grep` finds no caller of
# UserToken#has_permission? anywhere in server/, extensions/ (including
# extensions/private) or worker/, and none of #refresh! either. A literal-name
# grep cannot see symbol or composed dispatch, so that is strong evidence of no
# caller rather than proof. The point is that the safety of every permission
# narrowing rested on nobody happening to call the method.
#
# These examples assert through the token OBJECT rather than through a request, so
# a failure names the authorization layer rather than a controller, and none of
# them re-mint the token after changing the grant: the STALE READ is the defect, so
# an example that re-mints would pass against the broken code.
RSpec.describe "UserToken#has_permission? resolves live, not from a mint-time snapshot" do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, permissions: [ "ai.agents.read", "ai.agents.update" ]) }
  let(:role) { user.roles.first }

  # role_permissions is a join table with `id: false`, so revoke through the
  # production mutators on Role rather than destroying a row that has no PK.
  def revoke!(permission_name)
    expect(role.role_permissions.exists?(permission_name: permission_name)).to be(true)
    role.remove_permission(permission_name)
    user.reload
  end

  def grant!(permission_name)
    unless Permissions.permission_exists?(permission_name)
      Permissions.register_permissions(permission_name => "Test permission")
    end
    role.add_permission(permission_name)
    user.reload
  end

  # THE ORACLE NOTHING ELSE CATCHES. refresh! copied the snapshot into its
  # successor, so the staleness would not have been bounded by a token's lifetime
  # — it would have been bounded by nothing.
  describe "across a refresh chain" do
    it "denies a permission revoked after the successor token was minted" do
      refresh_token = UserToken.create_token_for_user(user, type: "refresh")[:user_token]
      successor = refresh_token.refresh![:user_token]

      revoke!("ai.agents.update")

      expect(successor.reload.has_permission?("ai.agents.update")).to be(false)
    end

    it "still holds a permission the user was NOT stripped of (no lockout)" do
      refresh_token = UserToken.create_token_for_user(user, type: "refresh")[:user_token]
      successor = refresh_token.refresh![:user_token]

      revoke!("ai.agents.update")

      expect(successor.reload.has_permission?("ai.agents.read")).to be(true)
    end
  end

  # Direction 1: the snapshot wrongly ALLOWS. This is the JWT defect's shape.
  describe "when a permission is revoked after the token is minted" do
    it "denies it" do
      token = UserToken.create_token_for_user(user, type: "access")[:user_token]

      revoke!("ai.agents.update")

      expect(token.reload.has_permission?("ai.agents.update")).to be(false)
    end

    it "sanity: the database agrees the user no longer holds it" do
      revoke!("ai.agents.update")

      expect(user.has_permission?("ai.agents.update")).to be(false)
    end
  end

  # Direction 2: the snapshot wrongly DENIES. The JWT claim could only over-grant;
  # this one returned the list verbatim, so it has a false-negative direction too.
  describe "when a permission is granted after the token is minted" do
    it "allows it" do
      token = UserToken.create_token_for_user(user, type: "access")[:user_token]

      grant!("ai.agents.delete")

      expect(token.reload.has_permission?("ai.agents.delete")).to be(true)
    end
  end

  # The `system.admin` arm, separately: it did not compare the requested
  # permission at all, so a stale admin snapshot was a blanket yes.
  describe "when system.admin is revoked after the token is minted" do
    let(:user) { create(:user, account: account, permissions: [ "system.admin" ]) }

    it "does not answer true for an unrelated permission" do
      token = UserToken.create_token_for_user(user, type: "access")[:user_token]

      revoke!("system.admin")

      expect(token.reload.has_permission?("ai.agents.update")).to be(false)
    end

    it "sanity: while system.admin IS held, the token answers true (no lockout)" do
      token = UserToken.create_token_for_user(user, type: "access")[:user_token]

      expect(token.reload.has_permission?("ai.agents.update")).to be(true)
    end
  end

  # The reads are what made the column dangerous, so deleting them is the fix and
  # a mutant that merely repopulates the column does not change any authorization
  # answer above. These examples pin the WRITE removal directly, so the two halves
  # cannot silently drift back in one at a time.
  describe "the permissions column is no longer written" do
    it "is not populated at mint" do
      token = UserToken.create_token_for_user(user, type: "access")[:user_token]

      expect(token.reload.permissions).to be_nil
    end

    it "is not copied into a refresh successor" do
      refresh_token = UserToken.create_token_for_user(user, type: "refresh")[:user_token]
      # Simulate a legacy row that still carries a stamp.
      refresh_token.update!(permissions: [ "ai.agents.read", "system.admin" ])

      successor = refresh_token.reload.refresh![:user_token]

      expect(successor.reload.permissions).to be_nil
    end

    it "rejects a permissions: argument rather than silently ignoring one" do
      expect { UserToken.create_token_for_user(user, type: "access", permissions: [ "ai.agents.read" ]) }
        .to raise_error(ArgumentError, /permissions/)
    end
  end

  # The column is not dropped, so rows minted before this fix — and any row a
  # future writer populates — still carry a list. It must be inert.
  #
  # These write through `update!`, NOT `update_column`. `serialize` casts on
  # assignment but `update_column` writes the cast value straight through, so a
  # pre-dumped JSON String survives and is dumped AGAIN: `reload.permissions` then
  # returns the String `'["ai.agents.read"]'` rather than an Array, and
  # `String#include?("system.admin")` substring-matches. That would make the WIDER
  # example fail against the original code for an accidental reason instead of the
  # designed one.
  describe "a legacy row that already carries a snapshot" do
    it "ignores a snapshot NARROWER than the live grant" do
      token = UserToken.create_token_for_user(user, type: "access")[:user_token]
      token.update!(permissions: [ "ai.agents.read" ])

      expect(token.reload.has_permission?("ai.agents.update")).to be(true)
    end

    it "ignores a snapshot WIDER than the live grant" do
      token = UserToken.create_token_for_user(user, type: "access")[:user_token]
      token.update!(permissions: [ "ai.agents.read", "ai.agents.update", "system.admin" ])

      revoke!("ai.agents.update")

      expect(token.reload.has_permission?("ai.agents.update")).to be(false)
    end
  end
end
