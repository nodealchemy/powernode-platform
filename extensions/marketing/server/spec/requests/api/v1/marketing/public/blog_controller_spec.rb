# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Marketing::Public::BlogController", type: :request do
  let(:account) { create(:account) }
  let(:author) { create(:user, account: account) }

  describe "GET /api/v1/marketing/public/blog/posts" do
    let(:endpoint) { "/api/v1/marketing/public/blog/posts" }

    it "returns blog-tagged published Pages" do
      blog_post = create(:page, :published,
                         account: account,
                         user: author,
                         title: "Why kill switches",
                         slug: "why-kill-switches",
                         meta_keywords: "blog, governance",
                         meta_description: "On the importance of kill switches.")

      get endpoint, as: :json

      expect(response).to have_http_status(:ok)
      data = JSON.parse(response.body).fetch("data")
      slugs = data.fetch("posts").map { |p| p["slug"] }
      expect(slugs).to include(blog_post.slug)
    end

    it "excludes pages without 'blog' in meta_keywords" do
      create(:page, :published,
             account: account, user: author,
             title: "Privacy Policy", slug: "privacy",
             meta_keywords: "legal, privacy")

      get endpoint, as: :json

      data = JSON.parse(response.body).fetch("data")
      slugs = data.fetch("posts").map { |p| p["slug"] }
      expect(slugs).not_to include("privacy")
    end

    it "excludes draft (unpublished) blog pages" do
      create(:page, :draft,
             account: account, user: author,
             title: "Draft post", slug: "draft-post",
             meta_keywords: "blog")

      get endpoint, as: :json

      data = JSON.parse(response.body).fetch("data")
      slugs = data.fetch("posts").map { |p| p["slug"] }
      expect(slugs).not_to include("draft-post")
    end

    it "is publicly accessible without authentication" do
      get endpoint, as: :json
      expect(response).to have_http_status(:ok)
    end

    it "returns posts with summary fields (slug, title, excerpt, published_at, estimated_read_time)" do
      create(:page, :published,
             account: account, user: author,
             title: "Test post", slug: "test-post",
             meta_keywords: "blog",
             meta_description: "Excerpt here.")

      get endpoint, as: :json

      post = JSON.parse(response.body).fetch("data").fetch("posts").first
      expect(post.keys).to include("slug", "title", "excerpt", "published_at", "estimated_read_time")
    end

    it "orders posts by published_at descending" do
      old_post = create(:page, :published,
                        account: account, user: author,
                        slug: "old-post", meta_keywords: "blog",
                        published_at: 10.days.ago)
      new_post = create(:page, :published,
                        account: account, user: author,
                        slug: "new-post", meta_keywords: "blog",
                        published_at: 1.day.ago)

      get endpoint, as: :json

      slugs = JSON.parse(response.body).fetch("data").fetch("posts").map { |p| p["slug"] }
      expect(slugs.index(new_post.slug)).to be < slugs.index(old_post.slug)
    end
  end

  describe "GET /api/v1/marketing/public/blog/posts/:slug" do
    let!(:blog_post) do
      create(:page, :published, :with_markdown,
             account: account, user: author,
             title: "Why kill switches",
             slug: "why-kill-switches",
             meta_keywords: "blog, governance",
             meta_description: "Brief excerpt.")
    end

    it "returns the post by slug with full content" do
      get "/api/v1/marketing/public/blog/posts/#{blog_post.slug}", as: :json

      expect(response).to have_http_status(:ok)
      post = JSON.parse(response.body).fetch("data").fetch("post")
      expect(post["slug"]).to eq(blog_post.slug)
      expect(post["title"]).to eq("Why kill switches")
      expect(post["content"]).to include("Main Heading")
      expect(post["meta"]).to include("description" => "Brief excerpt.")
    end

    it "returns 404 for a non-existent slug" do
      get "/api/v1/marketing/public/blog/posts/does-not-exist", as: :json
      expect(response.status).to eq(404)
    end

    it "returns 404 for a published Page that is NOT blog-tagged" do
      create(:page, :published,
             account: account, user: author,
             slug: "privacy", meta_keywords: "legal, privacy")

      get "/api/v1/marketing/public/blog/posts/privacy", as: :json
      expect(response.status).to eq(404)
    end

    it "returns 404 for draft blog pages" do
      create(:page, :draft,
             account: account, user: author,
             slug: "draft-post", meta_keywords: "blog")

      get "/api/v1/marketing/public/blog/posts/draft-post", as: :json
      expect(response.status).to eq(404)
    end

    it "is publicly accessible without authentication" do
      get "/api/v1/marketing/public/blog/posts/#{blog_post.slug}", as: :json
      expect(response).to have_http_status(:ok)
    end
  end
end
