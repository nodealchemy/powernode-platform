class PageSerializer
  def initialize(page, options = {})
    @page = page
    @options = options
  end

  def as_json
    {
      id: @page.id,
      title: @page.title,
      slug: @page.slug,
      content: @page.content,
      rendered_content: @page.rendered_content,
      meta_description: @page.meta_description,
      meta_keywords: @page.meta_keywords,
      published_at: @page.published_at,
      word_count: @page.word_count,
      estimated_read_time: @page.estimated_read_time,
      seo: {
        title: @page.seo_title,
        description: @page.seo_description,
        keywords: @page.seo_keywords_array
      }
    }
  end

  def self.serialize(page, options = {})
    new(page, options).as_json
  end

  def self.serialize_collection(pages, options = {})
    pages.map { |page| serialize(page, options) }
  end
end