# frozen_string_literal: true

require "securerandom"
require "json"

module Ai
  # Pushes Sidekiq-formatted jobs directly to the worker's Redis queue.
  #
  # Mirrors the System extension's `System::WorkerDispatch` pattern but lives
  # in core since deferred-operation execution is platform-wide. Server-side
  # code does not bundle the sidekiq client gem; we push raw JSON so the
  # standalone worker process picks the job up via its normal queue.
  class WorkerDispatch
    DEFAULT_QUEUE = "default"

    def self.enqueue(class_name, args:, queue: DEFAULT_QUEUE, retry_count: 3)
      payload = {
        "class" => class_name,
        "args" => Array(args),
        "queue" => queue,
        "retry" => retry_count,
        "jid" => SecureRandom.hex(12),
        "created_at" => Time.current.to_f,
        "enqueued_at" => Time.current.to_f
      }

      conn = ::Powernode::Redis.new_worker_client
      conn.sadd("queues", queue)
      conn.lpush("queue:#{queue}", JSON.generate(payload))
      payload["jid"]
    ensure
      conn&.close
    end

    def self.enqueue_deferred_operation_execution(deferred_operation_id)
      enqueue("DeferredOperationExecutorJob", args: [deferred_operation_id])
    end
  end
end
