# frozen_string_literal: true

# Lightweight SQL query counter for N+1 regression specs.
#
#   count = count_queries(/\bworker_activities\b/) { get '/api/v1/workers', ... }
#
# Counts non-SCHEMA, non-cached `sql.active_record` events whose SQL matches the
# given pattern (typically a child table name). The canonical N+1 assertion is
# that this count stays constant as the number of parent rows grows.
module QueryCountHelper
  def count_queries(pattern)
    count = 0
    callback = lambda do |_name, _start, _finish, _id, payload|
      next if payload[:name] == "SCHEMA"
      next if payload[:cached]

      count += 1 if payload[:sql].to_s.match?(pattern)
    end

    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
      yield
    end

    count
  end
end

RSpec.configure do |config|
  config.include QueryCountHelper, type: :request
end
