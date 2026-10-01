# frozen_string_literal: true

require 'rails_helper'

# Drift guard (IMP-ca3551dd27be). Compliance::DataDeletionJob walks its own
# DELETABLE_DATA_TYPES on a 'full' deletion and honours data_types_to_retain
# for each member. The authoritative list is the server's
# DataManagement::DeletionRequest::DELETABLE_DATA_TYPES — what the platform
# ADVERTISES as erasable and validates requests against. The worker cannot
# load server code, so the server constant is read here as SOURCE TEXT. A
# server type missing from the worker list would never be erased on a full
# deletion; a worker type missing from the server list would be walked for a
# category the platform does not offer. A constant that cannot be found, or
# is not one %w[] literal, fails loudly rather than passing on a comparison
# it never made.
RSpec.describe 'Compliance::DataDeletionJob::DELETABLE_DATA_TYPES drift guard' do
  let(:repo_root) { File.expand_path('../../../..', __dir__) }
  let(:server_model) { 'server/app/models/data_management/deletion_request.rb' }

  def word_array_constant(relative_path, name)
    path = File.join(repo_root, relative_path)
    expect(File.file?(path)).to be(true), "drift guard: #{relative_path} not found under #{repo_root}"

    matches = File.read(path).scan(/^\s*#{name}\s*=\s*%w\[([^\]]*)\]/m).flatten
    expect(matches.size).to eq(1),
                            "drift guard: expected one #{name} = %w[...] literal in #{relative_path}, found #{matches.size}"
    matches.first.split
  end

  it 'keeps the worker list holding exactly the server list types' do
    server = word_array_constant(server_model, 'DELETABLE_DATA_TYPES')

    worker = Compliance::DataDeletionJob::DELETABLE_DATA_TYPES

    # Order-insensitive: a harmless reorder on either side is not drift. Set
    # membership still fails closed — a type missing on either side, a
    # duplicate, or an empty parse all redden.
    expect(server).not_to be_empty
    expect(server.uniq.size).to eq(server.size), "drift guard: duplicate entry in the server list #{server.inspect}"
    expect(worker.uniq.size).to eq(worker.size), "drift guard: duplicate entry in the worker list #{worker.inspect}"
    expect(worker.sort).to eq(server.sort),
                           "worker DELETABLE_DATA_TYPES #{worker.inspect} must hold the same types as the server's #{server.inspect}"
  end
end
