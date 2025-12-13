# frozen_string_literal: true

# Concern for enabling text search capabilities using PostgreSQL full-text search
module Searchable
  extend ActiveSupport::Concern

  included do
    # PostgreSQL full-text search support
    # Models using this concern should have a search_vector column of type tsvector
  end

  module ClassMethods
    # Search by text using PostgreSQL full-text search
    def search_by_text(query)
      return all if query.blank?

      # Use plainto_tsquery for simple text search
      # Properly quote the query parameter to prevent SQL injection
      quoted_query = connection.quote(query)
      where("search_vector @@ plainto_tsquery('english', ?)", query)
        .order(Arel.sql("ts_rank(search_vector, plainto_tsquery('english', #{quoted_query})) DESC"))
    end
  end
end
