# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Marketplace::TemplateDiscoveryService do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:service) { described_class.new(account: account, user: user) }

  # Create public templates for discovery
  let!(:automation_template) do
    create(:ai_workflow_template, :published,
           name: "Auto Workflow",
           category: "automation",
           difficulty_level: "beginner",
           rating: 4.5,
           rating_count: 20,
           usage_count: 150,
           tags: ["automation", "ai"],
           metadata: { "complexity_score" => 25, "has_ai_agents" => true })
  end

  let!(:analytics_template) do
    create(:ai_workflow_template, :published,
           name: "Analytics Pipeline",
           category: "analytics",
           difficulty_level: "intermediate",
           rating: 3.8,
           rating_count: 10,
           usage_count: 80,
           tags: ["analytics", "data"],
           metadata: { "complexity_score" => 50, "has_webhooks" => true })
  end

  let!(:integration_template) do
    create(:ai_workflow_template, :published,
           name: "API Integration",
           category: "integration",
           difficulty_level: "advanced",
           rating: 4.2,
           rating_count: 15,
           usage_count: 200,
           tags: ["integration", "api"],
           metadata: { "complexity_score" => 75, "has_schedules" => true })
  end

  describe "#initialize" do
    it "sets account and user" do
      expect(service.account).to eq(account)
      expect(service.user).to eq(user)
    end

    it "allows nil user" do
      s = described_class.new(account: account)
      expect(s.user).to be_nil
    end
  end

  describe "constants" do
    it "defines DEFAULT_LIMIT" do
      expect(described_class::DEFAULT_LIMIT).to eq(20)
    end

    it "defines MAX_LIMIT" do
      expect(described_class::MAX_LIMIT).to eq(100)
    end

    it "defines CATEGORIES" do
      expect(described_class::CATEGORIES).to include("automation", "analytics", "integration")
    end

    it "defines DIFFICULTY_LEVELS" do
      expect(described_class::DIFFICULTY_LEVELS).to eq(%w[beginner intermediate advanced expert])
    end
  end

  describe "#discover" do
    it "returns templates and total_count" do
      result = service.discover
      expect(result[:templates]).to be_present
      expect(result[:total_count]).to be >= 3
    end

    it "filters by category" do
      result = service.discover(category: "automation")
      expect(result[:templates].map(&:category).uniq).to eq(["automation"])
    end

    it "filters by difficulty" do
      result = service.discover(difficulty: "beginner")
      result[:templates].each do |t|
        expect(t.difficulty_level).to eq("beginner")
      end
    end

    it "filters by featured" do
      automation_template.update!(is_featured: true)
      result = service.discover(featured: true)
      expect(result[:templates]).to include(automation_template)
    end

    it "filters highly rated" do
      result = service.discover(highly_rated: true)
      result[:templates].each do |t|
        expect(t.rating).to be >= 4.0
      end
    end

    it "respects limit parameter" do
      result = service.discover(limit: 2)
      expect(result[:templates].size).to be <= 2
    end

    it "caps limit at MAX_LIMIT" do
      result = service.discover(limit: 200)
      expect(result[:templates].size).to be <= 100
    end

    it "supports offset for pagination" do
      all_results = service.discover(limit: 100)
      offset_results = service.discover(limit: 1, offset: 1)
      if all_results[:total_count] > 1
        expect(offset_results[:templates].first.id).not_to eq(all_results[:templates].first.id)
      end
    end

    describe "sorting" do
      it "sorts by popularity" do
        result = service.discover(sort_by: "popularity")
        counts = result[:templates].map(&:usage_count)
        expect(counts).to eq(counts.sort.reverse)
      end

      it "sorts by rating" do
        result = service.discover(sort_by: "rating")
        ratings = result[:templates].map(&:rating)
        expect(ratings).to eq(ratings.sort.reverse)
      end

      it "sorts by recent" do
        result = service.discover(sort_by: "recent")
        dates = result[:templates].map(&:created_at)
        expect(dates).to eq(dates.sort.reverse)
      end

      it "sorts by name" do
        result = service.discover(sort_by: "name")
        names = result[:templates].map(&:name)
        # PostgreSQL ORDER BY uses locale-aware collation, verify order matches DB sort
        db_sorted = Ai::WorkflowTemplate.where(id: result[:templates].map(&:id)).order(:name).pluck(:name)
        expect(names).to eq(db_sorted)
      end

      it "defaults to usage_count desc" do
        result = service.discover
        counts = result[:templates].map(&:usage_count)
        expect(counts).to eq(counts.sort.reverse)
      end
    end

    it "includes recommendations when requested" do
      result = service.discover(include_recommendations: true)
      expect(result).to have_key(:recommendations)
    end
  end

  describe "#advanced_search" do
    it "searches by query text (name)" do
      result = service.advanced_search(query: "Auto")
      expect(result[:templates]).to include(automation_template)
    end

    it "searches by query text (description)" do
      result = service.advanced_search(query: automation_template.description.first(10))
      expect(result[:templates]).to include(automation_template)
    end

    it "filters by categories array" do
      result = service.advanced_search(categories: ["automation", "analytics"])
      result[:templates].each do |t|
        expect(["automation", "analytics"]).to include(t.category)
      end
    end

    it "filters by difficulty_levels array" do
      result = service.advanced_search(difficulty_levels: ["beginner"])
      result[:templates].each do |t|
        expect(t.difficulty_level).to eq("beginner")
      end
    end

    it "filters by min_rating" do
      result = service.advanced_search(min_rating: 4.0)
      result[:templates].each do |t|
        expect(t.rating).to be >= 4.0
      end
    end

    it "filters by min_usage" do
      result = service.advanced_search(min_usage: 100)
      result[:templates].each do |t|
        expect(t.usage_count).to be >= 100
      end
    end

    it "returns total_count" do
      result = service.advanced_search(query: "Auto")
      expect(result[:total_count]).to be >= 1
    end

    it "returns search suggestions" do
      result = service.advanced_search(query: "auto")
      expect(result[:suggestions]).to be_an(Array)
    end

    it "limits results to MAX_LIMIT" do
      result = service.advanced_search
      expect(result[:templates].size).to be <= 100
    end
  end

  describe "#get_recommendations" do
    it "returns empty array when account is nil" do
      s = described_class.new(account: nil)
      expect(s.get_recommendations).to eq([])
    end

    it "returns recommendations based on account categories" do
      # Create a workflow with matching category so recommendations work
      create(:ai_workflow, account: account, metadata: { "category" => "automation" })

      recs = service.get_recommendations(limit: 5)
      expect(recs).to be_an(Array)
    end

    it "excludes already-installed templates" do
      # Install automation_template
      create(:marketplace_subscription,
             account: account,
             subscribable: automation_template)

      recs = service.get_recommendations(limit: 10)
      rec_template_ids = recs.map { |r| r[:template].id }
      expect(rec_template_ids).not_to include(automation_template.id)
    end

    it "includes recommendation_score and reasons" do
      create(:ai_workflow, account: account, metadata: { "category" => "automation" })

      recs = service.get_recommendations(limit: 5)
      next unless recs.any?

      rec = recs.first
      expect(rec).to have_key(:recommendation_score)
      expect(rec).to have_key(:recommendation_reasons)
      expect(rec[:recommendation_reasons]).to be_an(Array)
    end

    it "fills with popular templates when insufficient category matches" do
      recs = service.get_recommendations(limit: 10)
      expect(recs).to be_an(Array)
    end

    it "respects the limit parameter" do
      recs = service.get_recommendations(limit: 2)
      expect(recs.size).to be <= 2
    end

    it "sorts by recommendation_score descending" do
      create(:ai_workflow, account: account, metadata: { "category" => "automation" })

      recs = service.get_recommendations(limit: 10)
      scores = recs.map { |r| r[:recommendation_score] }
      expect(scores).to eq(scores.sort.reverse)
    end
  end

  describe "#compare_templates" do
    it "returns comparison data for given templates" do
      result = service.compare_templates([automation_template.id, analytics_template.id])
      expect(result[:templates].size).to eq(2)
    end

    it "includes comparison matrix" do
      result = service.compare_templates([automation_template.id, integration_template.id])
      expect(result[:comparison_matrix]).to have_key(:ratings)
      expect(result[:comparison_matrix]).to have_key(:usage)
      expect(result[:comparison_matrix]).to have_key(:complexity)
      expect(result[:comparison_matrix]).to have_key(:node_count)
    end

    it "includes a recommendation" do
      result = service.compare_templates([automation_template.id, analytics_template.id])
      expect(result[:recommendation]).to be_present
      expect(result[:recommendation]).to have_key(:recommended_id)
      expect(result[:recommendation]).to have_key(:reason)
    end

    it "serializes template details" do
      result = service.compare_templates([automation_template.id])
      t = result[:templates].first
      expect(t[:id]).to eq(automation_template.id)
      expect(t[:name]).to eq(automation_template.name)
      expect(t[:category]).to eq("automation")
      expect(t[:rating]).to eq(4.5)
    end

    it "handles empty template_ids" do
      result = service.compare_templates([])
      expect(result[:templates]).to be_empty
      expect(result[:recommendation]).to be_nil
    end
  end

  describe "#explore_categories" do
    it "returns category data with counts" do
      categories = service.explore_categories
      expect(categories).to be_an(Array)
      expect(categories.first).to have_key(:name)
      expect(categories.first).to have_key(:count)
      expect(categories.first).to have_key(:display_name)
      expect(categories.first).to have_key(:description)
    end

    it "includes featured_templates for each category" do
      categories = service.explore_categories
      automation = categories.find { |c| c[:name] == "automation" }
      expect(automation[:featured_templates]).to be_an(Array)
    end

    it "sorts by count descending" do
      categories = service.explore_categories
      counts = categories.map { |c| c[:count] }
      expect(counts).to eq(counts.sort.reverse)
    end

    it "includes all defined CATEGORIES" do
      categories = service.explore_categories
      category_names = categories.map { |c| c[:name] }
      described_class::CATEGORIES.each do |cat|
        expect(category_names).to include(cat)
      end
    end
  end

  describe "#explore_tags" do
    it "returns tag data with counts" do
      tags = service.explore_tags
      expect(tags).to be_an(Array)
      next unless tags.any?

      expect(tags.first).to have_key(:name)
      expect(tags.first).to have_key(:count)
    end

    it "limits to 50 tags" do
      tags = service.explore_tags
      expect(tags.size).to be <= 50
    end

    it "includes related tags" do
      tags = service.explore_tags
      next unless tags.any?

      expect(tags.first).to have_key(:related_tags)
      expect(tags.first[:related_tags]).to be_an(Array)
    end
  end

  describe "#marketplace_statistics" do
    it "returns total_templates" do
      stats = service.marketplace_statistics
      expect(stats[:total_templates]).to be >= 3
    end

    it "returns total_installs" do
      stats = service.marketplace_statistics
      expect(stats[:total_installs]).to be_a(Numeric)
    end

    it "returns average_rating" do
      stats = service.marketplace_statistics
      expect(stats[:average_rating]).to be_present
    end

    it "returns templates_by_category breakdown" do
      stats = service.marketplace_statistics
      expect(stats[:templates_by_category]).to be_a(Hash)
      expect(stats[:templates_by_category]).to have_key("automation")
    end

    it "returns templates_by_difficulty breakdown" do
      stats = service.marketplace_statistics
      expect(stats[:templates_by_difficulty]).to be_a(Hash)
    end

    it "returns new_this_week and new_this_month counts" do
      stats = service.marketplace_statistics
      expect(stats[:new_this_week]).to be_a(Numeric)
      expect(stats[:new_this_month]).to be_a(Numeric)
    end

    it "returns top_categories" do
      stats = service.marketplace_statistics
      expect(stats[:top_categories]).to be_a(Hash)
    end

    it "returns trending_tags" do
      stats = service.marketplace_statistics
      expect(stats[:trending_tags]).to be_a(Hash)
    end
  end

  describe "#template_analytics" do
    it "returns analytics for a template" do
      result = service.template_analytics(automation_template.id)
      expect(result[:total_installs]).to eq(automation_template.usage_count)
      expect(result[:total_ratings]).to eq(automation_template.rating_count)
      expect(result[:average_rating]).to eq(automation_template.rating)
    end

    it "includes install counts by timeframe" do
      result = service.template_analytics(automation_template.id)
      expect(result).to have_key(:installs_this_week)
      expect(result).to have_key(:installs_this_month)
      expect(result).to have_key(:installs_by_day)
    end

    it "includes category_rank" do
      result = service.template_analytics(automation_template.id)
      expect(result[:category_rank]).to be_a(Integer)
    end

    it "includes similar_templates" do
      result = service.template_analytics(automation_template.id)
      expect(result[:similar_templates]).to be_an(Array)
    end

    it "raises RecordNotFound for invalid template" do
      expect {
        service.template_analytics(SecureRandom.uuid)
      }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end

  describe "#featured_templates" do
    before do
      automation_template.update!(is_featured: true)
    end

    it "returns featured public templates" do
      result = service.featured_templates(limit: 10)
      result.each do |t|
        expect(t.is_featured).to be true
        expect(t.is_public).to be true
      end
    end

    it "orders by rating then usage_count" do
      result = service.featured_templates(limit: 10)
      ratings = result.map(&:rating)
      expect(ratings).to eq(ratings.sort.reverse)
    end

    it "respects limit" do
      result = service.featured_templates(limit: 1)
      expect(result.size).to be <= 1
    end
  end

  describe "#popular_templates" do
    it "returns public templates ordered by usage_count" do
      result = service.popular_templates(limit: 10)
      counts = result.map(&:usage_count)
      expect(counts).to eq(counts.sort.reverse)
    end

    it "respects limit" do
      result = service.popular_templates(limit: 1)
      expect(result.size).to be <= 1
    end
  end
end
