# frozen_string_literal: true

require "rails_helper"

# Cross-app contract guard: the server enqueues worker jobs by CLASS-NAME STRING.
# Nothing in Ruby links the producer's string to the consumer's class, so a
# rename/typo/never-implemented job is invisible to every compiler, linter and
# reference grep on both sides.
#
# There are TWO transports, and the name fails quietly on both:
#
#   1. HTTP (WorkerJobService -> POST /api/v1/jobs). The worker's
#      JobsController#valid_job_class? does Object.const_get + `< BaseJob` and
#      answers 422 "Invalid job class". WorkerJobService#make_worker_request
#      turns that 4xx into a WorkerServiceError — which several call sites
#      deliberately rescue as best-effort (welcome email, verification email,
#      monitoring alert), so the feature never happens and no one is told.
#
#   2. Redis — Sidekiq-formatted JSON lpush'd straight onto the worker's queue
#      (the shape System::WorkerDispatch uses; core had an Ai::WorkerDispatch
#      too until IMP-315e6c5f6e81 deleted it as inert at both ends). This lane
#      never reaches valid_job_class?: Sidekiq pops the job, fails to
#      constantize it, and it dies in the retry then dead set. Worse than the
#      422, and equally silent to the caller. Core has no producer on this lane
#      today, which is exactly why DISPATCH_SURFACE matches the TRANSPORT and
#      not a dispatcher class name — see there.
#
# This spec enumerates EVERY job-class name the server can emit as a literal and
# asserts the worker defines it. It is a static scan on purpose: the server may
# not load worker code, and `scripts/validate.sh` runs server/spec only (never
# worker/spec), so a worker-side guard would not gate anything.
#
# NOT covered, both deliberate and documented:
#   * Job classes chosen at runtime from data rather than source —
#     Ai::Missions::OrchestratorService#job_class_for_phase reads `job_class` out
#     of a mission's custom_phases / template JSON. No static scan can enumerate
#     those; the worker's 422 is their only backstop. Api::V1::JobsController
#     #forward_to_worker_service is the same shape and does not even get that:
#     it lpush'es a caller-supplied `job_class` param onto the queue itself, so
#     it takes the Redis lane's silent dead-lettering. Both are name-less to
#     this scan by construction, not by oversight.
#   * PRODUCERS inside extensions/*/server. An extension's job strings are the
#     extension's contract and belong in its own spec suite (validate.sh runs
#     extension specs separately); scanning them from core would put a core gate
#     at the mercy of independently-versioned submodules. Extension CONSUMERS
#     are scanned — see EXTENSION_JOBS_DIRS — because core does emit names that
#     extension workers define.

