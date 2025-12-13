# frozen_string_literal: true

class AdminPageSerializer < PageSerializer
  def as_json
    base_data = super
    base_data.merge({
      status: @page.status,
      author: {
        id: @page.user.id,
        name: @page.user.full_name,
        email: @page.user.email
      },
      created_at: @page.created_at,
      updated_at: @page.updated_at,
      excerpt: @page.content.to_s.truncate(200)
    })
  end

  def self.serialize_for_index(page)
    {
      id: page.id,
      title: page.title,
      slug: page.slug,
      status: page.status,
      meta_description: page.meta_description,
      meta_keywords: page.meta_keywords,
      author: {
        id: page.user.id,
        name: page.user.full_name,
        email: page.user.email
      },
      published_at: page.published_at,
      word_count: page.word_count,
      estimated_read_time: page.estimated_read_time,
      created_at: page.created_at,
      updated_at: page.updated_at,
      excerpt: page.content.to_s.truncate(200)
    }
  end

  def self.serialize_for_public_index(page)
    {
      id: page.id,
      title: page.title,
      slug: page.slug,
      meta_description: page.meta_description,
      published_at: page.published_at,
      word_count: page.word_count,
      estimated_read_time: page.estimated_read_time,
      excerpt: page.content.to_s.truncate(200)
    }
  end
end
