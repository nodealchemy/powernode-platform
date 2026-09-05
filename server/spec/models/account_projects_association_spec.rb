# frozen_string_literal: true

require "rails_helper"

# APO increment `app-6` — Account gains its projects association.
#
# Every other Ai:: model on Account has one, so its absence read as an
# oversight rather than a boundary; callers were reaching past it with an
# explicit `Ai::Project.where(account_id:)`, which is the shape that lets a
# cross-tenant read slip in when someone forgets the scope.
RSpec.describe "Account#ai_projects" do
  let(:account) { create(:account) }

  it "reaches only this account's projects" do
    mine = create(:ai_project, account: account, name: "Mine")
    create(:ai_project, account: create(:account), name: "Theirs")

    expect(account.ai_projects).to contain_exactly(mine)
  end

  # STRUCTURAL, and the weaker assertion on purpose — `account.destroy!` is not
  # available as an oracle here, for two reasons that both predate this
  # association and neither of which involves projects:
  #
  #   * an account carrying System::NodePlatform rows is refused outright
  #     ("Cannot delete record because dependent system node platforms exist"),
  #     which is `restrict_with_error` behaving as designed, and the account
  #     factory produces such an account;
  #   * past that, a mission carrying a `created_by` raises
  #     PG::ForeignKeyViolation on ai_missions.created_by_id, because users are
  #     destroyed before missions. Reproduced with no project in the picture.
  #
  # Asserting the declared option is therefore what is honestly available.
  # Routing a project guarantee through that cascade would make it pass or fail
  # for reasons that have nothing to do with projects.
  it "declares dependent: :destroy so projects do not outlive their account" do
    reflection = Account.reflect_on_association(:ai_projects)

    expect(reflection).to be_present
    expect(reflection.macro).to eq(:has_many)
    expect(reflection.options[:dependent]).to eq(:destroy)
    expect(reflection.options[:class_name]).to eq("Ai::Project")
  end

  # The behavioural half that IS reachable, and the one that matters more: the
  # project association must not delete missions out from under the account
  # cascade.
  it "does not delete a project's missions when the PROJECT is destroyed — it nullifies them" do
    user = create(:user, account: account)
    project = create(:ai_project, account: account)
    mission = create(:ai_mission, account: account, mission_type: "infrastructure",
                                  created_by: user, project: project)

    project.destroy!

    expect(Ai::Mission.find_by(id: mission.id)).to be_present
    expect(mission.reload.ai_project_id).to be_nil
  end

  it "is the scope the read surface uses — no caller re-derives it" do
    # `command grep`, not the shell function, so extensions/private is in scope
    # for the absence claim.
    root = Rails.root.join("app")
    offenders = Dir.glob(root.join("**", "*.rb")).select do |path|
      File.read(path).match?(/Ai::Project\.where\(\s*account_id:/)
    end

    expect(offenders).to be_empty,
      "these re-derive the account scope instead of using account.ai_projects: #{offenders.join(', ')}"
  end
end
