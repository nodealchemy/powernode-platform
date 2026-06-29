# frozen_string_literal: true

require "rails_helper"

# Globalize-content campaign: KB articles seed GLOBAL (account_id nil). The tool's
# list/find paths must be override-aware (for_account = global + own) so global
# articles are discoverable, while another tenant's private articles stay hidden.
RSpec.describe Ai::Tools::KbArticleManagementTool do
  let(:account) { create(:account) }
  let(:other_account) { create(:account) }
  let(:category) { create(:kb_category) }
  subject(:tool) { described_class.new(account: account) }

  let!(:global_article) { create(:kb_article, :published, category: category, account: nil, slug: "global-art") }
  let!(:own_article)    { create(:kb_article, :published, category: category, account: account, slug: "own-art") }
  let!(:foreign_article) { create(:kb_article, :published, category: category, account: other_account, slug: "foreign-art") }

  describe "#list_articles" do
    it "lists GLOBAL and own articles but not a foreign account's" do
      slugs = tool.send(:list_articles, {})[:articles].map { |a| a[:slug] }
      expect(slugs).to include("global-art", "own-art")
      expect(slugs).not_to include("foreign-art")
    end
  end

  describe "#find_article" do
    it "finds a GLOBAL article by slug" do
      expect(tool.send(:find_article, slug: "global-art")).to eq(global_article)
    end

    it "finds a GLOBAL article by id" do
      expect(tool.send(:find_article, article_id: global_article.id)).to eq(global_article)
    end

    it "does not find a foreign account's article" do
      expect(tool.send(:find_article, slug: "foreign-art")).to be_nil
      expect(tool.send(:find_article, article_id: foreign_article.id)).to be_nil
    end
  end
end
