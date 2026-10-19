# frozen_string_literal: true

# TestProf (https://test-prof.evilmartians.io) — `let_it_be` / `before_all` and the profilers.
#
# `before_all` / `let_it_be` create data once per example group inside a transaction that
# before_all opens itself (independent of transactional fixtures), rolled back when the group
# ends, so it cannot leak into sibling groups. Use them for data a group only READS; reach for
# `let_it_be(:x, refind: true)` or `reload: true` when an example mutates the record.
# NEVER use before_all / let_it_be in :truncation groups (use_transactional_tests = false):
# the data would not be rolled back and would leak.
#
# The profilers are inert unless their env var is set:
#   FPROF=1                               FactoryProf  (FPROF=flamegraph for the stack view)
#   EVENT_PROF=factory.create             EventProf    (also: sql.active_record)
#   RD_PROF=1                             RSpecDissect (let/before time per group)
#   TAG_PROF=type                         TagProf
#   FDOC=1                                FactoryDoctor
# See docs/operations/test-performance-profile-2026-10.md.
require "test_prof/recipes/rspec/before_all"
require "test_prof/recipes/rspec/let_it_be"
