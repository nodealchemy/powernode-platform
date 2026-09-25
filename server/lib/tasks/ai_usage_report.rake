# frozen_string_literal: true

namespace :ai do
  desc "Token usage per model x call site over the last N days (default 7): input, cache read, cache write, " \
       "output, max_tokens stops, refusals. ACCOUNT_ID=<uuid> limits it to one account."
  task :usage_report, [ :days ] => :environment do |_task, args|
    account = ENV["ACCOUNT_ID"].presence && Account.find(ENV["ACCOUNT_ID"])
    report = Ai::UsageReportService.new(days: args[:days].presence || 7, account: account)
    rows = report.rows

    headers = %w[model call_site calls input cache_read cache_write output max_tok_stops refusals]
    table = rows.map { |row| Ai::UsageReportService::COLUMNS.map { |col| row[col].to_s } }
    totals = report.totals
    table << [ "TOTAL", "" ] + (Ai::UsageReportService::COLUMNS - %i[model call_site]).map { |col| totals[col].to_s }

    widths = headers.each_index.map { |i| ([ headers[i] ] + table.map { |r| r[i] }).map(&:length).max }
    line = ->(cells) { cells.each_with_index.map { |c, i| i < 2 ? c.ljust(widths[i]) : c.rjust(widths[i]) }.join("  ") }

    puts line.call(headers)
    puts widths.map { |w| "-" * w }.join("  ")
    table.each { |r| puts line.call(r) }
    puts "(no tracked executions in the window)" if rows.empty?
  end
end
