# frozen_string_literal: true

require 'rails_helper'
require_relative '../../../app/services/mcp/stdio_concurrency_limiter'

# IMP-ecc0e18c0455 — the process-wide cap on concurrent synchronous stdio
# MCP executions in worker-web. The request-level behaviour (503, release on
# every exit path) is covered in spec/controllers/jobs_controller_spec.rb;
# this file pins the counter itself and how the cap is resolved from ENV.
RSpec.describe Mcp::StdioConcurrencyLimiter do
  describe '#try_acquire / #release' do
    subject(:limiter) { described_class.new(limit: 2) }

    it 'admits up to the limit and refuses the next, without blocking' do
      expect(limiter.try_acquire).to be(true)
      expect(limiter.try_acquire).to be(true)
      expect(limiter.try_acquire).to be(false)
      expect(limiter.in_flight).to eq(2)
    end

    it 'admits again once a slot is released' do
      2.times { limiter.try_acquire }
      limiter.release

      expect(limiter.in_flight).to eq(1)
      expect(limiter.try_acquire).to be(true)
      expect(limiter.try_acquire).to be(false)
    end

    it 'counts refusals, and only refusals' do
      2.times { limiter.try_acquire }
      3.times { limiter.try_acquire }

      expect(limiter.rejected_total).to eq(3)
    end

    it 'never lets an unpaired release push the count below zero' do
      limiter.release

      expect(limiter.in_flight).to eq(0)
      2.times { limiter.try_acquire }
      expect(limiter.try_acquire).to be(false)
    end

    # Deterministic: every thread parks on the gate until all are started,
    # so the acquires genuinely contend; no sleeps.
    it 'never admits more than the limit under contention' do
      limiter = described_class.new(limit: 3)
      gate = Thread::Queue.new
      threads = Array.new(20) do
        Thread.new do
          gate.pop
          limiter.try_acquire
        end
      end
      20.times { gate << :go }

      results = threads.map(&:value)

      expect(results.count(true)).to eq(3)
      expect(limiter.in_flight).to eq(3)
      expect(limiter.rejected_total).to eq(17)
    end

    [ 0, -1, nil, '2', 1.5 ].each do |bad|
      it "refuses to be built with limit #{bad.inspect}" do
        expect { described_class.new(limit: bad) }.to raise_error(ArgumentError)
      end
    end
  end

  describe '.resolve_limit' do
    let(:logger) { instance_double(Logger, warn: nil) }

    def resolve(env)
      described_class.resolve_limit(env: env, logger: logger)
    end

    it 'defaults to DEFAULT_LIMIT, silently, when the variable is unset' do
      expect(resolve({})).to eq(described_class::DEFAULT_LIMIT)
      expect(logger).not_to have_received(:warn)
    end

    it 'keeps the default at no more than half the default thread pool' do
      expect(described_class::DEFAULT_LIMIT).to be <= described_class::DEFAULT_WEB_THREADS / 2
    end

    it 'treats a blank value as unset' do
      expect(resolve('MCP_STDIO_MAX_CONCURRENCY' => '  ')).to eq(described_class::DEFAULT_LIMIT)
      expect(logger).not_to have_received(:warn)
    end

    it 'honours a positive integer within the ceiling' do
      expect(resolve('MCP_STDIO_MAX_CONCURRENCY' => '3')).to eq(3)
      expect(resolve('MCP_STDIO_MAX_CONCURRENCY' => ' 12 ')).to eq(12)
      expect(logger).not_to have_received(:warn)
    end

    it 'reads the value as decimal, never octal' do
      expect(resolve('MCP_STDIO_MAX_CONCURRENCY' => '010')).to eq(10)
    end

    %w[abc 4.5 0 -2 0x8 4threads].each do |bad|
      it "falls back to the default, with a warning, for #{bad.inspect}" do
        expect(resolve('MCP_STDIO_MAX_CONCURRENCY' => bad)).to eq(described_class::DEFAULT_LIMIT)
        expect(logger).to have_received(:warn).with(/MCP_STDIO_MAX_CONCURRENCY/).once
      end
    end

    it 'never echoes the rejected value into the log' do
      resolve('MCP_STDIO_MAX_CONCURRENCY' => 'not-a-number-s3cret')

      expect(logger).to have_received(:warn) { |msg| expect(msg).not_to include('s3cret') }
    end

    # A cap at or above the thread pool is no cap at all: every thread could
    # still be held by stdio MCP calls. The ceiling keeps RESERVED_WEB_THREADS
    # of the pool for everything else worker-web serves.
    it 'clamps a value above the ceiling of the default pool, with a warning' do
      ceiling = described_class::DEFAULT_WEB_THREADS - described_class::RESERVED_WEB_THREADS

      expect(resolve('MCP_STDIO_MAX_CONCURRENCY' => '13')).to eq(ceiling)
      expect(resolve('MCP_STDIO_MAX_CONCURRENCY' => '500')).to eq(ceiling)
      expect(logger).to have_received(:warn).with(/MCP_STDIO_MAX_CONCURRENCY/).twice
    end

    it 'sizes the ceiling from WORKER_WEB_THREADS when the process can see it' do
      env = { 'WORKER_WEB_THREADS' => '32', 'MCP_STDIO_MAX_CONCURRENCY' => '20' }

      expect(resolve(env)).to eq(20)
      expect(resolve(env.merge('MCP_STDIO_MAX_CONCURRENCY' => '40'))).to eq(28)
    end

    it 'clamps the default itself on a pool too small to afford it' do
      expect(resolve('WORKER_WEB_THREADS' => '8')).to eq(4)
    end

    it 'never resolves below 1, however small the pool' do
      expect(resolve('WORKER_WEB_THREADS' => '2')).to eq(1)
      expect(resolve('WORKER_WEB_THREADS' => '2', 'MCP_STDIO_MAX_CONCURRENCY' => '5')).to eq(1)
    end

    it 'assumes the default pool when WORKER_WEB_THREADS is not a positive integer' do
      expect(resolve('WORKER_WEB_THREADS' => 'lots', 'MCP_STDIO_MAX_CONCURRENCY' => '12')).to eq(12)
    end
  end

  describe '.instance' do
    after { described_class.reset_instance! }

    it 'is one process-wide limiter, resolved from the environment once' do
      described_class.reset_instance!
      allow(described_class).to receive(:resolve_limit).and_return(5)

      first = described_class.instance

      expect(first.limit).to eq(5)
      expect(described_class.instance).to be(first)
      expect(described_class).to have_received(:resolve_limit).once
    end
  end
end
