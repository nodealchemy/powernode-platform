# frozen_string_literal: true

require "rails_helper"

# Campaign 01a08c9b, increment A4 — the read door's permission.
#
# `platform.status.read` is granted to admin, owner, manager AND member on
# purpose (design §6): the surfaces the status page absorbs were reachable by a
# member, and a consolidation that quietly narrows who can see the platform's
# health is a privilege regression, not a consolidation.
#
# Both arms throughout: a role that HOLDS it, and a role/user that does not.
RSpec.describe "platform.status.read permission" do
  it "is registered in the catalog by the define(namespace: \"platform\") block" do
    expect(::Permissions.permission_exists?("platform.status.read")).to be true
    expect(::Permissions.all_permissions["platform.status.read"])
      .to include("component status plane")
  end

  # The negative arm of the registration: a name the block does NOT declare is
  # still unknown, so "permission_exists? is true" above is not a check that
  # passes for everything.
  it "does not register a manage twin (nothing writes these rows through a user door)" do
    expect(::Permissions.permission_exists?("platform.status.manage")).to be false
  end

  describe "role grants" do
    %w[admin owner manager member].each do |role_name|
      it "grants it to #{role_name}" do
        expect(::Permissions.permissions_for_role(role_name)).to include("platform.status.read")
      end
    end

    # The other arm: a role the design does not name must NOT pick it up, or
    # "every role has it" would satisfy the four examples above vacuously.
    it "does not grant it to system_worker" do
      expect(::Permissions.permissions_for_role("system_worker")).not_to include("platform.status.read")
    end
  end

  describe "a real user resolved against the seeded roles" do
    let(:account) { create(:account) }

    it "member holds it; a permissionless user does not" do
      # The account's FIRST user gets owner, so create that one first and
      # assert on the SECOND — otherwise the member trait's user would be
      # passing on the owner grant it replaced.
      create(:user, account: account)
      member = create(:user, :member, account: account)

      expect(member.has_permission?("platform.status.read")).to be true
      unprivileged = create(:user, account: account, permissions: [])
      expect(unprivileged.has_permission?("platform.status.read")).to be false
    end
  end
end
