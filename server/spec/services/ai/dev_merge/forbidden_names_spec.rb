# frozen_string_literal: true

require "rails_helper"

# Which private-extension names a dev_merge_increment may never publish, and
# whether this host can know. Synthetic names only: a spec is a tracked file.
RSpec.describe Ai::DevMerge::ForbiddenNames do
  let(:registry) { {} }

  before do
    allow(Shared::ExtensionPaths).to receive(:private_slugs).and_return([])
    allow(Shared::ExtensionPaths).to receive(:private_root_present?).and_return(false)
    allow(Powernode::ExtensionRegistry).to receive(:all).and_return(registry)
    allow(Powernode::ExtensionRegistry).to receive(:slugs) { registry.keys }
  end

  def declare(value)
    SiteSetting.set(described_class::SETTING_KEY, value, setting_type: "json")
  end

  # N1: a registry-only list proves only that SOME private extension is
  # loaded here, never that it is the whole set, so without a declaration or
  # the on-disk directory it is not an answer.
  it "is INDETERMINATE for a registry-only list: one private engine loaded, no declaration, no directory" do
    registry.merge!("zz-loaded" => { private: true }, "public-one" => { private: false })

    result = described_class.resolve

    expect(result).not_to be_determinate
    expect(result.reason).to include(described_class::SETTING_KEY)
    expect(result.reason).not_to include("zz-loaded")
  end

  it "still carries the registry's names once the list is determinate" do
    registry["zz-loaded"] = { private: true }
    declare([])

    expect(described_class.resolve.names).to eq(%w[zz-loaded])
  end

  it "is determinate when extensions/private/ exists on disk, even with nothing declared" do
    allow(Shared::ExtensionPaths).to receive(:private_root_present?).and_return(true)
    allow(Shared::ExtensionPaths).to receive(:private_slugs).and_return(%w[zz-disk])
    registry["public-one"] = { private: false }

    result = described_class.resolve

    expect(result).to be_determinate
    expect(result.names).to eq(%w[zz-disk])
  end

  it "unions the on-disk directories, the registry and the operator's declaration" do
    allow(Shared::ExtensionPaths).to receive(:private_slugs).and_return(%w[zz-disk])
    registry["zz-loaded"] = { private: true }
    declare(%w[zz-declared zz-disk])

    expect(described_class.resolve.names).to eq(%w[zz-declared zz-disk zz-loaded])
  end

  it "answers a determinate [] in core mode: no extension registered at all" do
    result = described_class.resolve

    expect(result.names).to eq([])
    expect(result).to be_determinate
  end

  it "is INDETERMINATE when extensions are loaded, none is private here, and nothing was declared" do
    registry["public-one"] = { private: false }

    result = described_class.resolve

    expect(result).not_to be_determinate
    expect(result.reason).to include(described_class::SETTING_KEY)
  end

  it "lets the operator declare that none exist, with an explicit empty list" do
    registry["public-one"] = { private: false }
    declare([])

    result = described_class.resolve

    expect(result.names).to eq([])
    expect(result).to be_determinate
  end

  it "refuses a declaration that is not a list of slugs" do
    expect { declare({ "a" => 1 }) }.to raise_error(ActiveRecord::RecordInvalid)
    expect { declare([ "Not A Slug" ]) }.to raise_error(ActiveRecord::RecordInvalid)
  end

  it "keeps the declaration off every public settings surface" do
    declare(%w[zz-declared])

    expect(SiteSetting.find_by(key: described_class::SETTING_KEY).is_public).to be(false)
  end

  it "never puts a name in its reason" do
    registry["public-one"] = { private: false }
    allow(Shared::ExtensionPaths).to receive(:private_slugs).and_return([])
    allow(Shared::ExtensionPaths).to receive(:private_root_present?).and_return(false)

    expect(described_class.resolve.reason).not_to include("public-one")
  end

  # IMP-1765f6f09458 — the ordering the protected declaration registers for a
  # MACHINE park: a list is at least as restrictive as the current one when it
  # keeps every declared name. Unset is the most restrictive state (the merge
  # refuses to publish at all), so nothing tightens from it by machine.
  describe ".tightens?" do
    it "accepts a superset and the same list" do
      expect(described_class.tightens?(%w[alpha beta], %w[alpha])).to be(true)
      expect(described_class.tightens?(%w[beta alpha], %w[alpha beta])).to be(true)
      expect(described_class.tightens?([], [])).to be(true)
    end

    it "refuses a list that drops a declared name" do
      expect(described_class.tightens?(%w[alpha], %w[alpha beta])).to be(false)
      expect(described_class.tightens?([], %w[alpha])).to be(false)
      expect(described_class.tightens?(%w[gamma], %w[alpha])).to be(false)
    end

    it "refuses every list while the declaration is unset" do
      expect(described_class.tightens?([], nil)).to be(false)
      expect(described_class.tightens?(%w[alpha], nil)).to be(false)
    end

    it "refuses anything that is not a slug list on either side" do
      expect(described_class.tightens?("alpha", %w[alpha])).to be(false)
      expect(described_class.tightens?(%w[alpha], {})).to be(false)
      expect(described_class.tightens?([ "Not A Slug" ], [])).to be(false)
      expect(described_class.tightens?(%w[alpha], [ 1 ])).to be(false)
    end
  end
end
