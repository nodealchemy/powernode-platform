# frozen_string_literal: true

require "rails_helper"

# IMP 01a15724-5933: Powernode::Redis used to memoise ONE client, so every
# thread in a threaded puma serialised through that client's Monitor (a slow
# call on one thread blocked every other thread's GET). `with` checks a
# connection out of a ConnectionPool instead.
RSpec.describe "Powernode::Redis.with (connection pool)" do
  after { Powernode::Redis.reconfigure! }

  it "hands two simultaneous threads distinct connections" do
    ids = Queue.new
    barrier = Queue.new
    threads = Array.new(2) do
      Thread.new do
        Powernode::Redis.with do |redis|
          ids << redis.call("CLIENT", "ID")
          barrier << :in
          sleep 0.05 until barrier.size >= 2 # both threads hold a connection at once
        end
      end
    end
    threads.each { |t| expect(t.join(5)).not_to be_nil }

    seen = Array.new(2) { ids.pop }
    expect(seen.uniq.size).to eq(2)
  end

  it "does not let a slow call on one thread block another thread's GET" do
    started = Queue.new
    slow = Thread.new do
      Powernode::Redis.with do |redis|
        started << :go
        redis.call("DEBUG", "SLEEP", "1")
      end
    rescue StandardError
      sleep 1 # DEBUG may be disabled; the connection is still held for the duration
    end
    started.pop

    t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    Powernode::Redis.with { |redis| redis.get("pool-spec:probe") }
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0
    slow.join(5)

    expect(elapsed).to be < 0.5
  end

  it "returns the block's value and checks the connection back in" do
    expect(Powernode::Redis.with { |redis| redis.ping }).to eq("PONG")
    expect(Powernode::Redis.pool_available).to eq(Powernode::Redis.pool_size)
  end

  it "sizes the pool from Puma's max threads plus headroom" do
    stub_const("ENV", ENV.to_h.merge("RAILS_MAX_THREADS" => "10").except("POWERNODE_REDIS_POOL_SIZE"))
    expect(Powernode::Redis.pool_size).to eq(10 + Powernode::Redis::POOL_HEADROOM)
  end

  it "keeps the test-lane database through the pool" do
    expect(Powernode::Redis.with { |redis| redis.connection[:db] }).to eq(Powernode::Redis.test_database)
  end

  it "reconfigure! drains the pool so the next checkout is a fresh connection" do
    first = Powernode::Redis.with { |redis| redis.call("CLIENT", "ID") }
    Powernode::Redis.reconfigure!
    second = Powernode::Redis.with { |redis| redis.call("CLIENT", "ID") }

    expect(second).not_to eq(first)
  end

  it "raises a pool timeout rather than waiting forever when exhausted" do
    stub_const("ENV", ENV.to_h.merge("POWERNODE_REDIS_POOL_SIZE" => "1", "POWERNODE_REDIS_POOL_TIMEOUT" => "0.2"))
    Powernode::Redis.reconfigure!
    holder = Thread.new { Powernode::Redis.with { sleep 0.8 } }
    sleep 0.2

    expect { Powernode::Redis.with(&:ping) }.to raise_error(ConnectionPool::TimeoutError)
    holder.join
  end

  it "has no remaining callers of the removed shared client in app code" do
    hits = Dir.glob(Rails.root.join("app/**/*.rb")).select { |f| File.read(f).match?(/Powernode::Redis\.client\b/) }
    expect(hits).to be_empty
  end
end
