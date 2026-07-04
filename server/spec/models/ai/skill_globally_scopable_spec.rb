# frozen_string_literal: true

require "rails_helper"

# Override-aware skill resolution (the clone-on-evolve gap): a GLOBAL
# (platform-provided) skill and an account's own clone/override of it can
# share a slug (partial unique indexes partition uniqueness by account_id —
# see db/schema.rb ai_skills). resolve_for must prefer the account's row over
# the global baseline. Mirrors agent_globally_scopable_spec.rb +
# agent_slug_scope_spec.rb for Ai::Agent.
RSpec.describe "Ai::Skill global/account scoping" do
  let(:account) { create(:account) }
  let(:other_account) { create(:account) }

  def global_skill(name:, slug: nil)
    create(:ai_skill, :global, name: name, slug: slug, category: "productivity", status: "active")
  end

  describe "a global skill" do
    it "persists with a nil account_id and reports global?" do
      skill = global_skill(name: "Code Review", slug: "code-review")
      expect(skill).to be_persisted
      expect(skill.account_id).to be_nil
      expect(skill.global?).to be true
    end

    it "is visible to every account via for_account, alongside the account's own" do
      g = global_skill(name: "Code Review", slug: "code-review")
      mine = create(:ai_skill, account: account, name: "My Skill", slug: "my-skill")

      visible = Ai::Skill.for_account(account.id)
      expect(visible).to include(g, mine)
      # other account sees the global but not my account's own
      expect(Ai::Skill.for_account(other_account.id)).to include(g)
      expect(Ai::Skill.for_account(other_account.id)).not_to include(mine)
    end
  end

  describe ".resolve_for (override-aware)" do
    it "returns the GLOBAL baseline when the account has no override" do
      g = global_skill(name: "Code Review", slug: "code-review")
      resolved = Ai::Skill.resolve_for(account.id, slug: "code-review")
      expect(resolved).to eq(g)
    end

    it "returns the ACCOUNT's own override/clone in preference to the global baseline" do
      global_skill(name: "Code Review", slug: "code-review")
      override = create(:ai_skill, account: account, name: "Code Review (Custom)", slug: "code-review",
                                   category: "productivity", status: "active")

      resolved = Ai::Skill.resolve_for(account.id, slug: "code-review")
      expect(resolved).to eq(override)
    end

    it "still resolves the GLOBAL baseline for a different account" do
      g = global_skill(name: "Code Review", slug: "code-review")
      create(:ai_skill, account: account, name: "Code Review (Custom)", slug: "code-review",
                        category: "productivity", status: "active")

      expect(Ai::Skill.resolve_for(other_account.id, slug: "code-review")).to eq(g)
    end

    it "resolves by name as well as slug" do
      global_skill(name: "Code Review", slug: "code-review")
      override = create(:ai_skill, account: account, name: "Code Review", slug: "code-review",
                                   category: "productivity", status: "active")

      expect(Ai::Skill.resolve_for(account.id, name: "Code Review")).to eq(override)
    end
  end

  describe "#generate_slug (scope-partitioned dedupe)" do
    it "lets an ACCOUNT skill reuse the slug of the GLOBAL skill it overrides" do
      g = global_skill(name: "Override Skill")
      a = create(:ai_skill, account: account, slug: nil, name: "Override Skill",
                            category: "productivity", status: "active")

      expect(g.account_id).to be_nil
      expect(g.slug).to eq("override-skill")
      expect(a.account_id).to eq(account.id)
      expect(a.slug).to eq("override-skill") # same slug, different scope — the override case
      expect(a).to be_persisted
    end

    it "dedupes slug-colliding GLOBAL skills within the global scope" do
      first  = global_skill(name: "Dup Skill")
      second = global_skill(name: "Dup Skill!")

      expect(first.slug).to eq("dup-skill")
      expect(second.slug).to eq("dup-skill-1")
    end

    it "dedupes slug-colliding skills within one account" do
      first  = create(:ai_skill, account: account, slug: nil, name: "Acct Skill",
                                 category: "productivity", status: "active")
      second = create(:ai_skill, account: account, slug: nil, name: "Acct Skill!",
                                 category: "productivity", status: "active")

      expect(first.slug).to eq("acct-skill")
      expect(second.slug).to eq("acct-skill-1")
    end

    it "lets two different accounts each hold the same slug" do
      a = create(:ai_skill, account: account, slug: nil, name: "Cross Acct",
                            category: "productivity", status: "active")
      b = create(:ai_skill, account: other_account, slug: nil, name: "Cross Acct",
                            category: "productivity", status: "active")

      expect(a.slug).to eq("cross-acct")
      expect(b.slug).to eq("cross-acct")
      expect(b).to be_persisted
    end
  end

  describe "#clone_to_account + #update_from_source (the override mechanism, smoke)" do
    it "clones a global skill into an account as an editable copy with provenance" do
      g = global_skill(name: "Code Review", slug: "code-review")
      clone = g.clone_to_account(account)

      expect(clone.account_id).to eq(account.id)
      expect(clone.cloned_from_id).to eq(g.id)
      expect(clone.global?).to be false
      expect(clone.clone?).to be true
      expect(clone.slug).not_to eq(g.slug) # clone_to_account suffixes for global-slug safety

      # resolve_for still prefers the clone once it carries the account's own slug
      clone.update!(slug: g.slug)
      expect(Ai::Skill.resolve_for(account.id, slug: g.slug)).to eq(clone)
    end

    it "pulls non-conflicting origin changes via update_from_source" do
      g = global_skill(name: "Code Review", slug: "code-review")
      g.update!(description: "Original description")
      clone = g.clone_to_account(account)

      g.update!(description: "Updated by platform")
      result = clone.update_from_source

      expect(result[:synced]).to be true
      expect(clone.reload.description).to eq("Updated by platform")
    end
  end
end
