# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Tools::PageManagementTool do
  let(:account_a) { create(:account) }
  let(:account_b) { create(:account) }
  let(:tool) { described_class.new(account: account_a) }

  describe "cross-account isolation (IDOR)" do
    let!(:own_page) { create(:page, account: account_a, title: "A's page") }
    let!(:other_page) { create(:page, account: account_b, title: "B's page") }

    it "list_pages only returns the tool account's pages" do
      result = tool.execute(params: { action: "list_pages" })

      expect(result[:success]).to be true
      ids = result[:pages].map { |p| p[:id] }
      expect(ids).to include(own_page.id)
      expect(ids).not_to include(other_page.id)
    end

    it "get_page cannot read another account's page by id" do
      result = tool.execute(params: { action: "get_page", page_id: other_page.id })

      expect(result[:success]).to be false
      expect(result[:error]).to match(/not found/i)
    end

    it "get_page cannot read another account's page by slug" do
      result = tool.execute(params: { action: "get_page", slug: other_page.slug })

      expect(result[:success]).to be false
      expect(result[:error]).to match(/not found/i)
    end

    it "update_page cannot mutate another account's page" do
      result = tool.execute(params: { action: "update_page", page_id: other_page.id, title: "hijacked" })

      expect(result[:success]).to be false
      expect(result[:error]).to match(/not found/i)
      expect(other_page.reload.title).to eq("B's page")
    end
  end

  describe "legitimate same-account access" do
    let!(:own_page) { create(:page, account: account_a, title: "Original") }

    it "get_page reads the account's own page" do
      result = tool.execute(params: { action: "get_page", page_id: own_page.id })
      expect(result[:success]).to be true
      expect(result[:page][:id]).to eq(own_page.id)
    end

    it "update_page mutates the account's own page" do
      result = tool.execute(params: { action: "update_page", page_id: own_page.id, title: "Updated" })
      expect(result[:success]).to be true
      expect(own_page.reload.title).to eq("Updated")
    end
  end
end
