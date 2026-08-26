# frozen_string_literal: true

require "tmpdir"
require "fileutils"

# Point the internal CA at a throwaway directory for the whole test run.
#
# WHY THIS EXISTS. LocalCaAdapter persists to POWERNODE_CA_LOCAL_DIR, defaulting
# to /var/lib/powernode/internal-ca — a production path no test process can
# write. That used to be invisible: persistence was best-effort, so a failed
# write logged a warning and the adapter kept an IN-MEMORY CA. Every spec
# touching the CA was therefore running on a root that existed only inside that
# one process, and any test asserting cross-process stability was asserting
# nothing.
#
# The in-memory fallback is gone (issuance now refuses on an unpersistable CA —
# a silently ephemeral per-process root signs certificates that verify nowhere,
# which is worse than a loud failure). So the suite needs a real, writable
# store, and it belongs HERE rather than as a Rails.env.test? branch inside the
# adapter: the adapter has no business knowing it is under test, and a
# test-only code path in the CA is exactly the kind of fork that later reads as
# production behavior.
#
# One directory per RUN (not per example) on purpose: cross-example stability
# of the generated root is a property worth preserving, and parallel workers get
# distinct dirs via TEST_ENV_NUMBER.
# Set at REQUIRE time, not in a before(:suite) hook: the adapter is memoized on
# first touch, and anything that builds it during boot or in another support
# file's setup would already have resolved the production default.
unless ENV["POWERNODE_CA_LOCAL_DIR"].to_s.strip.empty?
  # An explicit value wins — a caller who set one meant it.
else
  suffix = ENV["TEST_ENV_NUMBER"].to_s.strip
  suffix = Process.pid.to_s if suffix.empty?
  dir = File.join(Dir.tmpdir, "powernode-test-ca-#{suffix}")
  FileUtils.mkdir_p(dir, mode: 0o700)
  ENV["POWERNODE_CA_LOCAL_DIR"] = dir
end
