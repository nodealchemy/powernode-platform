# frozen_string_literal: true

FactoryBot.define do
  factory :page do
    sequence(:title) { |n| "#{Faker::Lorem.sentence(word_count: 3).chomp('.')} #{n}" }
    sequence(:slug) { |n| "test-page-#{n}" }
    content { Faker::Lorem.paragraphs(number: 3).map { |p| "#{p}\n\n" }.join }
    meta_description { Faker::Lorem.sentence(word_count: 15) }
    meta_keywords { Faker::Lorem.words(number: 8).join(', ') }
    status { 'draft' }
    user { association(:user, account: account) }
    account
    published_at { nil }

    trait :published do
      status { 'published' }
      published_at { 1.day.ago }
    end

    trait :draft do
      status { 'draft' }
      published_at { nil }
    end

    trait :with_markdown do
      content do
        <<~MARKDOWN
          # Main Heading

          This is a paragraph with **bold text** and *italic text*.

          ## Subheading

          Here's a list:

          - Item 1
          - Item 2
          - Item 3

          Here's some `inline code` and a [link](https://example.com).

          ```ruby
          def hello_world
            Rails.logger.debug "Hello, World!"
          end
          ```

          > This is a blockquote with some important information.

          | Column 1 | Column 2 |
          |----------|----------|
          | Data 1   | Data 2   |
          | Data 3   | Data 4   |
        MARKDOWN
      end
    end

    trait :with_long_content do
      content { Faker::Lorem.paragraphs(number: 10).map { |p| "#{p}\n\n" }.join }
    end

    trait :seo_optimized do
      meta_description { "A comprehensive guide to understanding this topic in detail with practical examples." }
      meta_keywords { "guide, tutorial, examples, practical, comprehensive, detailed" }
    end

    # Create a page with a specific slug
    factory :page_with_slug do
      sequence(:slug) { |n| "custom-page-#{n}" }
    end

    # Create a page by a specific author
    factory :page_by_author do
      transient do
        author { nil }
      end

      user { author || association(:user) }
    end
  end
end
