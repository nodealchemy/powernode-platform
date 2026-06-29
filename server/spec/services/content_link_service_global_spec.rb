# frozen_string_literal: true

require "rails_helper"

# Globalize-content campaign: the [[wiki-link]] resolver's KB-article fallback
# must be override-aware — it resolves GLOBAL platform articles and the account's
# own, but never another tenant's private article.
RSpec.describe ContentLinkService do
  let(:account) { create(:account) }
  let(:other_account) { create(:account) }
  let(:category) { create(:kb_category) }
  subject(:service) { described_class.new(account: account) }

  it "resolves a GLOBAL article via the fallback" do
    global = create(:kb_article, :published, category: category, account: nil,
                                             title: "Platform Guide", slug: "platform-guide")
    expect(service.send(:resolve_link,"Platform Guide")).to eq(global)
  end

  it "does not resolve a foreign account's article" do
    create(:kb_article, :published, category: category, account: other_account,
                                    title: "Secret Doc", slug: "secret-doc")
    expect(service.send(:resolve_link,"Secret Doc")).to be_nil
  end
end