# All state lives on this module rather than on the example group: a bare
# constant assigned inside an `RSpec.describe` block is defined on Object (the
# block's lexical scope is top level), so names this generic would leak into
# every other spec file and can clash on load order.
module WorkerJobClassContract
  SERVER_DIR = Rails.root
  REPO_ROOT = Rails.root.parent
  WORKER_JOBS_DIR = REPO_ROOT.join("worker", "app", "jobs")

  # Extensions ship their own worker jobs, loaded into the same worker process,
  # so Object.const_get resolves them exactly like core's. Globbed, never named:
  # naming a private extension in core source is a core-purity violation. An
  # absent extension is reported honestly rather than excused — with the
  # extension gone nothing can enqueue its jobs either.
  EXTENSION_JOBS_DIRS = (
    Dir[REPO_ROOT.join("extensions", "*", "worker", "app", "jobs")] +
    Dir[REPO_ROOT.join("extensions", "private", "*", "worker", "app", "jobs")]
  ).freeze

  # A file that touches the worker-dispatch surface at all is treated as a
  # producer, and EVERY "...Job" string literal in it is treated as a name that
  # can reach the worker.
  #
  # Matching the dispatch surface rather than listing dispatcher files is what
  # makes this survive real code: the job class is routinely chosen by a
  # case/when or a lookup hash and handed to the dispatcher in a VARIABLE
  # (FileStorageService, WorkerApiClient#job_class_for_type,
  # Api::V1::ServicesController), so a regex anchored on the call site sees only
  # the variable and misses every literal.
  #
  # The last two alternatives cover the SECOND transport: Sidekiq-formatted JSON
  # lpush'd straight onto the worker's Redis queue, which never reaches the
  # worker's JobsController#valid_job_class?. There an unresolvable name is not
  # a 422 — Sidekiq pops the job, fails to constantize, and it dies in the
  # retry/dead set. Strictly worse, so it must be covered.
  #
  # Matched by its MECHANISM (`new_worker_client`, the connection to the
  # worker's Redis, and an lpush onto a `queue:*` list) rather than by a
  # dispatcher class NAME, because the name is a convention and the transport
  # is not. IMP-315e6c5f6e81 proved the difference with two fixtures pushing
  # the same undefined job: the one that named the dispatcher was caught, the
  # one that lpush'd the identical payload itself was invisible. Keying on the
  # name alone also went inert for this lane the moment core's only
  # `Ai::WorkerDispatch` was deleted (same task) — a producer FILE is what
  # carries the name, so deleting the file deletes the match.
  #
  # `WorkerDispatch` stays in the alternation for a future core dispatcher of
  # that name, not for extension code: `sources` below is core-only, and
  # extension PRODUCERS are deliberately out of scope (see the header).
  DISPATCH_SURFACE = /queue_job\(|enqueue_job\(|WorkerDispatch|["']?job_class["']?\s*(?:=>|:)|new_worker_client|lpush\(\s*["']queue:/

  # Names the server emits that no worker app defines — the escape hatch that
  # let IMP-f2cfaed728c4 land green while the defects it found were fixed one
  # at a time.
  #
  # EMPTY as of IMP-315e6c5f6e81: the last entry, DeferredOperationExecutorJob,
  # is gone because its only emitter was deleted, not because it was delisted.
  # Deferred operations run synchronously through
  # Ai::DeferredOperation#execute_now!, and the documented home for a gated
  # action too slow to run inline is a System::Task on the existing dispatch —
  # see Ai::DeferredOperation#on_approval_decision. So the contract now holds
  # with no exceptions, and an addition here needs the same justification the
  # original entries had.
  #
  # Asserted EXACT in both directions: a new undefined name fails, and
  # implementing one of these without deleting its entry fails too.
  KNOWN_UNDEFINED = [].freeze

  CONST_RE = /[A-Z][A-Za-z0-9_]*(?:::[A-Z][A-Za-z0-9_]*)*/

  module_function

  # name => [relative source paths that emit it]
  def enqueued_job_class_names
    found = Hash.new { |h, k| h[k] = [] }

    sources = Dir[SERVER_DIR.join("app", "**", "*.rb")] +
              Dir[SERVER_DIR.join("lib", "**", "*.rb")] +
              Dir[SERVER_DIR.join("lib", "**", "*.rake")]

    sources.each do |path|
      src = File.read(path)
      next unless src.match?(DISPATCH_SURFACE)

      rel = Pathname.new(path).relative_path_from(SERVER_DIR).to_s
      src.scan(/["'](#{CONST_RE}Job)["']/o) { |m| found[m[0]] << rel }
    end

    found.transform_values(&:uniq)
  end

  # Fully-qualified names of ENQUEUABLE job classes under the worker job trees.
  #
  # Mirrors JobsController#valid_job_class?, which requires `klass.is_a?(Class)`
  # and `klass < BaseJob`: only `class` declarations count, and only those whose
  # superclass is itself job-shaped. Recording bare `module`s or plain helper
  # classes (Devops::GitProviderClient, FileProcessing::ClamavScanner) would let
  # a producer naming a namespace or a concern read as a false OK.
  #
  # Modules still push onto the nesting stack — they qualify the names — they
  # just are not themselves recorded. The stack is indentation-keyed and handles
  # both the nested (`module Notifications` + `class AlertEmailJob`) and compact
  # (`class Notifications::BulkEmailJob`) forms the worker uses.
  def worker_defined_job_classes
    job_files = Dir[WORKER_JOBS_DIR.join("**", "*.rb")] +
                EXTENSION_JOBS_DIRS.flat_map { |d| Dir[File.join(d, "**", "*.rb")] }

    job_files.each_with_object(Set.new) do |path, set|
      stack = []
      File.foreach(path) do |line|
        next if line =~ /\A\s*#/
        next unless line =~ /\A(\s*)(class|module)\s+(#{CONST_RE})(?:\s*<\s*(#{CONST_RE}))?/o

        indent, kind, name, superclass = Regexp.last_match(1).length, Regexp.last_match(2),
                                         Regexp.last_match(3), Regexp.last_match(4)
        stack.pop while stack.any? && stack.last[1] >= indent
        full = name.include?("::") ? name : (stack.map(&:first) + [name]).join("::")
        stack.push([name, indent])

        set << full if kind == "class" && superclass&.match?(/Job\z/)
      end
    end
  end
end

RSpec.describe "server -> worker job-class contract", type: :integration do
  let(:enqueued) { WorkerJobClassContract.enqueued_job_class_names }
  let(:defined_in_worker) { WorkerJobClassContract.worker_defined_job_classes }
  let(:known_undefined) { WorkerJobClassContract::KNOWN_UNDEFINED }

  it "finds the worker's job tree (guard is not silently scanning nothing)" do
    expect(WorkerJobClassContract::WORKER_JOBS_DIR).to be_directory
    expect(defined_in_worker.size).to be > 200
    expect(enqueued.size).to be > 70
  end

  it "defines every job class the server enqueues by name" do
    undefined = enqueued.keys.reject { |n| defined_in_worker.include?(n) }
    unexpected = (undefined - known_undefined).sort

    detail = unexpected.map { |n| "  #{n}  <- #{enqueued[n].join(', ')}" }.join("\n")

    expect(unexpected).to be_empty, <<~MSG
      The server enqueues #{unexpected.size} job class(es) that the worker does not define.
      Each one never runs: on the HTTP lane the worker answers 422 "Invalid job
      class"; on the Redis lane (WorkerDispatch) Sidekiq cannot constantize it and
      the job dies in the retry/dead set. Both are silent to the caller.

      Fix by either defining the job in worker/app/jobs, or correcting the string
      to the name the worker actually defines (compare the ENQUEUE-SITE ARGUMENTS
      against the candidate's #execute signature — name resemblance is not evidence):

      #{detail}
    MSG
  end

  it "keeps KNOWN_UNDEFINED exact — no entry that the worker now defines" do
    stale = known_undefined.select { |n| defined_in_worker.include?(n) }

    expect(stale).to be_empty,
      "the worker now defines #{stale.join(', ')} — delete the entry from " \
      "WorkerJobClassContract::KNOWN_UNDEFINED so the contract is enforced for it."
  end

  it "keeps KNOWN_UNDEFINED exact — no entry the server no longer enqueues" do
    stale = known_undefined.reject { |n| enqueued.key?(n) }

    expect(stale).to be_empty,
      "the server no longer enqueues #{stale.join(', ')} — delete the entry from " \
      "WorkerJobClassContract::KNOWN_UNDEFINED."
  end
end
