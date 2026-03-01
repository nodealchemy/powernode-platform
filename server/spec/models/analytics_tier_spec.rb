# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AnalyticsTier, type: :model do
  describe 'validations' do
    subject { build(:analytics_tier, slug: 'free') }

    it { should validate_presence_of(:name) }
    it { should validate_length_of(:name).is_at_least(2).is_at_most(50) }
    it { should validate_presence_of(:slug) }
    it { should validate_inclusion_of(:slug).in_array(%w[free starter pro enterprise]) }
    it { should validate_numericality_of(:monthly_price).is_greater_than_or_equal_to(0) }
    it { should validate_numericality_of(:retention_days).is_greater_than_or_equal_to(-1) }
    it { should validate_numericality_of(:cohort_months).is_greater_than_or_equal_to(-1) }
    it { should validate_numericality_of(:api_calls_per_day).is_greater_than_or_equal_to(0) }

    it 'validates uniqueness of slug' do
      create(:analytics_tier, :free)
      tier = build(:analytics_tier, slug: 'free')
      expect(tier).not_to be_valid
      expect(tier.errors[:slug]).to include('has already been taken')
    end
  end

  describe 'scopes' do
    let!(:active_tier) { create(:analytics_tier, :free, is_active: true) }
    let!(:inactive_tier) { create(:analytics_tier, :starter, is_active: false) }

    describe '.active' do
      it 'returns only active tiers' do
        expect(AnalyticsTier.active).to include(active_tier)
        expect(AnalyticsTier.active).not_to include(inactive_tier)
      end
    end

    describe '.ordered' do
      let!(:tier_high) { create(:analytics_tier, :pro, sort_order: 10) }
      let!(:tier_low) { create(:analytics_tier, :enterprise, sort_order: 1) }

      it 'returns tiers ordered by sort_order ascending' do
        ordered = AnalyticsTier.ordered
        expect(ordered.index(tier_low)).to be < ordered.index(tier_high)
      end
    end
  end

  describe 'class methods' do
    before do
      create(:analytics_tier, :free)
      create(:analytics_tier, :starter)
      create(:analytics_tier, :pro)
      create(:analytics_tier, :enterprise)
    end

    describe '.free' do
      it 'returns the free tier' do
        expect(AnalyticsTier.free.slug).to eq('free')
      end
    end

    describe '.starter' do
      it 'returns the starter tier' do
        expect(AnalyticsTier.starter.slug).to eq('starter')
      end
    end

    describe '.pro' do
      it 'returns the pro tier' do
        expect(AnalyticsTier.pro.slug).to eq('pro')
      end
    end

    describe '.enterprise' do
      it 'returns the enterprise tier' do
        expect(AnalyticsTier.enterprise.slug).to eq('enterprise')
      end
    end

    describe '.for_comparison' do
      it 'returns comparison data for active tiers' do
        data = AnalyticsTier.for_comparison
        expect(data).to be_an(Array)
        expect(data.first).to have_key(:id)
        expect(data.first).to have_key(:features)
      end
    end
  end

  describe 'instance methods' do
    describe '#free?' do
      it 'returns true for free tier' do
        tier = build(:analytics_tier, :free)
        expect(tier.free?).to be true
      end

      it 'returns false for non-free tier' do
        tier = build(:analytics_tier, :pro)
        expect(tier.free?).to be false
      end
    end

    describe '#unlimited_retention?' do
      it 'returns true when retention_days is -1' do
        tier = build(:analytics_tier, retention_days: -1)
        expect(tier.unlimited_retention?).to be true
      end

      it 'returns false when retention_days is positive' do
        tier = build(:analytics_tier, retention_days: 30)
        expect(tier.unlimited_retention?).to be false
      end
    end

    describe '#unlimited_cohorts?' do
      it 'returns true when cohort_months is -1' do
        tier = build(:analytics_tier, cohort_months: -1)
        expect(tier.unlimited_cohorts?).to be true
      end

      it 'returns false when cohort_months is positive' do
        tier = build(:analytics_tier, cohort_months: 3)
        expect(tier.unlimited_cohorts?).to be false
      end
    end

    describe '#unlimited_api_calls?' do
      it 'returns true when api_calls_per_day is 0' do
        tier = build(:analytics_tier, api_calls_per_day: 0)
        expect(tier.unlimited_api_calls?).to be true
      end

      it 'returns true when api_calls_per_day exceeds 100000' do
        tier = build(:analytics_tier, api_calls_per_day: 200_000)
        expect(tier.unlimited_api_calls?).to be true
      end

      it 'returns false when api_calls_per_day is within limit' do
        tier = build(:analytics_tier, api_calls_per_day: 1000)
        expect(tier.unlimited_api_calls?).to be false
      end
    end

    describe '#has_feature?' do
      let(:tier) { build(:analytics_tier, csv_export: true, api_access: false, features: { 'custom_feature' => true }) }

      it 'returns feature value for known features' do
        expect(tier.has_feature?(:csv_export)).to be true
        expect(tier.has_feature?(:api_access)).to be false
      end

      it 'checks features hash for unknown features' do
        expect(tier.has_feature?('custom_feature')).to be true
        expect(tier.has_feature?('unknown')).to be false
      end
    end

    describe '#retention_display' do
      it 'returns "Unlimited" for unlimited retention' do
        tier = build(:analytics_tier, retention_days: -1)
        expect(tier.retention_display).to eq('Unlimited')
      end

      it 'returns formatted days for limited retention' do
        tier = build(:analytics_tier, retention_days: 30)
        expect(tier.retention_display).to eq('30 days')
      end
    end

    describe '#cohort_display' do
      it 'returns "N/A" when cohort_months is 0' do
        tier = build(:analytics_tier, cohort_months: 0)
        expect(tier.cohort_display).to eq('N/A')
      end

      it 'returns "Unlimited" for unlimited cohorts' do
        tier = build(:analytics_tier, cohort_months: -1)
        expect(tier.cohort_display).to eq('Unlimited')
      end

      it 'returns formatted months for limited cohorts' do
        tier = build(:analytics_tier, cohort_months: 12)
        expect(tier.cohort_display).to eq('12 months')
      end
    end

    describe '#price_display' do
      it 'returns "Free" when monthly_price is zero' do
        tier = build(:analytics_tier, monthly_price: 0)
        expect(tier.price_display).to eq('Free')
      end

      it 'returns formatted price for non-zero' do
        tier = build(:analytics_tier, monthly_price: 29)
        expect(tier.price_display).to eq('$29/mo')
      end
    end

    describe '#comparison_data' do
      let(:tier) { create(:analytics_tier, :pro) }

      it 'returns hash with expected keys' do
        data = tier.comparison_data
        expect(data).to have_key(:id)
        expect(data).to have_key(:name)
        expect(data).to have_key(:slug)
        expect(data).to have_key(:features)
        expect(data).to have_key(:is_popular)
      end

      it 'marks pro tier as popular' do
        expect(tier.comparison_data[:is_popular]).to be true
      end
    end

    describe '#summary' do
      let(:tier) { create(:analytics_tier, :starter) }

      it 'returns hash with expected keys' do
        summary = tier.summary
        expect(summary).to have_key(:id)
        expect(summary).to have_key(:name)
        expect(summary).to have_key(:slug)
        expect(summary).to have_key(:monthly_price)
        expect(summary).to have_key(:retention_days)
      end
    end
  end
end
