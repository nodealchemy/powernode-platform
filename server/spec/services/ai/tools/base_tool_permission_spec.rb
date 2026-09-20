# frozen_string_literal: true

require "rails_helper"

# BaseTool.permitted? resolves permissions via User#has_permission?
# (user.rb:181-187 — a roles.joins(:role_permissions).exists? check, the
# same resolution every other permission check in the app uses), so a
# permission granted through a CODE-DEFINED role (e.g. ai.campaigns.*,
# seeded via Role.sync_from_config!) is visible to an agent's authorization
# check exactly the way it is to a user's.
#
# Review correction (IMP-82db8ba318aa): the previous version of this
# comment described has_permission? as "the canonical resolution" as
# opposed to "a raw RolePermission query [that] only sees DB grants" — but
# has_permission? IS that join query; there is no separate, more-canonical
# mechanism it uses instead. Left in only the behavioral claim (code-defined
# role grants ARE visible this way, which the first example below still
# demonstrates) and dropped the inaccurate mechanism distinction.
#
# IMP-82db8ba318aa: this file used to assert an ANY-ACCOUNT-USER union as the intended
# behavior — "grants the tool when an account user holds the required permission" passed
# whether or not that user was the agent's own creator. That was the bug: an agent's
# authority was effectively the union of every account user's roles. The gate now asks
# "is THIS agent's CREATOR authorized", not "is anyone in the account authorized" — the
# examples below assert the new semantics with the same coverage intent, plus the
# differentiator that is the finding itself (creator lacks it, someone else in the
# account holds it).
RSpec.describe Ai::Tools::BaseTool, ".permitted?" do
  it "grants the tool when the agent's CREATOR holds the required permission" do
    account = create(:account)
    creator = create(:user, account: account, permissions: ["ai.campaigns.manage"])
    agent = create(:ai_agent, account: account, creator: creator)

    expect(Ai::Tools::CampaignTool.permitted?(agent: agent)).to be true
  end

  it "denies the tool when nobody in the account holds the required permission" do
    account = create(:account)
    creator = create(:user, account: account, permissions: ["ai.goals.read"])
    agent = create(:ai_agent, account: account, creator: creator)

    expect(Ai::Tools::CampaignTool.permitted?(agent: agent)).to be false
  end

  # IMP-82db8ba318aa: the finding, stated as a test. Under the OLD union check
  # this passed (any account user's permission sufficed); the creator check
  # must deny it, since the specific creator does not hold the permission.
  it "denies the tool when the agent's creator lacks the permission, even though another account user holds it" do
    account = create(:account)
    creator = create(:user, account: account, permissions: ["ai.goals.read"])
    create(:user, account: account, permissions: ["ai.campaigns.manage"]) # a DIFFERENT user, same account
    agent = create(:ai_agent, account: account, creator: creator)

    expect(Ai::Tools::CampaignTool.permitted?(agent: agent)).to be false
  end

  it "is permissive with no agent" do
    expect(Ai::Tools::CampaignTool.permitted?(agent: nil)).to be true
  end
end
