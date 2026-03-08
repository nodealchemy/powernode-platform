# frozen_string_literal: true

module Ai
  module Tools
    module Concerns
      module TradingContextResolvable
        extend ActiveSupport::Concern

        private

        def require_trading!
          unless defined?(::Trading)
            raise "Trading extension is not loaded"
          end
        end

        def resolve_portfolio
          account.trading_portfolio ||
            raise(ActiveRecord::RecordNotFound, "No trading portfolio found")
        end

        def resolve_strategy(identifier)
          portfolio = resolve_portfolio
          portfolio.strategies.find_by(id: identifier) ||
            portfolio.strategies.find_by(name: identifier) ||
            raise(ActiveRecord::RecordNotFound, "Strategy not found: #{identifier}")
        end

        def resolve_venue(identifier)
          Trading::Venue.find_by(id: identifier) ||
            Trading::Venue.find_by(slug: identifier) ||
            Trading::Venue.find_by(name: identifier) ||
            raise(ActiveRecord::RecordNotFound, "Venue not found: #{identifier}")
        end

        def resolve_simulation(identifier)
          portfolio = resolve_portfolio
          portfolio.simulations.find_by(id: identifier) ||
            raise(ActiveRecord::RecordNotFound, "Simulation not found: #{identifier}")
        end

        def resolve_position(identifier)
          portfolio = resolve_portfolio
          Trading::Position.joins(:strategy)
            .where(trading_strategies: { trading_portfolio_id: portfolio.id })
            .find_by(id: identifier) ||
            raise(ActiveRecord::RecordNotFound, "Position not found: #{identifier}")
        end

        def resolve_order(identifier)
          portfolio = resolve_portfolio
          Trading::Order.joins(:strategy)
            .where(trading_strategies: { trading_portfolio_id: portfolio.id })
            .find_by(id: identifier) ||
            raise(ActiveRecord::RecordNotFound, "Order not found: #{identifier}")
        end

        def resolve_training_session(identifier)
          Trading::TrainingSession.where(account_id: account.id)
            .find_by(id: identifier) ||
            raise(ActiveRecord::RecordNotFound, "Training session not found: #{identifier}")
        end

        def resolve_epoch(identifier)
          portfolio = resolve_portfolio
          portfolio.evolution_epochs.find_by(id: identifier) ||
            raise(ActiveRecord::RecordNotFound, "Evolution epoch not found: #{identifier}")
        end
      end
    end
  end
end
