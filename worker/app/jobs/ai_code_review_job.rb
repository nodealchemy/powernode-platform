# frozen_string_literal: true

# AiCodeReviewJob - Background code review with diff analysis
# Parses diffs, generates inline comments, and creates code review artifacts
class AiCodeReviewJob < BaseJob
  sidekiq_options queue: :ai_orchestration, retry: 2

  def execute(args = {})
    @account_id = args[:account_id] || args['account_id']
    @review_id = args[:review_id] || args['review_id']
    @diff_text = args[:diff_text] || args['diff_text']

    log_info "[AiCodeReviewJob] Starting code review for review #{@review_id}"

    analysis = analyze_diff(@diff_text)

    comments = generate_comments(analysis)

    submit_comments(comments)

    log_info "[AiCodeReviewJob] Code review complete: #{comments.size} comments for review #{@review_id}"
    { review_id: @review_id, comments_count: comments.size }
  end

  private

  def analyze_diff(diff_text)
    return { files: [] } if diff_text.nil? || diff_text.to_s.empty?

    files = []
    current_file = nil

    diff_text.to_s.lines.each do |line|
      if line.start_with?('diff --git')
        file_match = line.match(%r{b/(.+)$})
        current_file = { path: file_match&.[](1) || 'unknown', changes: [] }
        files << current_file
      elsif current_file && line.start_with?('+') && !line.start_with?('+++')
        current_file[:changes] << { type: 'addition', content: line[1..] }
      elsif current_file && line.start_with?('-') && !line.start_with?('---')
        current_file[:changes] << { type: 'deletion', content: line[1..] }
      end
    end

    { files: files }
  end

  def generate_comments(analysis)
    comments = []

    (analysis[:files] || []).each do |file|
      line_num = 1
      (file[:changes] || []).each do |change|
        if change[:content]&.match?(/TODO|FIXME|HACK|XXX/i)
          comments << build_comment(file[:path], line_num, 'issue', 'warning',
            'Found TODO/FIXME marker - ensure this is addressed before merge',
            change[:content])
        end

        if change[:content]&.match?(/console\.(log|debug|info)/i)
          comments << build_comment(file[:path], line_num, 'suggestion', 'warning',
            'Console logging detected - consider removing before production',
            'Remove or replace with proper logging framework')
        end

        if change[:content]&.match?(/binding\.pry|byebug|debugger/i)
          comments << build_comment(file[:path], line_num, 'issue', 'critical',
            'Debug statement detected - must be removed before merge',
            'Remove the debug statement')
        end

        line_num += 1
      end
    end

    comments
  end

  def build_comment(file_path, line, comment_type, severity, content, suggested_fix)
    {
      file_path: file_path,
      line_start: line,
      line_end: line,
      comment_type: comment_type,
      severity: severity,
      content: content,
      suggested_fix: suggested_fix,
      category: 'automated'
    }
  end

  def submit_comments(comments)
    return if comments.empty?

    api_client.post(
      "/api/v1/internal/ai/code_reviews/#{@review_id}/comments",
      { comments: comments }
    )
  rescue StandardError => e
    log_error "[AiCodeReviewJob] Failed to submit comments", e
  end
end
