# frozen_string_literal: true

require 'spec_helper'
require 'open3'
require 'tmpdir'

# Regression for IMP-d40a58733850: an executor sourced the unit env (RAILS_ENV=development
# + DATABASE_*) and ran rspec; rails_helper kept development and before(:suite) deleted every
# row of the dev database. These specs spawn rspec as a subprocess pointed ONLY at a database
# that does not exist, so the guard must abort before any connection (no DELETE can run).
RSpec.describe 'rails_helper environment guard' do
  PROBE_DB = 'powernode_guard_probe_nonexistent'
  SERVER_ROOT = File.expand_path('../..', __dir__)

  def run_probe(env)
    Dir.mktmpdir('env-guard') do |dir|
      probe = File.join(dir, 'probe_spec.rb')
      File.write(probe, <<~RUBY)
        require 'rails_helper'
        RSpec.describe 'probe' do
          it('runs') { expect(1).to eq(1) }
        end
      RUBY
      base = { 'RAILS_ENV' => nil, 'RACK_ENV' => nil, 'DATABASE_URL' => nil,
               'DATABASE_NAME' => nil, 'TEST_ENV_NUMBER' => nil }
      out, status = Bundler.with_unbundled_env do
        Open3.capture2e(base.merge(env), 'bundle', 'exec', 'rspec', probe, chdir: SERVER_ROOT)
      end
      [ out, status ]
    end
  end

  it 'refuses RAILS_ENV=development before touching any database' do
    out, status = run_probe('RAILS_ENV' => 'development', 'DATABASE_NAME' => PROBE_DB)
    expect(status.exitstatus).not_to eq(0)
    expect(out).to include('rspec refuses RAILS_ENV=development')
    expect(out).not_to match(/DELETE FROM|PG::ConnectionBad|does not exist/)
  end

  it 'refuses RACK_ENV=development when RAILS_ENV is unset' do
    out, status = run_probe('RACK_ENV' => 'development', 'DATABASE_NAME' => PROBE_DB)
    expect(status.exitstatus).not_to eq(0)
    expect(out).to include('rspec refuses RACK_ENV=development')
    expect(out).not_to match(/DELETE FROM|PG::ConnectionBad|does not exist/)
  end

  it 'refuses a non-test database name even when RAILS_ENV=test' do
    out, status = run_probe('RAILS_ENV' => 'test',
                            'DATABASE_URL' => "postgres://localhost:5432/#{PROBE_DB}")
    expect(status.exitstatus).not_to eq(0)
    expect(out).to include('rspec refuses database')
    expect(out).to include(PROBE_DB)
    expect(out).not_to match(/DELETE FROM|PG::ConnectionBad|does not exist/)
  end
end
