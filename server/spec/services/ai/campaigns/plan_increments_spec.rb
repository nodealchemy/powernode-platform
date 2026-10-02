# frozen_string_literal: true

require "rails_helper"

# IMP-fd7e7082b431 — a campaign's plan_increments are seeded onto RalphTasks by
# CampaignDriver#seed_plan_increments!, which reads each increment's keys
# leniently: an unknown key is dropped, a non-list `files` reads as "none" (so
# the file-collision guard over-blocks forever), a dependency that is not a
# string is dropped. Nothing said what the keys are or refused a mistake, so a
# typo (`file:` for `files:`) cost the plan its collision data without a word.
RSpec.describe Ai::Campaigns::PlanIncrements do
  def problems(plan)
    described_class.problems("plan_increments" => plan)
  end

  it "accepts a configuration with no plan, and a plan of titles and full hashes" do
    expect(described_class.problems({})).to eq([])
    expect(described_class.problems(nil)).to eq([])
    expect(problems([ "First", { "title" => "Second", "description" => "d", "task_key" => "kx",
                                 "files" => [ "a.rb" ], "acceptance_criteria" => "it works",
                                 "dependencies" => [ "kx" ] } ])).to eq([])
  end

  it "accepts symbol keys, since a caller's hash may carry them" do
    expect(problems([ { title: "T", files: [ "a.rb" ] } ])).to eq([])
  end

  it "refuses a plan that is not a list, naming the key" do
    expect(problems("do things")).to contain_exactly(/plan_increments must be a list/)
  end

  it "refuses an unknown key, naming it and the increment, and lists the allowed ones" do
    expect(problems([ "ok", { "title" => "T", "file" => [ "a.rb" ] } ]))
      .to contain_exactly(/plan_increments\[1\]\.file is not a known key.*acceptance_criteria.*dependencies.*files/m)
  end

  it "refuses a wrong type, naming the key and the type it wants" do
    expect(problems([ { "title" => "T", "files" => "a.rb" } ])).to contain_exactly(/plan_increments\[0\]\.files must be a list of strings/)
    expect(problems([ { "title" => "T", "files" => [ "a.rb", 3 ] } ])).to contain_exactly(/plan_increments\[0\]\.files\[1\] must be a string/)
    expect(problems([ { "title" => "T", "dependencies" => "kx" } ])).to contain_exactly(/plan_increments\[0\]\.dependencies must be a list of strings/)
    expect(problems([ { "title" => 5 } ])).to contain_exactly(/plan_increments\[0\]\.title must be a string/)
    expect(problems([ { "title" => "T", "acceptance_criteria" => [ "x" ] } ])).to contain_exactly(/plan_increments\[0\]\.acceptance_criteria must be a string/)
  end

  it "refuses an increment that is neither a title nor a hash" do
    expect(problems([ 7 ])).to contain_exactly(/plan_increments\[0\] must be a title string or an object/)
  end

  it "refuses an increment with neither a title nor a task_key: the driver would silently skip it" do
    expect(problems([ { "files" => [ "a.rb" ] } ])).to contain_exactly(/plan_increments\[0\] needs a title or a task_key/)
    expect(problems([ "   " ])).to contain_exactly(/plan_increments\[0\] needs a title or a task_key/)
  end

  it "reports every problem, not just the first" do
    expect(problems([ { "title" => "T", "bogus" => 1, "files" => "x" } ]).size).to eq(2)
  end

  it "reads an absent, null or empty plan as no plan, as the driver does" do
    expect(described_class.problems("plan_increments" => nil)).to eq([])
    expect(problems([])).to eq([])
  end

  it "ignores a configuration that is not a Hash rather than raising" do
    expect(described_class.problems([ 1 ])).to eq([])
    expect(described_class.problems("x")).to eq([])
  end

  it "checks every key's type, not just the first few it knows" do
    expect(problems([ { "task_key" => 3 } ])).to contain_exactly(/plan_increments\[0\]\.task_key must be a string/)
    expect(problems([ { "title" => "T", "description" => 3 } ])).to contain_exactly(/\.description must be a string/)
    expect(problems([ { "title" => "T", "dependencies" => [ "a", 2 ] } ])).to contain_exactly(/\.dependencies\[1\] must be a string/)
  end

  it "accepts a task_key alone, and refuses a blank title with no task_key" do
    expect(problems([ { "task_key" => "kx" } ])).to eq([])
    expect(problems([ { "title" => "  " } ])).to contain_exactly(/needs a title or a task_key/)
    expect(problems([ { "title" => "", "task_key" => "kx" } ])).to eq([])
  end

  it "refuses a nil increment as not an object, not as a missing title" do
    expect(problems([ nil ])).to contain_exactly(/plan_increments\[0\] must be a title string or an object/)
  end
end
