# frozen_string_literal: true

require "rails_helper"

RSpec.describe "SitemapController", type: :request do
  describe "GET /sitemap.xml" do
    let(:account) { create(:account) }
    let(:author) { create(:user, account: account) }

    def parse_sitemap(body)
      doc = Nokogiri::XML(body)
      doc.remove_namespaces!
      doc.xpath("//url").map do |url|
        {
          loc:        url.at_xpath("loc")&.text,
          lastmod:    url.at_xpath("lastmod")&.text,
          changefreq: url.at_xpath("changefreq")&.text,
          priority:   url.at_xpath("priority")&.text
        }
      end
    end

    it "returns 200 with application/xml content type" do
      get "/sitemap.xml"
      expect(response).to have_http_status(:ok)
      expect(response.content_type).to start_with("application/xml")
    end

    it "produces well-formed XML with sitemap.org namespace" do
      get "/sitemap.xml"
      doc = Nokogiri::XML(response.body)
      expect(doc.errors).to be_empty
      expect(doc.root.namespaces).to include("xmlns" => "http://www.sitemaps.org/schemas/sitemap/0.9")
    end

    it "includes the static landing-page paths" do
      get "/sitemap.xml"
      paths = parse_sitemap(response.body).map { |u| URI.parse(u[:loc]).path }
      expect(paths).to include("/", "/pricing", "/features")
    end

    it "uses request.base_url for absolute URLs (no hardcoded domain)" do
      get "/sitemap.xml"
      urls = parse_sitemap(response.body).map { |u| u[:loc] }
      urls.each do |url|
        expect(url).to start_with("http://www.example.com").or start_with("http://localhost").or start_with("http://127.0.0.1")
      end
      expect(urls).to all(satisfy { |u| !u.include?("powernode.org") })
    end

    it "includes whitelisted public Pages (about/contact/help/privacy/terms/welcome)" do
      create(:page, :published, account: account, user: author, slug: "about")
      create(:page, :published, account: account, user: author, slug: "help")
      create(:page, :published, account: account, user: author, slug: "privacy")

      get "/sitemap.xml"
      paths = parse_sitemap(response.body).map { |u| URI.parse(u[:loc]).path }

      expect(paths).to include("/pages/about", "/pages/help", "/pages/privacy")
    end

    it "excludes non-whitelisted Pages (e.g. account-specific personal slugs)" do
      create(:page, :published,
             account: account, user: author,
             slug: "daily-summary-2026-04-13")
      create(:page, :published,
             account: account, user: author,
             slug: "internal-notes")

      get "/sitemap.xml"
      paths = parse_sitemap(response.body).map { |u| URI.parse(u[:loc]).path }

      expect(paths).not_to include("/pages/daily-summary-2026-04-13", "/pages/internal-notes")
    end

    it "excludes draft Pages even if their slug is whitelisted" do
      create(:page, :draft, account: account, user: author, slug: "about")

      get "/sitemap.xml"
      paths = parse_sitemap(response.body).map { |u| URI.parse(u[:loc]).path }

      expect(paths).not_to include("/pages/about")
    end

    it "static paths have higher priority than dynamic Page entries" do
      create(:page, :published, account: account, user: author, slug: "about")

      get "/sitemap.xml"
      entries = parse_sitemap(response.body)
      static = entries.find { |e| URI.parse(e[:loc]).path == "/" }
      page_entry = entries.find { |e| URI.parse(e[:loc]).path == "/pages/about" }

      expect(static[:priority].to_f).to be > page_entry[:priority].to_f
    end
  end
end
