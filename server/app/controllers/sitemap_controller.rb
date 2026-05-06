# frozen_string_literal: true

# Serves /sitemap.xml dynamically. Uses request.base_url so URLs track
# the actual public host of the request — including X-Forwarded-Proto
# and X-Forwarded-Host from reverse proxies (Traefik, nginx, etc.).
# This makes the sitemap correct for any deployment without per-instance
# build configuration. Inherits from ActionController::Base to avoid
# the authentication chain on ApplicationController; sitemap.xml is
# a public artifact by definition.
class SitemapController < ActionController::Base
  PUBLIC_PATHS = [
    { path: "/",         changefreq: "weekly",  priority: "1.0" },
    { path: "/pricing",  changefreq: "monthly", priority: "0.9" },
    { path: "/features", changefreq: "monthly", priority: "0.9" }
  ].freeze

  def index
    base = request.base_url
    lastmod = Time.zone.today.iso8601
    render content_type: "application/xml", plain: build_xml(base, lastmod)
  end

  private

  def build_xml(base, lastmod)
    entries = PUBLIC_PATHS.map { |u| url_entry(base, u, lastmod) }.join("\n")
    <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
      #{entries}
      </urlset>
    XML
  end

  def url_entry(base, url, lastmod)
    <<~XML.chomp
        <url>
          <loc>#{xml_escape("#{base}#{url[:path]}")}</loc>
          <lastmod>#{lastmod}</lastmod>
          <changefreq>#{url[:changefreq]}</changefreq>
          <priority>#{url[:priority]}</priority>
        </url>
    XML
  end

  def xml_escape(value)
    value.to_s.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;").gsub("\"", "&quot;").gsub("'", "&apos;")
  end
end
