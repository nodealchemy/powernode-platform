# frozen_string_literal: true

# Serves /sitemap.xml dynamically. Uses request.base_url so URLs track
# the actual public host of the request — including X-Forwarded-Proto
# and X-Forwarded-Host from reverse proxies (Traefik, nginx, etc.).
# This makes the sitemap correct for any deployment without per-instance
# build configuration. Inherits from ActionController::Base to avoid
# the authentication chain on ApplicationController; sitemap.xml is
# a public artifact by definition.
class SitemapController < ActionController::Base
  # Static landing-page paths served by the SPA. Always present in sitemap.
  PUBLIC_PATHS = [
    { path: "/",         changefreq: "weekly",  priority: "1.0" },
    { path: "/pricing",  changefreq: "monthly", priority: "0.9" },
    { path: "/features", changefreq: "monthly", priority: "0.9" }
  ].freeze

  # Slug whitelist for Page records that should appear in the public sitemap.
  # Extending this list is an explicit opt-in — prevents account-specific pages
  # (e.g. personal notes, dated summaries) from leaking into search indexes.
  PUBLIC_PAGE_SLUGS = %w[about contact help privacy terms welcome].freeze

  def index
    base = request.base_url
    today = Time.zone.today.iso8601
    render content_type: "application/xml", plain: build_xml(base, today)
  end

  private

  def build_xml(base, today)
    entries = (static_entries(base, today) + page_entries(base)).join("\n")
    <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
      #{entries}
      </urlset>
    XML
  end

  def static_entries(base, today)
    PUBLIC_PATHS.map do |url|
      url_entry(loc: "#{base}#{url[:path]}", lastmod: today,
                changefreq: url[:changefreq], priority: url[:priority])
    end
  end

  def page_entries(base)
    return [] unless defined?(::Page)

    ::Page.published.where(slug: PUBLIC_PAGE_SLUGS).find_each.map do |page|
      url_entry(loc: "#{base}/pages/#{page.slug}",
                lastmod: page.updated_at.to_date.iso8601,
                changefreq: "monthly",
                priority: "0.6")
    end
  end

  def url_entry(loc:, lastmod:, changefreq:, priority:)
    <<~XML.chomp
        <url>
          <loc>#{xml_escape(loc)}</loc>
          <lastmod>#{lastmod}</lastmod>
          <changefreq>#{changefreq}</changefreq>
          <priority>#{priority}</priority>
        </url>
    XML
  end

  def xml_escape(value)
    value.to_s.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;").gsub("\"", "&quot;").gsub("'", "&apos;")
  end
end
