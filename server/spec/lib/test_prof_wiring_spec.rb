# frozen_string_literal: true

require "rails_helper"

# Pins the TestProf wiring (spec/support/test_prof.rb): `let_it_be` / `before_all` must exist
# in every example group, and the data they create must be rolled back when the group ends
# so it can never leak past it. Every example is self-contained (runnable alone, by line
# number, or under --only-failures / --bisect).
RSpec.describe "TestProf wiring" do
  marker_name = "test_prof_wiring_marker"
  names = [ marker_name, "#{marker_name}_b" ]
  created = {}

  # Runs after the nested groups' own after(:all) rollbacks: nothing may survive them.
  after(:all) do
    leaked = Role.where(name: names).pluck(:name)
    expect(leaked).to be_empty, "let_it_be / before_all data leaked past its group: #{leaked.inspect}"
  end

  describe "let_it_be" do
    let_it_be(:marker) do
      Role.create!(name: marker_name, display_name: "TestProf marker", role_type: "user", immutable: false)
        .tap { |role| created[:marker_id] = role.id }
    end

    it "is available in an example group and persisted" do
      expect(marker).to be_persisted
      expect(Role.where(name: marker_name).count).to eq(1)
    end

    it "is created once for the group, not once per example" do
      expect(marker.id).to eq(created[:marker_id])
      expect(Role.where(name: marker_name).count).to eq(1)
    end
  end

  describe "before_all" do
    before_all do
      Role.create!(name: "#{marker_name}_b", display_name: "TestProf b", role_type: "user", immutable: false)
    end

    it "runs before the examples and its data is visible to them" do
      expect(Role.where(name: "#{marker_name}_b").count).to eq(1)
    end
  end
end
