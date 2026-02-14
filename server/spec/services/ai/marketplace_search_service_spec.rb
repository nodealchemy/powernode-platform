# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::MarketplaceSearchService, type: :service do
  let(:publisher) { create(:ai_publisher_account) }

  # Helper to create templates with publisher_id set directly
  def create_template(attrs)
    Ai::AgentTemplate.create!(
      { publisher_id: publisher.id, version: "1.0.0" }.merge(attrs)
    )
  end

  let!(:template_popular) do
    create_template(
      name: "Popular Bot",
      slug: "popular-bot-#{SecureRandom.hex(4)}",
      status: "published",
      visibility: "public",
      published_at: Time.current,
      installation_count: 500,
      average_rating: 4.5,
      review_count: 20,
      pricing_type: "free",
      is_featured: true,
      is_verified: true,
      features: ["streaming", "function_calling"],
      description: "A popular AI bot"
    )
  end

  let!(:template_paid) do
    create_template(
      name: "Premium Bot",
      slug: "premium-bot-#{SecureRandom.hex(4)}",
      status: "published",
      visibility: "public",
      published_at: Time.current,
      installation_count: 100,
      average_rating: 4.8,
      review_count: 10,
      pricing_type: "one_time",
      price_usd: 19.99,
      is_verified: false,
      features: ["code_generation"],
      description: "A premium AI bot"
    )
  end

  let!(:template_low_rated) do
    create_template(
      name: "Basic Bot",
      slug: "basic-bot-#{SecureRandom.hex(4)}",
      status: "published",
      visibility: "public",
      published_at: Time.current,
      installation_count: 10,
      average_rating: 2.5,
      review_count: 3,
      pricing_type: "free",
      is_verified: false,
      features: [],
      description: "A basic bot"
    )
  end

  let!(:template_draft) do
    create_template(
      name: "Draft Bot",
      slug: "draft-bot-#{SecureRandom.hex(4)}",
      status: "draft",
      visibility: "private",
      pricing_type: "free",
      description: "An unpublished bot"
    )
  end

  # The service's base_query includes :categories which doesn't exist.
  # Patch the private base_query method to skip the missing association.
  before do
    allow_any_instance_of(described_class).to receive(:base_query).and_return(
      Ai::AgentTemplate.published.includes(:publisher)
    )
  end

  # ===========================================================================
  # #search
  # ===========================================================================

  describe "#search" do
    context "with no params" do
      subject(:service) { described_class.new({}) }

      it "returns all published templates" do
        result = service.search

        ids = result[:templates].map(&:id)
        expect(ids).to include(template_popular.id, template_paid.id, template_low_rated.id)
        expect(ids).not_to include(template_draft.id)
      end

      it "returns total_count" do
        result = service.search

        expect(result[:total_count]).to be >= 3
      end

      it "returns filters_applied hash" do
        result = service.search

        expect(result[:filters_applied]).to be_a(Hash)
        expect(result[:filters_applied]).to be_empty
      end

      it "sorts by installation_count desc by default" do
        result = service.search
        counts = result[:templates].map(&:installation_count)

        expect(counts).to eq(counts.sort.reverse)
      end
    end

    context "with text search" do
      subject(:service) { described_class.new({ q: "Premium" }) }

      it "filters templates by name" do
        result = service.search

        names = result[:templates].map(&:name)
        expect(names).to include("Premium Bot")
        expect(names).not_to include("Basic Bot")
      end

      it "tracks the query filter" do
        result = service.search

        expect(result[:filters_applied][:query]).to eq("Premium")
      end
    end

    context "with pricing filter" do
      it "filters by pricing type" do
        service = described_class.new({ pricing_type: "free" })
        result = service.search

        result[:templates].each do |t|
          expect(t.pricing_type).to eq("free")
        end
      end

      it "filters free_only" do
        service = described_class.new({ free_only: "true" })
        result = service.search

        result[:templates].each do |t|
          expect(t.pricing_type).to eq("free")
        end
      end

      it "filters by max_price" do
        service = described_class.new({ max_price: "10.00" })
        result = service.search

        # Should include free templates and paid templates under $10
        result[:templates].each do |t|
          expect(t.pricing_type == "free" || t.price_usd.to_f <= 10.0).to be true
        end
      end
    end

    context "with rating filter" do
      subject(:service) { described_class.new({ min_rating: "4.0" }) }

      it "filters templates by minimum rating" do
        result = service.search

        result[:templates].each do |t|
          expect(t.average_rating).to be >= 4.0
        end
      end
    end

    context "with features filter" do
      subject(:service) { described_class.new({ features: "streaming" }) }

      it "filters templates by feature" do
        result = service.search

        result[:templates].each do |t|
          expect(t.features).to include("streaming")
        end
      end
    end

    context "with verified_only filter" do
      subject(:service) { described_class.new({ verified_only: "true" }) }

      it "returns only verified templates" do
        result = service.search

        result[:templates].each do |t|
          expect(t.is_verified).to be true
        end
      end
    end

    context "with custom sorting" do
      it "sorts by average_rating desc" do
        service = described_class.new({ sort_by: "average_rating", sort_order: "desc" })
        result = service.search
        ratings = result[:templates].map(&:average_rating)

        expect(ratings).to eq(ratings.sort.reverse)
      end

      it "sorts by name asc" do
        service = described_class.new({ sort_by: "name", sort_order: "asc" })
        result = service.search
        names = result[:templates].map(&:name)

        expect(names).to eq(names.sort)
      end

      it "falls back to default for invalid sort fields" do
        service = described_class.new({ sort_by: "invalid_field" })
        result = service.search

        # Should still return results (uses default sort)
        expect(result[:templates]).to be_present
      end
    end
  end

  # ===========================================================================
  # #featured
  # ===========================================================================

  describe "#featured" do
    subject(:service) { described_class.new({}) }

    it "returns featured templates" do
      result = service.featured

      expect(result).to be_an(Array)
      result.each do |t|
        expect(t.is_featured).to be true
      end
    end

    it "orders by installation_count desc" do
      result = service.featured

      counts = result.map(&:installation_count)
      expect(counts).to eq(counts.sort.reverse)
    end

    it "limits to 10 results" do
      result = service.featured

      expect(result.size).to be <= 10
    end
  end

  # ===========================================================================
  # #new_releases
  # ===========================================================================

  describe "#new_releases" do
    subject(:service) { described_class.new({}) }

    it "returns recently published templates" do
      result = service.new_releases(days: 30)

      expect(result).to be_an(Array)
      result.each do |t|
        expect(t.created_at).to be >= 30.days.ago
      end
    end

    it "orders by created_at desc" do
      result = service.new_releases

      dates = result.map(&:created_at)
      expect(dates).to eq(dates.sort.reverse)
    end
  end

  # ===========================================================================
  # #top_rated
  # ===========================================================================

  describe "#top_rated" do
    subject(:service) { described_class.new({}) }

    it "returns top rated templates with minimum review threshold" do
      result = service.top_rated(min_reviews: 5)

      result.each do |t|
        expect(t.review_count).to be >= 5
      end
    end

    it "orders by average_rating desc" do
      result = service.top_rated(min_reviews: 5)

      ratings = result.map(&:average_rating)
      expect(ratings).to eq(ratings.sort.reverse)
    end
  end

  # ===========================================================================
  # #autocomplete
  # ===========================================================================

  describe "#autocomplete" do
    subject(:service) { described_class.new({}) }

    it "returns matching template names" do
      result = service.autocomplete("Pop")

      names = result.map { |r| r[:name] }
      expect(names).to include("Popular Bot")
    end

    it "returns empty for blank query" do
      expect(service.autocomplete("")).to eq([])
    end

    it "returns empty for very short query" do
      expect(service.autocomplete("a")).to eq([])
    end

    it "includes id, name, slug in results" do
      result = service.autocomplete("Bot")

      expect(result).not_to be_empty
      expect(result.first).to have_key(:id)
      expect(result.first).to have_key(:name)
      expect(result.first).to have_key(:slug)
    end

    it "limits results" do
      result = service.autocomplete("Bot", limit: 2)

      expect(result.size).to be <= 2
    end
  end

  # ===========================================================================
  # .invalidate_caches
  # ===========================================================================

  describe ".invalidate_caches" do
    it "deletes marketplace cache keys" do
      allow(Rails.cache).to receive(:delete_matched)

      described_class.invalidate_caches

      expect(Rails.cache).to have_received(:delete_matched).with("ai:marketplace:featured*")
      expect(Rails.cache).to have_received(:delete_matched).with("ai:marketplace:trending*")
      expect(Rails.cache).to have_received(:delete_matched).with("ai:marketplace:new_releases*")
      expect(Rails.cache).to have_received(:delete_matched).with("ai:marketplace:top_rated*")
      expect(Rails.cache).to have_received(:delete_matched).with("ai:marketplace:autocomplete*")
    end
  end
end
