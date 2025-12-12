# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Page, type: :model do
  subject { build(:page, slug: 'unique-test-slug') }

  # Associations
  describe 'associations' do
    it { should belong_to(:user).with_foreign_key('author_id') }
    it { should respond_to(:author) }
    it { should have_many(:file_objects).dependent(:nullify) }
    it { should have_many(:images) }
  end

  describe 'file_objects association' do
    let(:page) { create(:page) }
    let(:account) { create(:account) }
    let(:file_storage) { create(:file_storage, account: account, is_default: true) }

    it 'can have file_objects attached' do
      file = create(:file_object, account: account, attachable: page, file_storage: file_storage)
      expect(page.file_objects).to include(file)
    end

    it 'nullifies file_objects when page is deleted' do
      file = create(:file_object, account: account, attachable: page, file_storage: file_storage)
      page.destroy
      file.reload
      expect(file.attachable).to be_nil
    end

    it 'images scope returns only image file_objects' do
      image_file = create(:file_object,
                          account: account,
                          attachable: page,
                          file_type: 'image',
                          content_type: 'image/png',
                          file_storage: file_storage)
      doc_file = create(:file_object,
                        account: account,
                        attachable: page,
                        file_type: 'document',
                        content_type: 'application/pdf',
                        file_storage: file_storage)

      expect(page.images).to include(image_file)
      expect(page.images).not_to include(doc_file)
      expect(page.file_objects).to include(image_file)
      expect(page.file_objects).to include(doc_file)
    end
  end

  # Validations
  describe 'validations' do
    context 'title validation' do
      it { should validate_presence_of(:title) }
      it { should validate_length_of(:title).is_at_least(1).is_at_most(200) }
    end

    context 'slug validation' do
      # Custom validation tests since shoulda-matchers has issues with auto-generation
      it 'requires slug to be present' do
        # Test slug presence validation by creating a page without title and with blank slug
        page = Page.new(
          title: '',  # Empty title so no slug gets generated
          slug: '',   # Empty slug
          content: 'test content',
          status: 'draft'
        )
        expect(page).not_to be_valid
        expect(page.errors[:slug]).to include("can't be blank")
      end

      it 'requires slug to be unique' do
        create(:page, slug: 'unique-slug')
        duplicate = build(:page, slug: 'unique-slug')
        expect(duplicate).not_to be_valid
        expect(duplicate.errors[:slug]).to include("has already been taken")
      end

      it 'validates slug length' do
        page = build(:page, slug: 'a' * 151)
        expect(page).not_to be_valid
        expect(page.errors[:slug]).to include('is too long (maximum is 150 characters)')
      end

      it 'sanitizes slug with invalid characters' do
        user = create(:user)
        page = build(:page, slug: 'invalid-slug!', user: user)
        expect(page).to be_valid
        page.valid?  # Run validations to trigger sanitization
        expect(page.slug).to eq('invalid-slug')
      end

      it 'sanitizes slugs starting with hyphen' do
        user = create(:user)
        page = build(:page, slug: '-invalid-slug', user: user)
        expect(page).to be_valid
        page.valid?  # Run validations to trigger sanitization
        expect(page.slug).to eq('invalid-slug')
      end

      it 'sanitizes slugs ending with hyphen' do
        user = create(:user)
        page = build(:page, slug: 'invalid-slug-', user: user)
        expect(page).to be_valid
        page.valid?  # Run validations to trigger sanitization
        expect(page.slug).to eq('invalid-slug')
      end

      it 'sanitizes slugs with consecutive hyphens' do
        user = create(:user)
        page = build(:page, slug: 'invalid--slug', user: user)
        expect(page).to be_valid
        page.valid?  # Run validations to trigger sanitization
        expect(page.slug).to eq('invalid-slug')
      end
    end

    context 'content validation' do
      it { should validate_presence_of(:content) }
    end

    context 'status validation' do
      it { should validate_presence_of(:status) }
      it { should validate_inclusion_of(:status).in_array(%w[draft published]) }
    end

    context 'meta fields validation' do
      it { should validate_length_of(:meta_description).is_at_most(300) }
      it { should validate_length_of(:meta_keywords).is_at_most(500) }
      it { should allow_value(nil).for(:meta_description) }
      it { should allow_value('').for(:meta_description) }
      it { should allow_value(nil).for(:meta_keywords) }
      it { should allow_value('').for(:meta_keywords) }
    end
  end

  # Scopes
  describe 'scopes' do
    let!(:published_page) { create(:page, :published) }
    let!(:draft_page) { create(:page, :draft) }
    let!(:author) { create(:user) }
    let!(:authored_page) { create(:page, user: author) }

    describe '.published' do
      it 'returns only published pages' do
        expect(Page.published).to include(published_page)
        expect(Page.published).not_to include(draft_page)
      end
    end

    describe '.draft' do
      it 'returns only draft pages' do
        expect(Page.draft).to include(draft_page)
        expect(Page.draft).not_to include(published_page)
      end
    end

    describe '.by_slug' do
      it 'returns page with matching slug' do
        expect(Page.by_slug(published_page.slug)).to include(published_page)
        expect(Page.by_slug(published_page.slug)).not_to include(draft_page)
      end
    end

    describe '.recent' do
      it 'orders pages by created_at desc' do
        # Create pages with explicit ordering expectation
        first_page = create(:page)
        sleep(0.01)  # Ensure different timestamps
        second_page = create(:page)

        recent_pages = Page.recent.limit(2)
        expect(recent_pages.first.id).to eq(second_page.id)
        expect(recent_pages.second.id).to eq(first_page.id)
      end
    end

    describe '.by_author' do
      it 'returns pages by specific author' do
        expect(Page.by_author(author)).to include(authored_page)
        expect(Page.by_author(author)).not_to include(published_page)
      end
    end
  end

  # Callbacks
  describe 'callbacks' do
    context 'slug generation' do
      it 'generates slug from title if slug is blank on create' do
        page = build(:page, title: 'My Great Page Title', slug: nil)
        page.save!
        expect(page.slug).to eq('my-great-page-title')
      end

      it 'does not override existing slug' do
        page = build(:page, title: 'My Great Page Title', slug: 'custom-slug')
        page.save!
        expect(page.slug).to eq('custom-slug')
      end

      it 'sanitizes slug before saving' do
        page = build(:page, slug: 'My-SLUG-With-CAPS!')
        page.save!
        expect(page.slug).to eq('my-slug-with-caps')
      end
    end

    context 'published_at setting' do
      it 'sets published_at when status changes to published' do
        page = create(:page, :draft)
        expect(page.published_at).to be_nil

        page.update!(status: 'published')
        expect(page.published_at).not_to be_nil
      end

      it 'clears published_at when status changes to draft' do
        page = create(:page, :published)
        expect(page.published_at).not_to be_nil

        page.update!(status: 'draft')
        expect(page.published_at).to be_nil
      end
    end
  end

  # Instance methods
  describe 'instance methods' do
    let(:page) { create(:page) }

    describe '#published?' do
      it 'returns true for published pages' do
        page.update!(status: 'published')
        expect(page.published?).to be true
      end

      it 'returns false for draft pages' do
        page.update!(status: 'draft')
        expect(page.published?).to be false
      end
    end

    describe '#draft?' do
      it 'returns true for draft pages' do
        page.update!(status: 'draft')
        expect(page.draft?).to be true
      end

      it 'returns false for published pages' do
        page.update!(status: 'published')
        expect(page.draft?).to be false
      end
    end

    describe '#publish!' do
      it 'sets status to published and sets published_at' do
        page = create(:page, :draft)
        page.publish!
        expect(page.status).to eq('published')
        expect(page.published_at).not_to be_nil
      end
    end

    describe '#unpublish!' do
      it 'sets status to draft and clears published_at' do
        page = create(:page, :published)
        page.unpublish!
        expect(page.status).to eq('draft')
        expect(page.published_at).to be_nil
      end
    end

    describe '#to_param' do
      it 'returns the slug' do
        page = create(:page, slug: 'my-page-slug')
        expect(page.to_param).to eq('my-page-slug')
      end
    end

    describe '#rendered_content' do
      it 'renders markdown content to HTML' do
        page = create(:page, content: '# Hello World')
        expect(page.rendered_content).to include('<h1')
        expect(page.rendered_content).to include('Hello World')
      end
    end

    describe '#word_count' do
      it 'counts words in content' do
        page = create(:page, content: 'This is a test content with eight words.')
        expect(page.word_count).to eq(8)  # "This is a test content with eight words."
      end

      it 'handles empty content' do
        page = build(:page, content: ' ')  # Build instead of create for invalid data
        expect(page.word_count).to eq(0)
      end
    end

    describe '#estimated_read_time' do
      it 'calculates reading time based on word count' do
        # 200 words should take 1 minute
        content = (Array.new(200) { 'word' }).join(' ')
        page = create(:page, content: content)
        expect(page.estimated_read_time).to eq(1)
      end

      it 'rounds up partial minutes' do
        # 250 words should take 2 minutes (1.25 rounded up)
        content = (Array.new(250) { 'word' }).join(' ')
        page = create(:page, content: content)
        expect(page.estimated_read_time).to eq(2)
      end
    end

    describe '#seo_title' do
      it 'returns the page title' do
        page = create(:page, title: 'My SEO Title')
        expect(page.seo_title).to eq('My SEO Title')
      end
    end

    describe '#seo_description' do
      it 'returns meta_description if present' do
        page = create(:page, meta_description: 'Custom meta description')
        expect(page.seo_description).to eq('Custom meta description')
      end

      it 'falls back to truncated content if no meta_description' do
        long_content = 'A' * 200
        page = create(:page, content: long_content, meta_description: nil)
        expect(page.seo_description.length).to be <= 160
      end
    end

    describe '#seo_keywords_array' do
      it 'splits meta_keywords by comma' do
        page = create(:page, meta_keywords: 'keyword1, keyword2, keyword3')
        expect(page.seo_keywords_array).to eq([ 'keyword1', 'keyword2', 'keyword3' ])
      end

      it 'returns empty array if no meta_keywords' do
        page = create(:page, meta_keywords: nil)
        expect(page.seo_keywords_array).to eq([])
      end

      it 'filters out blank keywords' do
        page = create(:page, meta_keywords: 'keyword1, , keyword3')
        expect(page.seo_keywords_array).to eq([ 'keyword1', 'keyword3' ])
      end
    end
  end

  # Database constraints and indexes
  describe 'database' do
    it 'enforces unique constraint on slug' do
      create(:page, slug: 'unique-slug')
      expect {
        create(:page, slug: 'unique-slug')
      }.to raise_error(ActiveRecord::RecordInvalid, /Slug has already been taken/)
    end
  end
end
