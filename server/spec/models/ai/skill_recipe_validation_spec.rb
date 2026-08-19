# frozen_string_literal: true

require "rails_helper"

# Blocker 3 of the recipe-dispatch readiness review — recipe metadata had NO
# validation on write. Ai::Skill#recipe returns metadata["recipe"] verbatim, so
# a malformed recipe was accepted at write time and failed at RUNTIME, mid-run,
# after earlier steps had already had effects. That is the worst place to
# discover a typo: SkillRecipeRunner has no compensation for a partially
# executed run.
#
# Validates STRUCTURE only, deliberately not tool existence. Structure is
# invariant; which tools are registered is deployment-dependent (a core-mode
# install carries no extension tools), so rejecting an unknown tool at write
# time would refuse a recipe that is valid on the install it was authored for.
# The runner already reports "Unknown tool" clearly at dispatch.
RSpec.describe Ai::Skill, "recipe validation" do
  let(:account) { create(:account) }

  def skill_with(recipe)
    build(:ai_skill, account: account, metadata: { "recipe" => recipe })
  end

  def valid_recipe
    { "version" => "1", "inputs" => [],
      "steps" => [ { "id" => "s1", "tool" => "memory_stats", "params" => {} } ],
      "output" => {} }
  end

  it "accepts a well-formed recipe" do
    expect(skill_with(valid_recipe)).to be_valid
  end

  it "rejects a recipe whose steps are not an array" do
    skill = skill_with(valid_recipe.merge("steps" => { "id" => "s1" }))

    expect(skill).not_to be_valid
    expect(skill.errors[:metadata].join).to match(/steps/i)
  end

  it "rejects a recipe with no steps" do
    skill = skill_with(valid_recipe.merge("steps" => []))

    expect(skill).not_to be_valid
    expect(skill.errors[:metadata].join).to match(/steps/i)
  end

  it "rejects a step missing its tool name" do
    skill = skill_with(valid_recipe.merge("steps" => [ { "id" => "s1" } ]))

    expect(skill).not_to be_valid
    expect(skill.errors[:metadata].join).to match(/tool/i)
  end

  # The runner keys captures and resume-position on step["id"]
  # (remaining_steps_for rejects completed ids), so an id-less step silently
  # breaks resume rather than failing loudly.
  it "rejects a step missing its id" do
    skill = skill_with(valid_recipe.merge("steps" => [ { "tool" => "memory_stats" } ]))

    expect(skill).not_to be_valid
    expect(skill.errors[:metadata].join).to match(/id/i)
  end

  it "rejects more steps than the runner will execute" do
    too_many = Array.new(Ai::SkillRecipeRunner::MAX_STEPS + 1) do |i|
      { "id" => "s#{i}", "tool" => "memory_stats" }
    end
    skill = skill_with(valid_recipe.merge("steps" => too_many))

    expect(skill).not_to be_valid
    expect(skill.errors[:metadata].join).to match(/#{Ai::SkillRecipeRunner::MAX_STEPS}/)
  end

  # CONTROL: a non-recipe skill must be unaffected. Most skills carry no
  # recipe key at all and must not acquire a new way to fail validation.
  it "leaves a skill with no recipe alone" do
    expect(build(:ai_skill, account: account, metadata: { "other" => "data" })).to be_valid
  end

  # CONTROL: the runner rejects unknown tools at dispatch; validation must not
  # duplicate that, or a core-mode install cannot store an extension recipe.
  it "accepts a recipe naming a tool this install does not register" do
    skill = skill_with(valid_recipe.merge(
      "steps" => [ { "id" => "s1", "tool" => "some_tool_from_an_unloaded_extension" } ]
    ))

    expect(skill).to be_valid
  end
end
