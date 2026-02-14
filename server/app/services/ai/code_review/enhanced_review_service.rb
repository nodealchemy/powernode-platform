# frozen_string_literal: true

module Ai
  module CodeReview
    class EnhancedReviewService
      SEVERITY_LEVELS = %w[info warning critical].freeze
      COMMENT_TYPES = %w[issue suggestion praise question].freeze

      attr_reader :account

      def initialize(account:)
        @account = account
      end

      # Create a review with parsed diff and generated comments
      def create_review(task_review, diff_text)
        analyzer = DiffAnalyzerService.new
        analysis = analyzer.analyze(diff_text)

        comments = generate_review_comments(task_review, analysis)

        task_review.update!(
          metadata: (task_review.metadata || {}).merge(
            "diff_analysis" => {
              "files_changed" => analysis[:changed_files].size,
              "lines_added" => analysis[:total_additions],
              "lines_removed" => analysis[:total_deletions],
              "change_types" => analysis[:change_types]
            },
            "review_comments_count" => comments.size
          )
        )

        Rails.logger.info("Created review for task_review #{task_review.id} with #{comments.size} comments")

        {
          task_review: task_review,
          analysis: analysis,
          comments: comments,
          summary: review_summary(task_review)
        }
      end

      # Add a file-level inline comment
      def add_file_comment(task_review, params)
        comment = Ai::CodeReviewComment.create!(
          account: account,
          task_review: task_review,
          agent_id: params[:agent_id],
          file_path: params[:file_path],
          line_start: params[:line_start],
          line_end: params[:line_end] || params[:line_start],
          comment_type: params[:comment_type] || "issue",
          severity: params[:severity] || "warning",
          content: params[:content],
          suggested_fix: params[:suggested_fix],
          category: params[:category],
          metadata: params[:metadata] || {}
        )

        Rails.logger.info("Added comment on #{params[:file_path]}:#{params[:line_start]}")
        comment
      rescue ActiveRecord::RecordInvalid => e
        Rails.logger.error("Failed to add review comment: #{e.message}")
        raise
      end

      # Mark a comment as resolved
      def resolve_comment(comment)
        comment.update!(resolved: true)
        Rails.logger.info("Resolved comment #{comment.id}")
        comment
      end

      # Generate aggregated review statistics
      def review_summary(task_review)
        comments = Ai::CodeReviewComment.where(
          account: account,
          task_review: task_review
        )

        total = comments.count
        severity_breakdown = comments.group(:severity).count
        by_type = comments.group(:comment_type).count
        resolved = comments.where(resolved: true).count
        unresolved = total - resolved

        critical_count = severity_breakdown["critical"] || 0
        error_count = severity_breakdown["error"] || 0
        warning_count = severity_breakdown["warning"] || 0

        quality_score = calculate_quality_score(total, critical_count, error_count, warning_count)

        {
          total_comments: total,
          resolved: resolved,
          unresolved: unresolved,
          severity_breakdown: severity_breakdown,
          by_type: by_type,
          quality_score: quality_score,
          recommendation: review_recommendation(critical_count, error_count, unresolved)
        }
      end

      private

      def generate_review_comments(task_review, analysis)
        comments = []

        analysis[:changed_files].each do |file|
          file[:hunks].each do |hunk|
            issues = detect_common_issues(hunk, file[:file_path])
            issues.each do |issue|
              comment = add_file_comment(task_review, issue)
              comments << comment
            end
          end
        end

        comments
      end

      def detect_common_issues(hunk, file_path)
        issues = []
        added_lines = hunk[:added_lines] || []

        added_lines.each do |line_info|
          line = line_info[:content] || ""
          line_num = line_info[:line_number]

          # Detect common patterns
          if line.match?(/TODO|FIXME|HACK|XXX/i)
            issues << build_issue(file_path, line_num, "issue", "warning", "TODO/FIXME marker found", "code_quality")
          end

          if line.match?(/binding\.pry|debugger|byebug|console\.log/)
            issues << build_issue(file_path, line_num, "issue", "warning", "Debug statement detected", "code_quality")
          end

          if line.match?(/password|secret|api_key/i) && line.match?(/[=:].*['"][^'"]+['"]/)
            issues << build_issue(file_path, line_num, "issue", "critical", "Possible hardcoded secret", "security")
          end
        end

        issues
      end

      def build_issue(file_path, line_num, type, severity, content, category)
        {
          file_path: file_path,
          line_start: line_num,
          comment_type: type,
          severity: severity,
          content: content,
          category: category
        }
      end

      def calculate_quality_score(total, critical, errors, warnings)
        return 100 if total.zero?

        deductions = critical * 25 + errors * 10 + warnings * 3
        [100 - deductions, 0].max
      end

      def review_recommendation(critical_count, error_count, unresolved)
        return "block" if critical_count > 0
        return "request_changes" if error_count > 0
        return "approve_with_comments" if unresolved > 0

        "approve"
      end
    end
  end
end
