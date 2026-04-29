# frozen_string_literal: true

require "rails_helper"

RSpec.describe Shared::ExtensionStateStore do
  let(:tmp_root) { Pathname.new(Dir.mktmpdir("extstate")) }
  let(:state_file) { tmp_root.join("config", "extensions_state.json") }

  before do
    allow(described_class).to receive(:path).and_return(state_file)
  end

  after do
    FileUtils.rm_rf(tmp_root)
  end

  describe ".read" do
    it "returns the default state when the file does not exist" do
      expect(described_class.read).to eq("disabled" => [])
    end

    it "parses an existing state file" do
      FileUtils.mkdir_p(state_file.dirname)
      File.write(state_file, JSON.generate("disabled" => %w[trading business]))

      expect(described_class.read).to eq("disabled" => %w[trading business])
    end

    it "coerces non-string slugs to strings" do
      FileUtils.mkdir_p(state_file.dirname)
      File.write(state_file, JSON.generate("disabled" => [:trading, "business"]))

      expect(described_class.read["disabled"]).to eq(%w[trading business])
    end

    it "falls back to default state on malformed JSON" do
      FileUtils.mkdir_p(state_file.dirname)
      File.write(state_file, "not json {{{")

      expect(described_class.read).to eq("disabled" => [])
    end
  end

  describe ".disabled?" do
    before do
      FileUtils.mkdir_p(state_file.dirname)
      File.write(state_file, JSON.generate("disabled" => ["trading"]))
    end

    it "returns true when slug is in the list" do
      expect(described_class.disabled?("trading")).to be true
    end

    it "returns false when slug is not in the list" do
      expect(described_class.disabled?("business")).to be false
    end

    it "accepts symbols and stringifies them" do
      expect(described_class.disabled?(:trading)).to be true
    end
  end

  describe ".set_disabled!" do
    it "creates the file and adds the slug when disabling for the first time" do
      result = described_class.set_disabled!("trading", disabled: true)

      expect(state_file).to exist
      expect(JSON.parse(state_file.read)).to eq("disabled" => ["trading"])
      expect(result).to eq("disabled" => ["trading"])
    end

    it "does not duplicate slugs already in the list" do
      described_class.set_disabled!("trading", disabled: true)
      described_class.set_disabled!("trading", disabled: true)

      expect(described_class.read["disabled"]).to eq(["trading"])
    end

    it "removes a slug when disabled: false" do
      described_class.set_disabled!("trading", disabled: true)
      described_class.set_disabled!("trading", disabled: false)

      expect(described_class.read["disabled"]).to eq([])
    end

    it "preserves other disabled slugs when toggling one" do
      described_class.set_disabled!("trading", disabled: true)
      described_class.set_disabled!("business", disabled: true)
      described_class.set_disabled!("trading", disabled: false)

      expect(described_class.read["disabled"]).to eq(["business"])
    end

    it "writes via temp + rename so partial files are never observed" do
      # Force a write failure mid-rename to verify no partial file lands at the
      # canonical path (the helper deletes its temp file on failure).
      allow(File).to receive(:rename).and_raise(Errno::EACCES, "denied")

      expect { described_class.set_disabled!("trading", disabled: true) }
        .to raise_error(Errno::EACCES)
      expect(state_file).not_to exist
      expect(Dir.children(state_file.dirname)).to be_empty
    end
  end
end
