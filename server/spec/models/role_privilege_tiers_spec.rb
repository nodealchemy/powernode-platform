# frozen_string_literal: true

require "rails_helper"

# IMP-4bd5ac8ca3ad — CHARACTERIZATION SPEC, not an endorsement.
#
# `system_worker` is granted `*SYSTEM_PERMISSIONS.keys` (config/permissions.rb
# ~:932), and SYSTEM_PERMISSIONS includes "system.admin" (:509), whose own
# description is "grants all permissions". User#has_permission? short-circuits
# on system.admin (user.rb:138-141) BEFORE consulting the requested name, so
# system_worker is effectively GRANT-ALL: every "worker-only" permission is
# exactly as strong as system.admin, never narrower.
#
# Two prose sites that reason from worker-only grants were audited and are
# accurate today (system_fleet_tool.rb's WORKER_ONLY_ACTIONS comment and
# engine.rb's "Deliberately EXCLUDED" note both spell out the short-circuit),
# so nothing is misleading in the tree. What remains is an OPEN DESIGN
# QUESTION the operator owns: should the worker tier be narrower than admin?
#
# This file pins the measured status quo so the collapse is a recorded fact
# rather than a surprise rediscovered by the next permission audit. If the
# role is deliberately narrowed, THIS SPEC GOING RED IS THE INTENDED SIGNAL —
# update it as part of that change rather than treating it as a regression.
# Real Role records throughout: a synthetic `permissions:` grant cannot
# observe this class of fact at all, which is why it stayed hidden.
RSpec.describe "role privilege tiers", type: :model do
  let(:account) { create(:account) }

  def user_with_role(role_name)
    user = create(:user, account: account)
    user.roles = []
    user.add_role(role_name)
    user
  end

  describe "system_worker" do
    subject(:worker) { user_with_role("system_worker") }

    it "holds system.admin, collapsing the worker tier into the admin tier" do
      expect(worker.has_permission?("system.admin")).to be true
    end

    it "therefore answers true for a permission name that does not exist" do
      expect(worker.has_permission?("totally.made.up.permission")).to be true
    end

    it "reaches the permissions the grant list deliberately excludes" do
      %w[system.platforms.publish_disk_image system.module_builds.dispatch].each do |name|
        expect(worker.has_permission?(name)).to be(true),
          "#{name} is excluded from system_worker's explicit grants but reachable via the short-circuit"
      end
    end
  end

  describe "roles WITHOUT the short-circuit" do
    # The counterweight: the collapse is specific to system_worker (and
    # super_admin, which holds system.admin by design). If a future change
    # granted system.admin more widely, these go red.
    %w[admin owner manager].each do |role_name|
      it "#{role_name} does not hold system.admin" do
        expect(user_with_role(role_name).has_permission?("system.admin")).to be false
      end

      it "#{role_name} cannot reach an invented permission" do
        expect(user_with_role(role_name).has_permission?("totally.made.up.permission")).to be false
      end
    end
  end
end
