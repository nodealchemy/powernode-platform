# frozen_string_literal: true

require "rails_helper"

# D2 review F1 — the model backstop for the missions door: whatever path writes
# a mission (controller, worker callback, console, a future service), its
# repository must belong to the mission's own account.
RSpec.describe Ai::Mission, "repository tenancy", type: :model do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }

  it "is invalid when the repository belongs to another account" do
    mission = build(:ai_mission, account: account, created_by: user,
                                 repository: create(:git_repository, account: create(:account)))

    expect(mission).not_to be_valid
    expect(mission.errors[:repository]).to include("not found")
  end

  it "is valid with a repository of its own account" do
    mission = build(:ai_mission, account: account, created_by: user,
                                 repository: create(:git_repository, account: account))

    expect(mission).to be_valid
  end

  it "re-checks the rule when an existing mission is re-pointed" do
    mission = create(:ai_mission, account: account, created_by: user,
                                  repository: create(:git_repository, account: account))

    mission.repository = create(:git_repository, account: create(:account))

    expect(mission).not_to be_valid
    expect(mission.errors[:repository]).to include("not found")
  end
end
