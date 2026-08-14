# frozen_string_literal: true

require "rails_helper"

# IMP-42358f7f5d4e — storage_gb is model-controlled, so the LLM can emit it as a
# Hash or Array as readily as a number. coerce_brief did
# `out["storage_gb"].to_i unless out["storage_gb"].nil?`, and Hash#to_i /
# Array#to_i do not exist, so a non-numeric shape raised NoMethodError and 500'd
# the whole intent capture. The reader it feeds, PlanComposerService
# #brief_storage_gb, already guards with `respond_to?(:to_i)` and degrades to
# no-volume; the writer must mirror that guard so a non-coercible storage_gb
# becomes no-volume (nil) instead of a crash. The nil-absence contract is
# preserved — nil DOES respond to :to_i (nil.to_i == 0), so the guard also keeps
# `!nil?`, leaving an absent storage_gb absent rather than coercing it to 0.
RSpec.describe Ai::Provisioning::IntentCaptureService, "storage_gb coercion", type: :service do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  subject(:service) { described_class.new(account: account, user: user) }

  # Drive the private post-processor with a full-shaped brief so nothing but
  # storage_gb varies. The positive-control examples below double as a harness
  # check: if coerce_brief itself were unhappy with empty_brief for some other
  # reason, they would fail too — isolating the bug to the storage_gb branch.
  def coerce_storage_gb(value)
    brief = service.send(:empty_brief).merge("storage_gb" => value)
    service.send(:coerce_brief, brief)["storage_gb"]
  end

  it "degrades a Hash storage_gb to no-volume instead of raising" do
    expect { coerce_storage_gb({}) }.not_to raise_error
    expect(coerce_storage_gb({})).to be_nil
  end

  it "degrades an Array storage_gb to no-volume instead of raising" do
    expect { coerce_storage_gb([]) }.not_to raise_error
    expect(coerce_storage_gb([])).to be_nil
  end

  it "degrades a non-empty Hash storage_gb to no-volume instead of raising" do
    expect { coerce_storage_gb({ "gb" => 250 }) }.not_to raise_error
    expect(coerce_storage_gb({ "gb" => 250 })).to be_nil
  end

  # Positive controls: the coercion the writer already performed is unchanged.
  it "still coerces a numeric string to an Integer" do
    expect(coerce_storage_gb("250")).to eq(250)
  end

  it "still passes an Integer through" do
    expect(coerce_storage_gb(250)).to eq(250)
  end

  it "still coerces an empty string to 0 (unchanged pre-fix behavior)" do
    expect(coerce_storage_gb("")).to eq(0)
  end

  it "keeps an absent storage_gb absent (nil stays nil, not coerced to 0)" do
    expect(coerce_storage_gb(nil)).to be_nil
  end
end
