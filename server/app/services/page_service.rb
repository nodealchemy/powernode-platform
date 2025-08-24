# frozen_string_literal: true

class PageService
  def self.generate_slug(title)
    # Convert title to slug format
    slug = title.to_s.downcase
                   .gsub(/[^a-z0-9\s\-]/, '') # Remove non-alphanumeric chars except spaces and hyphens
                   .gsub(/\s+/, '-')          # Replace spaces with hyphens
                   .gsub(/-+/, '-')           # Replace multiple hyphens with single
                   .gsub(/^-|-$/, '')         # Remove leading/trailing hyphens

    # Ensure slug is not empty
    slug.present? ? slug : "page-#{SecureRandom.hex(4)}"
  end

  def self.sanitize_slug(slug)
    return slug if slug.blank?
    
    # Sanitize the slug to valid format
    slug.to_s.downcase
            .gsub(/[^a-z0-9\s\-]/, '')  # Remove invalid characters
            .gsub(/\s+/, '-')            # Replace spaces with hyphens
            .gsub(/-+/, '-')             # Replace multiple hyphens with single
            .gsub(/^-|-$/, '')           # Remove leading/trailing hyphens
  end

  def self.render_markdown(content)
    # Simple markdown rendering (could be enhanced with a proper markdown gem)
    return '' if content.blank?
    
    # Basic markdown-to-HTML conversion (simplified)
    html = content.dup
    
    # Headers
    html.gsub!(/^### (.+)$/, '<h3>\1</h3>')
    html.gsub!(/^## (.+)$/, '<h2>\1</h2>')
    html.gsub!(/^# (.+)$/, '<h1>\1</h1>')
    
    # Bold and italic
    html.gsub!(/\*\*(.+?)\*\*/, '<strong>\1</strong>')
    html.gsub!(/\*(.+?)\*/, '<em>\1</em>')
    
    # Links
    html.gsub!(/\[(.+?)\]\((.+?)\)/, '<a href="\2">\1</a>')
    
    # Code
    html.gsub!(/`(.+?)`/, '<code>\1</code>')
    
    # Line breaks
    html.gsub!(/\n\n/, '</p><p>')
    html = "<p>#{html}</p>"
    
    # Clean up empty paragraphs
    html.gsub!(/<p><\/p>/, '')
    
    html
  end
end