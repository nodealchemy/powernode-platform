# frozen_string_literal: true

require "rails_helper"

# Caller text that may reach a commit message written by dev_merge_increment.
# The names here are synthetic: a spec is a tracked file, and a tracked file
# must never name a real private extension.
RSpec.describe Ai::DevMerge::CommitMessagePolicy do
  def violation(text, names: %w[zzhidden kebab-slug])
    described_class.violation(text, forbidden_names: names)
  end

  it "accepts an ordinary summary" do
    expect(violation("governed in-place peer key rotation")).to be_nil
  end

  describe "AI attribution" do
    [
      "Co-Authored-By: Anyone <a@example.invalid>",
      "co-authored-by: lower case too",
      "Generated with some tool",
      "fix the thing\n\nReviewed-by: Claude",
      "Assisted-by: GPT-5",
      "Signed-off-by: Gemini Agent"
    ].each do |text|
      it "refuses #{text.lines.last.strip.inspect}" do
        expect(violation(text)).to match(/AI attribution/)
      end
    end

    it "does not read a model word outside a trailer as attribution" do
      expect(violation("document the sonnet form")).to be_nil
    end
  end

  # Reject, never strip. The bytes are built with .chr, never with a \u
  # escape (which is decoded in transit before it reaches the file).
  describe "control bytes" do
    { 30 => "\\x1e", 0 => "\\x00", 127 => "\\x7f", 27 => "\\x1b" }.each do |code, named|
      it "refuses #{named}, naming the byte and never echoing the text" do
        reason = violation("fix the thing#{code.chr}quietly")

        expect(reason).to eq("it contains the control byte #{named}")
        expect(reason).not_to include("quietly")
      end
    end

    it "lets tab, LF and CR through" do
      expect(violation("a\tb\r\nc")).to be_nil
    end
  end

  describe "private extension names" do
    it "refuses the slug as a word, in any case" do
      expect(violation("wire ZZHIDDEN into the seam")).to match(/private extension/)
    end

    it "refuses the PascalCase namespace of a kebab slug" do
      expect(violation("call KebabSlug::Thing")).to match(/private extension/)
    end

    it "refuses the submodule path" do
      expect(violation("bump extensions/private/zzhidden")).to match(/private extension/)
    end

    it "does not match a longer word that merely contains the slug" do
      expect(violation("zzhiddenness is fine")).to be_nil
    end

    it "never quotes the name back" do
      expect(violation("zzhidden")).not_to include("zzhidden")
    end

    it "takes the names from Ai::DevMerge::ForbiddenNames by default" do
      allow(Ai::DevMerge::ForbiddenNames).to receive(:resolve)
        .and_return(Ai::DevMerge::ForbiddenNames::Result.new(names: %w[zzderived], determinate: true))

      expect(described_class.violation("touch zzderived")).to match(/private extension/)
      expect(described_class.violation("touch nothing private")).to be_nil
    end
  end
end
