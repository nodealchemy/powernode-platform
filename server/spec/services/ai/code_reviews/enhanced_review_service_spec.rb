# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::CodeReviews::EnhancedReviewService, type: :service do
  let(:account) { create(:account) }

  subject(:service) { described_class.new(account: account) }

  describe '#create_review' do
    let(:task_review) { create(:ai_task_review, account: account, metadata: {}) }
    # Use a diff with only TODO (generates "warning" severity, which is valid)
    # Avoid binding.pry which generates "error" severity (not in model's SEVERITIES).
    let(:diff_text) do
      <<~DIFF
        diff --git a/app/services/example.rb b/app/services/example.rb
        --- a/app/services/example.rb
        +++ b/app/services/example.rb
        @@ -1,3 +1,4 @@
         class Example
        +  # TODO: refactor this method
         end
      DIFF
    end

    it 'creates a review with diff analysis' do
      result = service.create_review(task_review, diff_text)

      expect(result[:task_review]).to eq(task_review)
      expect(result[:analysis]).to be_a(Hash)
      expect(result[:analysis][:files_count]).to eq(1)
    end

    it 'generates review comments for detected issues' do
      result = service.create_review(task_review, diff_text)

      expect(result[:comments].size).to be >= 1
    end

    it 'updates task_review metadata with diff analysis' do
      service.create_review(task_review, diff_text)

      task_review.reload
      expect(task_review.metadata["diff_analysis"]).to be_present
      expect(task_review.metadata["diff_analysis"]["files_changed"]).to eq(1)
    end

    it 'returns a summary' do
      result = service.create_review(task_review, diff_text)

      expect(result[:summary]).to be_a(Hash)
      expect(result[:summary]).to have_key(:total_comments)
    end

    context 'with clean code (no issues)' do
      let(:clean_diff) do
        <<~DIFF
          diff --git a/app/models/user.rb b/app/models/user.rb
          --- a/app/models/user.rb
          +++ b/app/models/user.rb
          @@ -1,3 +1,4 @@
           class User < ApplicationRecord
          +  validates :email, presence: true
           end
        DIFF
      end

      it 'creates review with no comments' do
        result = service.create_review(task_review, clean_diff)
        expect(result[:comments]).to be_empty
      end
    end
  end

  describe '#add_file_comment' do
    let(:task_review) { create(:ai_task_review, account: account) }

    it 'creates a code review comment' do
      params = {
        file_path: "app/models/user.rb",
        line_start: 10,
        content: "Consider using a constant here",
        comment_type: "suggestion",
        severity: "info",
        category: "code_quality"
      }

      comment = service.add_file_comment(task_review, params)

      expect(comment).to be_persisted
      expect(comment.file_path).to eq("app/models/user.rb")
      expect(comment.line_start).to eq(10)
      expect(comment.severity).to eq("info")
    end

    it 'defaults comment_type to issue' do
      params = {
        file_path: "test.rb",
        line_start: 1,
        content: "Problem found"
      }

      comment = service.add_file_comment(task_review, params)
      expect(comment.comment_type).to eq("issue")
    end

    it 'defaults severity to warning' do
      params = {
        file_path: "test.rb",
        line_start: 1,
        content: "Problem found"
      }

      comment = service.add_file_comment(task_review, params)
      expect(comment.severity).to eq("warning")
    end

    it 'sets line_end to line_start when not provided' do
      params = {
        file_path: "test.rb",
        line_start: 5,
        content: "Issue"
      }

      comment = service.add_file_comment(task_review, params)
      expect(comment.line_end).to eq(5)
    end
  end

  describe '#resolve_comment' do
    let(:task_review) { create(:ai_task_review, account: account) }
    let(:comment) { create(:ai_code_review_comment, task_review: task_review, account: account, resolved: false) }

    it 'marks the comment as resolved' do
      result = service.resolve_comment(comment)

      expect(result.resolved).to be true
      expect(comment.reload.resolved).to be true
    end
  end

  describe '#review_summary' do
    let(:task_review) { create(:ai_task_review, account: account) }

    context 'with no comments' do
      it 'returns empty summary with 100 quality score' do
        summary = service.review_summary(task_review)

        expect(summary[:total_comments]).to eq(0)
        expect(summary[:resolved]).to eq(0)
        expect(summary[:unresolved]).to eq(0)
        expect(summary[:quality_score]).to eq(100)
        expect(summary[:recommendation]).to eq("approve")
      end
    end

    context 'with critical comments' do
      before do
        create(:ai_code_review_comment, :critical, task_review: task_review, account: account)
      end

      it 'recommends blocking' do
        summary = service.review_summary(task_review)

        expect(summary[:recommendation]).to eq("block")
        expect(summary[:severity_breakdown]["critical"]).to eq(1)
      end
    end

    # Note: the service references "error" severity but model only allows
    # critical/warning/info. This context tests the logic without DB records.
    context 'with error-level comments (stubbed)' do
      it 'recommends request_changes when error severity exists' do
        # Directly test the recommendation method logic via the summary path
        # by stubbing CodeReviewComment queries
        comments_rel = double('comments_rel')
        allow(Ai::CodeReviewComment).to receive(:where).with(
          account: account, task_review: task_review
        ).and_return(comments_rel)
        allow(comments_rel).to receive(:count).and_return(1)
        allow(comments_rel).to receive(:group).with(:severity).and_return(
          double('severity_group', count: { "error" => 1 })
        )
        allow(comments_rel).to receive(:group).with(:comment_type).and_return(
          double('type_group', count: { "issue" => 1 })
        )
        allow(comments_rel).to receive(:where).with(resolved: true).and_return(
          double('resolved_rel', count: 0)
        )

        summary = service.review_summary(task_review)
        expect(summary[:recommendation]).to eq("request_changes")
      end
    end

    context 'with only warning comments that are unresolved' do
      before do
        create(:ai_code_review_comment, task_review: task_review, account: account,
               severity: "warning", resolved: false)
      end

      it 'recommends approve_with_comments' do
        summary = service.review_summary(task_review)
        expect(summary[:recommendation]).to eq("approve_with_comments")
      end
    end

    context 'with all comments resolved' do
      before do
        create(:ai_code_review_comment, :resolved, task_review: task_review, account: account,
               severity: "info")
      end

      it 'recommends approve' do
        summary = service.review_summary(task_review)
        expect(summary[:recommendation]).to eq("approve")
      end
    end

    it 'calculates quality score based on severity' do
      # Use stubbed queries since "error" severity is not valid in the model
      comments_rel = double('comments_rel')
      allow(Ai::CodeReviewComment).to receive(:where).with(
        account: account, task_review: task_review
      ).and_return(comments_rel)
      allow(comments_rel).to receive(:count).and_return(2)
      allow(comments_rel).to receive(:group).with(:severity).and_return(
        double('severity_group', count: { "warning" => 1, "error" => 1 })
      )
      allow(comments_rel).to receive(:group).with(:comment_type).and_return(
        double('type_group', count: { "issue" => 2 })
      )
      allow(comments_rel).to receive(:where).with(resolved: true).and_return(
        double('resolved_rel', count: 0)
      )

      summary = service.review_summary(task_review)
      # 100 - (0*25 + 1*10 + 1*3) = 87
      expect(summary[:quality_score]).to eq(87)
    end
  end
end
