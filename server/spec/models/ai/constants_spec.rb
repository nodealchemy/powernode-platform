# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Constants do
  describe "Statuses" do
    it "defines all expected statuses" do
      expect(Ai::Constants::Statuses::ALL).to include("pending", "completed", "failed", "cancelled")
    end

    it "has terminal statuses as subset of ALL" do
      expect(Ai::Constants::Statuses::ALL).to include(*Ai::Constants::Statuses::TERMINAL)
    end

    it "has active statuses as subset of ALL" do
      expect(Ai::Constants::Statuses::ALL).to include(*Ai::Constants::Statuses::ACTIVE)
    end

    it "terminal and active sets are disjoint" do
      intersection = Ai::Constants::Statuses::TERMINAL & Ai::Constants::Statuses::ACTIVE
      expect(intersection).to be_empty
    end

    it "all constants are frozen strings" do
      Ai::Constants::Statuses::ALL.each do |status|
        expect(status).to be_frozen
      end
    end
  end

  describe "ProviderTypes" do
    it "defines all expected providers" do
      expect(Ai::Constants::ProviderTypes::ALL).to include("openai", "anthropic", "ollama")
    end

    it "OPENAI_COMPATIBLE is subset of ALL" do
      expect(Ai::Constants::ProviderTypes::ALL).to include(*Ai::Constants::ProviderTypes::OPENAI_COMPATIBLE)
    end

    it "CHAT_CAPABLE is subset of ALL" do
      expect(Ai::Constants::ProviderTypes::ALL).to include(*Ai::Constants::ProviderTypes::CHAT_CAPABLE)
    end
  end

  describe "TrustTiers" do
    it "defines thresholds for all tiers" do
      Ai::Constants::TrustTiers::ALL.each do |tier|
        expect(Ai::Constants::TrustTiers::THRESHOLDS).to have_key(tier)
      end
    end

    it "thresholds are monotonically increasing" do
      thresholds = Ai::Constants::TrustTiers::ALL.map { |t| Ai::Constants::TrustTiers::THRESHOLDS[t] }
      expect(thresholds).to eq(thresholds.sort)
    end
  end

  describe "ModelTiers" do
    it "defines economy, standard, and premium" do
      expect(Ai::Constants::ModelTiers::ALL).to eq(%w[economy standard premium])
    end
  end

  describe "all modules" do
    it "all ALL arrays are frozen" do
      constants_modules = [
        Ai::Constants::Statuses, Ai::Constants::ProviderTypes, Ai::Constants::MemoryTiers,
        Ai::Constants::TrustTiers, Ai::Constants::TeamTopologies, Ai::Constants::CoordinationStrategies,
        Ai::Constants::NodeTypes, Ai::Constants::MessageRoles, Ai::Constants::CircuitBreakerStates,
        Ai::Constants::LearningCategories, Ai::Constants::ModelTiers, Ai::Constants::ReviewModes,
        Ai::Constants::QuarantineSeverities
      ]

      constants_modules.each do |mod|
        expect(mod::ALL).to be_frozen, "#{mod}::ALL should be frozen"
      end
    end
  end
end
