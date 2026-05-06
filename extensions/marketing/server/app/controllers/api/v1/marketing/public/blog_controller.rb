# frozen_string_literal: true

module Api
  module V1
    module Marketing
      module Public
        # Public blog endpoints. Filters published Page records whose
        # meta_keywords includes "blog" — the convention for tagging a
        # Page as a blog post. No new model needed; the existing Page
        # model carries title, slug, content, and SEO metadata.
        class BlogController < ApplicationController
          skip_before_action :authenticate_request, raise: false

          BLOG_KEYWORD = "blog"

          # GET /api/v1/marketing/public/blog/posts
          def index
            posts = blog_pages
                      .order(published_at: :desc, created_at: :desc)
                      .limit(50)
            render_success(posts: posts.map { |p| post_summary(p) })
          end

          # GET /api/v1/marketing/public/blog/posts/:slug
          def show
            post = ::Page.published.find_by(slug: params[:slug])

            unless post && blog_keyword?(post.meta_keywords)
              return render_error("Blog post not found", :not_found)
            end

            render_success(post: post_detail(post))
          end

          private

          def blog_pages
            ::Page.published
                  .where.not(meta_keywords: nil)
                  .where("meta_keywords ILIKE ?", "%#{BLOG_KEYWORD}%")
          end

          def blog_keyword?(keywords)
            keywords.to_s.downcase.include?(BLOG_KEYWORD)
          end

          def post_summary(page)
            {
              slug: page.slug,
              title: page.title,
              excerpt: page.meta_description,
              published_at: page.published_at,
              estimated_read_time: page.estimated_read_time
            }
          end

          def post_detail(page)
            {
              slug: page.slug,
              title: page.title,
              content: page.content,
              rendered_content: page.rendered_content,
              excerpt: page.meta_description,
              published_at: page.published_at,
              estimated_read_time: page.estimated_read_time,
              meta: {
                description: page.meta_description,
                keywords: page.meta_keywords
              }
            }
          end
        end
      end
    end
  end
end
