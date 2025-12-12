# frozen_string_literal: true

# SearchableController Concern
# Provides ILIKE-based search functionality for API controllers
# Consolidates duplicate search patterns across controllers
#
# Usage:
#   include SearchableController
#
#   def index
#     collection = apply_search(Model.all, :name, :description)
#     render_success(data: collection)
#   end
#
module SearchableController
  extend ActiveSupport::Concern

  # Apply ILIKE search to a collection
  # @param collection [ActiveRecord::Relation] The collection to search
  # @param columns [Array<Symbol>] Columns to search in (defaults to :name)
  # @param param_name [Symbol] Parameter name to use (default: :search)
  # @return [ActiveRecord::Relation] Filtered collection
  def apply_search(collection, *columns, param_name: :search)
    search_term = params[param_name]
    return collection if search_term.blank?

    columns = [ :name ] if columns.empty?
    search_pattern = "%#{sanitize_search_term(search_term)}%"

    if columns.length == 1
      collection.where("#{columns.first} ILIKE ?", search_pattern)
    else
      conditions = columns.map { |col| "#{col} ILIKE ?" }.join(" OR ")
      collection.where(conditions, *Array.new(columns.length, search_pattern))
    end
  end

  # Apply search with title fallback (common pattern)
  # @param collection [ActiveRecord::Relation] The collection to search
  # @param param_name [Symbol] Parameter name (default: :search)
  # @return [ActiveRecord::Relation] Filtered collection
  def apply_title_search(collection, param_name: :search)
    apply_search(collection, :title, param_name: param_name)
  end

  # Apply multi-column search (name + description)
  # @param collection [ActiveRecord::Relation] The collection to search
  # @param param_name [Symbol] Parameter name (default: :search)
  # @return [ActiveRecord::Relation] Filtered collection
  def apply_full_search(collection, param_name: :search)
    apply_search(collection, :name, :description, param_name: param_name)
  end

  private

  def sanitize_search_term(term)
    # Escape special LIKE characters
    term.to_s.gsub(/[%_\\]/) { |char| "\\#{char}" }
  end
end
