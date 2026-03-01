# frozen_string_literal: true

class AddCodeReviewFieldsToAiTaskReviews < ActiveRecord::Migration[8.0]
  def change
    add_column :ai_task_reviews, :diff_analysis, :jsonb, default: {}
    add_column :ai_task_reviews, :file_comments, :jsonb, default: {}
    add_column :ai_task_reviews, :code_suggestions, :jsonb, default: {}
    add_column :ai_task_reviews, :repository_url, :string
    add_column :ai_task_reviews, :commit_sha, :string
    add_column :ai_task_reviews, :pull_request_number, :integer
  end
end
