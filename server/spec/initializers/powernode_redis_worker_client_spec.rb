# frozen_string_literal: true

require "rails_helper"

# fc-47 review H2: a worker Redis that accepts the TCP connection and never
# answers must not hold a status sweep (or any other caller) open. The worker
# client carries explicit timeouts rather than the library defaults.
RSpec.describe "Powernode::Redis.new_worker_client" do
  it "sets explicit connect, read and write timeouts" do
    allow(::Redis).to receive(:new).and_call_original

    Powernode::Redis.new_worker_client.close

    expect(::Redis).to have_received(:new).with(
      hash_including(
        url: Powernode::Redis.worker_url,
        connect_timeout: Powernode::Redis::WORKER_CONNECT_TIMEOUT,
        read_timeout: Powernode::Redis::WORKER_READ_TIMEOUT,
        write_timeout: Powernode::Redis::WORKER_READ_TIMEOUT
      )
    )
  end

  it "keeps them short" do
    expect(Powernode::Redis::WORKER_CONNECT_TIMEOUT).to be <= 2
    expect(Powernode::Redis::WORKER_READ_TIMEOUT).to be <= 2
  end
end
