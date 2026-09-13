# frozen_string_literal: true

require "rails_helper"

# IMP-01a04fd8-3d32. Role conferral is a SUBSET test: Role#assignable_by?
# passes only if the assigner holds every permission the role grants. So the
# grant catalog is not just a list of capabilities — its containment structure
# decides who can invite whom, and a single grant that names `manager` without
# naming `owner` silently removes an owner's ability to confer that role.
#
# That is exactly what had happened. The system extension's catalog names
# admin / manager / member and never `owner`, so `manager` held 13 permissions
# `owner` did not and `member` held 3 — and a user holding nothing but the
# global `owner` role could not invite a member, the one conferral the product
# actually ships a form for.
#
# THE LATTICE, as measured rather than assumed:
#
#     owner  ⊇  manager  ⊇  member
#                       ⊇  developer
#
# `member` and `developer` are INCOMPARABLE and deliberately so — developer
# holds api.manage_keys, the kb.* writes and the webhook.* verbs that member
# does not, and member holds 48 that developer does not. Any chain that orders
# those two against each other is wrong, so this pins the two real chains
# instead of one invented four-link one.
#
# Asserted against the CATALOG (Permissions.permissions_for_role), not against
# seeded rows: the catalog is where an extension registers, where the defect
# was introduced, and it is what Role.sync_from_config! derives the rows from.
# A catalog-level failure therefore precedes any seed run.
RSpec.describe "Role grant containment", type: :model do
  def grants(role_name)
    Permissions.permissions_for_role(role_name).to_set
  end

  # Every pair that must nest, and why. A role absent from the catalog (an
  # extension that declares its own) simply never reaches these.
  {
    %w[owner manager] => "an owner must be able to confer manager",
    %w[owner member] => "an owner must be able to confer member",
    %w[owner developer] => "an owner must be able to confer developer",
    %w[manager member] => "a manager must be able to confer member",
    %w[manager developer] => "a manager must be able to confer developer"
  }.each do |(superset, subset), why|
    it "#{superset} ⊇ #{subset} — #{why}" do
      missing = (grants(subset) - grants(superset)).to_a.sort

      expect(missing).to be_empty,
                         "#{subset} holds #{missing.size} permission(s) #{superset} does not, so " \
                         "Role#assignable_by? refuses the conferral:\n  #{missing.join("\n  ")}\n" \
                         "Grant these to #{superset} in whichever catalog declares them."
    end
  end

  # The consequence, not just the data — a change to the conferral RULE that
  # reintroduced an exemption would leave the sets above untouched.
  it "lets a plain owner confer member and manager" do
    account = create(:account)
    owner_user = create(:user, account: account)
    owner_user.roles.destroy_all
    owner_user.assign_role(Role.find_by(name: "owner", account_id: nil))
    owner_user.reload

    %w[member manager].each do |role_name|
      role = Role.find_by(name: role_name, account_id: nil)
      expect(role).to be_present, "the global #{role_name} role is not seeded"
      expect(role.assignable_by?(owner_user)).to be(true),
                                                 "owner cannot confer #{role_name}; missing " \
                                                 "#{(role.role_permissions.pluck(:permission_name) - owner_user.permission_names).sort.inspect}"
    end
  end

  # Non-vacuity for the pairs above: member and developer are INCOMPARABLE, so
  # a spec that accidentally computed empty sets on both sides would pass every
  # example above while proving nothing. This one fails if the catalog ever
  # collapses to something trivially nested.
  it "keeps member and developer incomparable, so the pairs above are not vacuous" do
    expect((grants("developer") - grants("member"))).not_to be_empty
    expect((grants("member") - grants("developer"))).not_to be_empty
  end
end
