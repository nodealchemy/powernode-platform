# frozen_string_literal: true

require 'rails_helper'

# IMP-afe5e469cdf7 — the worker must not report to /api/v1/internal/system/operations.
#
# OperationReportingConcern PATCHed /api/v1/internal/system/operations/:id
# (status, progress) and POSTed .../events. Nothing on the server routes that
# surface: Api::V1::Internal::System::TasksController exists in the system
# extension but no routes.rb has ever drawn it, so every call would 404 and the
# concern's `rescue StandardError` would log it away.
#
# Nothing called it either. Its nine includers were the System:: jobs removed as
# dead in 6619a2653 (and NodeInstanceProvisionJob, their root, was replaced by a
# synchronous provisioning call), so the concern had no includer left and the
# PATCH never ran. Routing a controller for it would have revived a reporting
# surface with no producer, so the concern is removed instead.
#
# WHERE System::Task status and progress are reported today:
#   - the on-node agent: node_api/status/tasks/:id/{acknowledge,complete,fail,log}
#     (Api::V1::System::NodeApi::StatusController, scoped to the calling instance);
#   - stale tasks: SystemTaskReaperJob through the janitor seam,
#     worker_api/janitor/tasks and tasks/:id/reap.
RSpec.describe 'worker system-operation reporting (IMP-afe5e469cdf7)' do
  repo_root = File.expand_path('../../..', __dir__)
  sources = Dir[File.join(repo_root, 'worker/app/**/*.rb')] +
            Dir[File.join(repo_root, 'extensions/*/worker/app/**/*.rb')] +
            Dir[File.join(repo_root, 'extensions/private/*/worker/app/**/*.rb')]

  it 'has no worker code calling the unrouted internal/system/operations surface' do
    callers = sources.select { |path| File.read(path).include?('/internal/system/operations') }
                     .map { |path| path.delete_prefix("#{repo_root}/") }

    expect(callers).to be_empty,
                       'these call /api/v1/internal/system/operations, which no server route serves: ' \
                       "#{callers.join(', ')}"
  end

  it 'no longer ships OperationReportingConcern' do
    expect(defined?(OperationReportingConcern)).to be_nil
  end
end
