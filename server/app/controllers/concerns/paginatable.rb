# frozen_string_literal: true

# Paginatable Concern
# Provides standardized pagination for API controllers
# Consolidates duplicate pagination logic across controllers
#
# Usage:
#   include Paginatable
#
#   def index
#     collection = paginate(Model.all)
#     render_success(data: collection, meta: { pagination: pagination_meta })
#   end
#
# Options:
#   paginate(collection, default_per_page: 25, max_per_page: 100)
#
module Paginatable
  extend ActiveSupport::Concern

  included do
    attr_reader :pagination_state
  end

  # Paginate a collection with standardized params
  # @param collection [ActiveRecord::Relation] The collection to paginate
  # @param default_per_page [Integer] Default items per page (default: 20)
  # @param max_per_page [Integer] Maximum allowed per page (default: 100)
  # @return [ActiveRecord::Relation] Paginated collection
  def paginate(collection, default_per_page: 20, max_per_page: 100)
    page = normalize_page(params[:page])
    per_page = normalize_per_page(params[:per_page], default_per_page, max_per_page)
    offset = (page - 1) * per_page

    total_count = collection.count

    @pagination_state = {
      current_page: page,
      per_page: per_page,
      total_count: total_count,
      total_pages: (total_count / per_page.to_f).ceil,
      offset: offset
    }

    collection.limit(per_page).offset(offset)
  end

  # Generate pagination metadata for API response
  # @return [Hash] Pagination metadata
  def pagination_meta
    return {} unless @pagination_state

    {
      current_page: @pagination_state[:current_page],
      per_page: @pagination_state[:per_page],
      total_count: @pagination_state[:total_count],
      total_pages: @pagination_state[:total_pages],
      next_page: next_page,
      prev_page: prev_page
    }
  end

  private

  def normalize_page(page_param)
    [ (page_param&.to_i || 1), 1 ].max
  end

  def normalize_per_page(per_page_param, default, max)
    [ [ (per_page_param&.to_i || default), 1 ].max, max ].min
  end

  def next_page
    return nil unless @pagination_state
    return nil if @pagination_state[:current_page] >= @pagination_state[:total_pages]

    @pagination_state[:current_page] + 1
  end

  def prev_page
    return nil unless @pagination_state
    return nil if @pagination_state[:current_page] <= 1

    @pagination_state[:current_page] - 1
  end
end
