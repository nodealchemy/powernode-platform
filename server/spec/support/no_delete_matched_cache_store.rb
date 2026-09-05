# frozen_string_literal: true

# IMP-63a7d2f99c56. The test environment's cache store is MemoryStore
# (config/environments/test.rb), which DOES implement #delete_matched — so a
# spec run against Rails.cache as configured for tests cannot see the defect
# this task fixes (the production default, solid_cache, does not implement
# it; ActiveSupport::Cache::Store#delete_matched raises NotImplementedError,
# which is NOT a StandardError and so is not caught by `rescue StandardError`).
#
# This store reproduces exactly that one property — everything else (read,
# write, fetch, increment, delete) behaves like the in-memory store specs
# already rely on, so it can stand in for `Rails.cache` in an example without
# breaking the surrounding service's other cache usage.
class NoDeleteMatchedCacheStore < ActiveSupport::Cache::MemoryStore
  def delete_matched(*)
    raise NotImplementedError, "#{self.class.name} does not support delete_matched"
  end
end
