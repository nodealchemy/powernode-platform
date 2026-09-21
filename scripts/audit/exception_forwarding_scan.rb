#!/usr/bin/env ruby
# frozen_string_literal: true
#
# IMP-095a5fe91b4a / IMP-7e08feaf4ebf — exception-forwarding scanner.
#
# Finds MCP tool rescue arms that let a rescued exception reach a value the
# tool returns (and, from there, ai_messages.processing_metadata and the
# model provider — see IMP-5ed95e651b80). Prints "path:line" per flagged
# rescue arm; classification (safe / needs fixing / already excluded by
# design, e.g. ActiveRecord::RecordInvalid) is a manual step this script
# does not attempt — it only enumerates candidates.
#
# Usage:
#   ruby scripts/audit/exception_forwarding_scan.rb <root-or-file> [<root-or-file> ...]
#
# ROOTS: this script has no default — it scans exactly what ARGV names.
# `.../ai/tools` was this comment's own former recommendation, and it was
# wrong: three of this scanner's reported counts were wrong (twice
# independently, by different people running the same command) because
# every run inherited that scope. But the fix is NOT "scan everything" —
# `server/app` mixes two trust boundaries with opposite rules (a
# controller returning e.message to an authenticated operator is often
# correct) and produces a total in the thousands that nobody can drive to
# zero or usefully gate on. THE RIGHT BOUNDARY is "can this method write a
# value that becomes an MCP tool result envelope" — concretely, files
# defining `error_result(`/`success_result(`/an `ai_messages.processing_
# metadata` producer. Measured directly (not derived by this script,
# which does not compute it): ~64 such files, only ~16 of them outside
# `ai/tools` (e.g. ai/ralph/repository_git_tool.rb) — meaning the narrow
# root was genuinely incomplete, but "wider" means "shaped like this
# boundary", not "the whole app tree". A hand-maintained root list fails
# the way allowlists always do (see finding 5's "match by name, not a
# map"); computing these roots from the producers themselves, each run,
# is future work, not done here.
#
# THIS IS THE FOURTH VERSION of this instrument. It has been examined
# adversarially five times and a defect found each time — treat that
# history as the reason later changes should GENERALISE the question this
# script asks rather than add another special case, not as a reason to
# distrust the approach:
#
#   1. (IMP-5ed95e651b80) A multi-class `rescue A, B => e` silently
#      truncated to the first class — an AST LIST node is a flat array,
#      not the cons-list the first version assumed.
#   2. (IMP-095a5fe91b4a) Rescue clauses attached to a BLOCK — `ids.map do
#      |id| ... rescue StandardError => e ... end` — were invisible,
#      because the scanner only walked rescue nodes reachable from method
#      DEFINITION bodies. Fixed by walking the WHOLE AST for RESBODY nodes,
#      wherever they sit. This surfaced a binding-shape difference: `rescue
#      X => e` binds via LASGN (local assignment) at method/top-level
#      scope but via DASGN (dynamic/block-local assignment) inside a
#      block, and the variable is then referenced via DVAR, not LVAR.
#   3. (IMP-095a5fe91b4a) The scanner only flagged a body whose RETURN
#      matched a few known shapes (`error:`, `error_result(`,
#      `success: false`) — `{ id:, ok:, reason: e.message }` was invisible
#      for that reason alone. Fixed by keying on whether the exception
#      variable's `.message`/`.class` was read anywhere in the body outside
#      a `Rails.logger.<level>(...)` call, not on the body's return shape.
#   4. (IMP-7e08feaf4ebf) The fix for #3 was STILL an allowlist — of two
#      method names, `message` and `class` — so `e.record.errors
#      .full_messages.join(', ')` was invisible: `e.record` is a CALL
#      whose receiver is the bound variable, four levels below where the
#      body's own top-level CALL sits, and neither `.record` nor anything
#      above it is `.message`/`.class`. FIXED HERE by asking the question
#      this instrument exists to ask directly — IS THE BOUND EXCEPTION
#      READ HERE AT ALL? — instead of allowlisting methods on it: any
#      LVAR/DVAR/IVAR/GVAR/CVAR node anywhere in the body, at any nesting
#      depth, that names the bound variable counts as a read, unless it
#      sits inside a `Rails.logger.<level>(...)` call's argument list. This
#      single change also closes e.to_s, e.inspect, e.full_message,
#      e.detailed_message, e.backtrace, e.cause.message, a bare `e` passed
#      as an argument, and `"...#{e}"` (a DSTR's interpolation slot is a
#      bare LVAR/DVAR node with no wrapping CALL at all — verified by
#      dumping the AST before relying on it, not assumed).
#
#      Two further binding shapes are handled the same way, generically,
#      rather than as one-off cases: `rescue X => @err` binds via IASGN
#      (instance variable) instead of LASGN, so the read type checked is
#      IVAR, not LVAR — and a bare `rescue StandardError` with no `=> e`
#      at all, where the body reads `$!` or the `English` library's
#      `$ERROR_INFO` alias (both parse as GVAR nodes), is checked
#      independently of whether a local/instance binding exists.
#   5. (IMP-9553e923e1bc) Two defects, both DEMONSTRATED by running the
#      #4 scanner on a synthetic probe rather than found by reading it.
#      FIRST: #4's fix mapped BINDING node type to a single expected READ
#      node type (ASSIGN_TO_READ_TYPE: LASGN -> LVAR, DASGN -> DVAR, ...)
#      and matched only when a read's node type equaled that one entry.
#      That is wrong: a read's node type depends on the SCOPE DOING THE
#      READING, not the scope that bound the variable. A method-scope
#      `rescue => e` binds via LASGN, but a read of `e` inside a block
#      passed to `each`/`map`/`transaction do`/etc. is a DVAR regardless —
#      the read's own scope, unrelated to where `e` was bound. That map
#      was STILL an enumeration standing in for the property actually
#      wanted ("does this node name the bound variable"), just a
#      better-disguised one than #4's two-method allowlist; approving it
#      as "the generalisation" was the mistake, not writing it. THE FIX IS
#      A DELETION: match the read by NAME across every read-node type
#      that could reference a variable (LVAR/DVAR/IVAR/GVAR/CVAR) — not a
#      bigger or smarter map. Names cannot collide across those
#      namespaces (`:e` a local, `:@e` an ivar, `:@@e` a cvar, `:$e` a
#      global), so this is strictly safer than type equality, not just
#      simpler.
#
#      SECOND: the sink classification added in #4 tagged EVERY read in a
#      sanitizing sink call's ENTIRE argument list as :sanitized — so
#      `rescued_error_result(e, message: "failed: " + e.message)` had its
#      legitimate argument-0 read AND the read nested in `message:` both
#      tagged sanitized, and the arm was affirmatively labeled SANITIZED
#      while that `message:` string is returned VERBATIM. A second,
#      independent review broadened this: even the sweep's OWN reviewed
#      idiom, plain `rescued_error_result(e, message: e.message)` with no
#      extra nesting, has the same defect — 33 such arms exist in core.
#      An affirmative SANITIZED on a real forward is worse than a missing
#      flag — it is what stops the next reviewer looking.
#
#      Fixing this by sanitizing argument position 0 only and calling
#      everything else RAW was rejected: it correctly stops mislabeling
#      those 33 arms SANITIZED, but dumps them into RAW and recreates the
#      exact noise problem #4's RAW/SANITIZED split existed to solve. The
#      resolution is a THIRD bucket, FORWARDED-BY-INTENT: argument
#      position 0 (what the helper logs, never returns) is SANITIZED;
#      a read anywhere else in the sink call is FORWARDED-BY-INTENT, not
#      RAW — a read entirely outside any sink call is still RAW. Before
#      this fix the scanner rendered "sanitizes the exception" and
#      "forwards it raw by deliberate choice" IDENTICALLY, which hides
#      the one category most in need of periodic re-audit.
#
#      CONSERVATION: fixing finding 1 does not, by itself, guarantee a
#      future read shape (call it shape six) cannot vanish the same way —
#      it just closes the two known holes. The total (below) used to be
#      `raw.size + sanitized.size`, computed FROM the buckets — a check
#      that cannot fail differently from the thing it measures, which is
#      exactly how finding 1's probe printed a confident, internally
#      consistent `TOTAL: 2` while silently dropping an arm. The fix is
#      `mentions_name?`, a deliberately COARSE, type-agnostic tripwire
#      (see its own comment) run against every RESBODY: does the bound
#      name (or $!/$ERROR_INFO) appear ANYWHERE in the body at all,
#      regardless of node type? If so, the fine-grained matchers above
#      MUST have produced at least one hit — if they produced none, this
#      raises immediately, naming the file and line, rather than letting
#      the run finish with a smaller, plausible-looking total. This is
#      NOT "every RESBODY must land in a bucket" (false by construction —
#      most legitimately never read the exception, e.g. `rescue => e;
#      retry`); it is "if the coarse check found the name, the fine
#      check must have found a hit too", which holds regardless of how
#      many RESBODY arms exist that correctly produce zero hits.
#      Demonstrated by deliberately narrowing VARIABLE_READ_TYPES back to
#      finding 1's broken state against server/spec/scripts/
#      exception_forwarding_scan_spec.rb's conservation fixture: the
#      tripwire fires, naming the exact arm the fine matcher would have
#      dropped.
#
# VALIDATE BEFORE TRUSTING: point this script at a known-positive shape
# (one of the arms this version was written to catch — see
# server/spec/scripts/exception_forwarding_scan_spec.rb, which does this in
# CI so a future change to this file, or a Ruby upgrade that changes how
# RubyVM::AbstractSyntaxTree represents these node types, fails loudly
# instead of the scanner silently printing nothing) and a known-negative
# shape (an arm that only logs, or reads nothing) before trusting any count
# it produces on unfixed code.
#
# A file that fails to parse is reported to stderr and skipped — NOT
# silently dropped — because for a tool whose entire output is a
# completeness claim, an unparseable file and a clean one must never look
# identical.
#
# OUTPUT IS SPLIT INTO THREE BUCKETS — RAW, FORWARDED-BY-INTENT, and
# SANITIZED — all counted in the TOTAL, nothing hidden. See finding 5's
# "SECOND" paragraph above for why two buckets were not enough: labeling
# a real forward SANITIZED just because it passes through the audited
# helper's call is worse than not flagging it, because it is what stops
# the next reviewer looking. RAW: at least one read of the bound
# exception outside any sanitizing sink call. FORWARDED-BY-INTENT: every
# read is inside a sink call, but at least one is NOT argument position 0
# — the exception reaches the audited helper, but part of its content is
# still returned verbatim (e.g. `message: e.message`); a deliberate-
# looking carve-out, not a proven-safe pattern, and worth periodic
# re-audit precisely because nothing else marks it. SANITIZED: every read
# is argument position 0 — logged server-side, never returned. This is
# NOT a special case of the kind that caused blind spot 4 — that one
# narrowed what counts as a READ, syntactically, so a read could vanish
# from the count entirely. This narrows nothing: every hit stays in the
# total, unconditionally, and is only ever LABELED by which bucket it
# falls into. Without SOME split, IMP-7e08feaf4ebf's core count read as
# 199 candidates when only a handful were unreviewed, and an instrument
# whose answer needs a manual re-read of most of its own output before it
# means anything has not really been repaired.
#
# "Nothing is hidden" is enforced, not just asserted: `mentions_name?`'s
# CONSERVATION TRIPWIRE (see finding 5's own paragraph and the function's
# comment) raises immediately if a rescue arm's body mentions the bound
# name at all but no bucket recorded a hit for it — the exact signature
# of a read shape this scanner's fine matchers do not yet recognize.
#
# THE LOAD-BEARING ASSUMPTION, stated plainly rather than left implicit:
# this script trusts `rescued_error_result` BY NAME. It does not, and
# cannot, verify that the helper itself is safe — that is
# server/spec/services/ai/tools/base_tool_rescued_error_result_spec.rb's
# job, not this script's. If that helper ever starts interpolating raw
# exception content into its default message, ITS OWN spec is what must
# catch that, not this scanner; this scanner would keep calling every one
# of its callers "sanitized" regardless.

AST = RubyVM::AbstractSyntaxTree

LOGGER_LEVELS = %i[debug info warn error fatal unknown].freeze

# The one helper this scanner trusts by name to be a genuine sanitizing
# sink (see the file header's "LOAD-BEARING ASSUMPTION"). A list, not a
# single constant, so a second audited helper can be added later without
# restructuring the classification logic — but adding a name here is a
# security claim about that helper, not a bookkeeping change.
SANITIZING_SINK_METHODS = %i[rescued_error_result].freeze

# Assignment-node types that can bind `rescue X => name`, and the
# corresponding READ-node types that can reference a variable of that
# kind. IMP-9553e923e1bc: earlier versions of this file mapped BINDING
# type to a single expected READ type (LASGN -> LVAR, DASGN -> DVAR, ...)
# and matched a read only if its node type equaled that one entry. That
# is wrong: a read's node type depends on the SCOPE DOING THE READING, not
# the scope that bound the variable. A method-scope `rescue => e` binds
# via LASGN, but a read of `e` inside a block passed to `each`/`map`/
# `transaction do`/etc. is a DVAR regardless — demonstrated by running the
# scanner on exactly that shape and getting neither RAW nor SANITIZED,
# just silence. The fix is not a bigger map (that is the same enumeration
# one binding type at a time, and iteration six would find the next gap);
# it is matching the read by NAME across every read-node type that could
# possibly reference a variable, regardless of how it was bound. Names
# cannot collide across these namespaces (`:e` a local, `:@e` an ivar,
# `:@@e` a cvar, `:$e` a global), so this is strictly safer than type
# equality, not just simpler.
BINDING_ASSIGN_TYPES = %i[LASGN DASGN IASGN GASGN CVASGN].freeze
VARIABLE_READ_TYPES = %i[LVAR DVAR IVAR GVAR CVAR].freeze

# `$!` and (via the stdlib `English` library's alias) `$ERROR_INFO` both
# read the currently-rescued exception even with NO `=> e` binding at all.
GLOBAL_ERRINFO_NAMES = [:$!, :$ERROR_INFO].freeze

def find_resbodies(node, acc)
  return acc unless node.is_a?(AST::Node)
  acc << node if node.type == :RESBODY
  node.children.each { |c| find_resbodies(c, acc) }
  acc
end

# CONSERVATION TRIPWIRE (IMP-9553e923e1bc, added after review). Deliberately
# INDEPENDENT of find_reads/find_global_errinfo_reads: it does not care
# about node TYPE at all, only whether `name` (a Symbol) appears as a
# child value ANYWHERE in the subtree. This is the coarsest possible
# "does this body mention the bound variable" check — exactly because
# blind spot 5 was a fine-grained matcher (restricted to specific node
# types) missing a real occurrence. A coarse, type-agnostic check cannot
# share that failure mode: it does not know or care what kind of node
# carries the name, so a future read shape (blind spot six, whatever it
# turns out to be) that the fine matcher fails to recognize is still
# visible here. It trades precision for that independence on purpose —
# it is a TRIPWIRE, not a classifier: used only to assert "if the name
# appears at all, something in the fine matchers must have found a hit",
# never to decide RAW/FORWARDED/SANITIZED itself.
#
# It DOES still respect the Rails.logger exclusion (via `guarded`,
# threaded the same way find_reads threads it) — a mention inside
# `Rails.logger.error(...)` is a deliberate, correct exclusion (logging
# server-side is always safe), not a read shape the fine matchers failed
# to recognize, and must not trip the tripwire.
#
# WHY IT IGNORES NODE TYPE, specifically: two designs were considered and
# rejected before this one. Coarse TEXT matching (grep the rescue body's
# source for the name) dies on comments — a comment mentioning `e` would
# false-trip a tripwire meant to catch missed READS, and the 31-vs-33
# blind-spot-5 case is exactly a discrepancy of that shape. Counting
# "recognised reads" (i.e. re-deriving VARIABLE_READ_TYPES here, just
# summed differently) is circular — it can only ever agree with the fine
# matcher it is supposed to be checking, by construction. COARSE-AST is
# the design that survives both: staying inside the parsed tree excludes
# comments for free (they are not nodes), and dropping the node-type
# restriction removes the exact dimension VARIABLE_READ_TYPES got wrong
# (blind spot 5 was a type list missing DVAR, not a name it failed to
# find). Two detectors that can fail together — for the same reason, on
# the same input — are one detector wearing two names, not independent
# evidence. Do NOT "tidy" this into a type-aware helper (e.g. reusing
# VARIABLE_READ_TYPES / BINDING_ASSIGN_TYPES here, or adding a node.type
# guard for "efficiency") — that reintroduces the shared failure mode and
# silently re-arms blind spot 5 under a different name, with nothing here
# left to catch it.
def mentions_name?(node, name, guarded = false)
  return false unless node.is_a?(AST::Node)

  if rails_logger_call?(node)
    recv, _mid, args = node.children
    return true if mentions_name?(recv, name, guarded)
    return true if args && mentions_name?(args, name, true)
    return false
  end

  return true if !guarded && node.children.any? { |c| c == name }
  node.children.any? { |c| mentions_name?(c, name, guarded) }
end

# A RESBODY's body is either a single statement node, or a BLOCK node whose
# children are the statements.
def body_statements(body_node)
  return [] if body_node.nil?
  if body_node.is_a?(AST::Node) && body_node.type == :BLOCK
    body_node.children.compact
  else
    [body_node]
  end
end

# The `=> e` binding is an assignment of ERRINFO — it may be the first
# statement of the body, or (for a bare `rescue => e` with no further
# body) the entire body. Returns the bound variable's NAME (a Symbol) or
# nil — no read-type is derived from the binding; see VARIABLE_READ_TYPES.
def errinfo_binding(stmt)
  return nil unless stmt.is_a?(AST::Node) && BINDING_ASSIGN_TYPES.include?(stmt.type)
  name, val = stmt.children
  return nil unless val.is_a?(AST::Node) && val.type == :ERRINFO
  name
end

def exc_var_name(body_node)
  body_statements(body_node).each do |stmt|
    found = errinfo_binding(stmt)
    return found if found
  end
  nil
end

def rails_logger_call?(node)
  return false unless node.is_a?(AST::Node) && node.type == :CALL
  recv, mid, _args = node.children
  return false unless recv.is_a?(AST::Node) && recv.type == :CALL
  recv_recv, recv_mid, _recv_args = recv.children
  return false unless recv_mid == :logger
  return false unless recv_recv.is_a?(AST::Node) && recv_recv.type == :CONST && recv_recv.children == [:Rails]
  LOGGER_LEVELS.include?(mid)
end

# `rescued_error_result(...)` is called with an implicit receiver (self),
# which parses as FCALL, not CALL — CALL always carries an explicit
# receiver node. Both shapes are checked so `self.rescued_error_result(...)`
# would count too, though nothing here is written that way today.
def sanitizing_sink_call?(node)
  return false unless node.is_a?(AST::Node)
  mid = case node.type
        when :FCALL then node.children[0]
        when :CALL then node.children[1]
        end
  mid && SANITIZING_SINK_METHODS.include?(mid)
end

# The sink's argument LIST, positionally — an ARRAY node (or ARGSCAT/etc
# for a splat, left as-is; not special-cased here beyond returning it).
# IMP-9553e923e1bc, finding 2: only argument POSITION 0 is what the
# helper logs and never returns — `rescued_error_result(e, message: ...)`
# returns `message:` (argument position 1+) VERBATIM. A prior version
# tagged the entire argument list :sanitized, so a read nested inside
# `message:` — e.g. `message: "failed: " + e.message`, exactly the
# sweep's own idiom for preserving a specific message — was wrongly
# labeled sanitized instead of flagged. Position 0 is genuinely safe;
# nothing past it is, regardless of how it's nested (string concat, a
# hash value, ...).
def sink_call_arg0(node)
  args = case node.type
         when :FCALL then node.children[1]
         when :CALL then node.children[2]
         end
  return nil unless args.is_a?(AST::Node)
  args.children[0]
end

def sink_call_remaining_args(node)
  args = case node.type
         when :FCALL then node.children[1]
         when :CALL then node.children[2]
         end
  return nil unless args.is_a?(AST::Node)
  rest = args.children[1..]
  return nil if rest.nil? || rest.empty?
  # Wrap the remaining positional/keyword argument nodes back into a LIST
  # so the walk can recurse into them uniformly (a bare Array isn't a
  # Node, but each element of it is one, and #find_reads only needs to
  # recurse into Nodes — iterate directly instead of re-wrapping).
  rest
end

# Walk `node`, recording every reference to the bound exception — a
# VARIABLE_READ_TYPES node (see its own comment: matched by NAME, not by
# a type derived from how the variable was bound) naming `var_name` —
# that is NOT inside a Rails.logger.<level>(...) call's argument list.
# Each recorded hit is tagged :sanitized (argument position 0 of a
# SANITIZING_SINK_METHODS call), :forwarded (any OTHER argument of such a
# call), or left nil — read as :raw by the caller — for anything outside
# a sink call entirely (see sink_call_arg0's comment and the file
# header). Never dropped either way. This is deliberately NOT an
# allowlist of methods called on the reference: whatever the body does
# with the reference once found (call .message on it, call .record
# .errors.full_messages.join(', ') on it, pass it bare as an argument,
# interpolate it into a string) is a read of the exception, and the
# instrument's job is to say so and how it flows, not to guess which uses
# are interesting.
def find_reads(node, var_name, guarded, sink, hits)
  return unless node.is_a?(AST::Node)

  if rails_logger_call?(node)
    recv, _mid, args = node.children
    find_reads(recv, var_name, guarded, sink, hits)
    find_reads(args, var_name, true, sink, hits) if args
    return
  end

  if sanitizing_sink_call?(node)
    find_reads(sink_call_arg0(node), var_name, guarded, :sanitized, hits)
    Array(sink_call_remaining_args(node)).each { |a| find_reads(a, var_name, guarded, :forwarded, hits) }
    return
  end

  if !guarded && VARIABLE_READ_TYPES.include?(node.type) && node.children[0] == var_name
    hits << [node.first_lineno, sink || :raw]
  end

  node.children.each { |c| find_reads(c, var_name, guarded, sink, hits) }
end

# Same shape, for `$!` / `$ERROR_INFO` read with no local/instance binding
# at all (or in addition to one — nothing stops a rescue body from reading
# both `e` and `$!`).
def find_global_errinfo_reads(node, guarded, sink, hits)
  return unless node.is_a?(AST::Node)

  if rails_logger_call?(node)
    recv, _mid, args = node.children
    find_global_errinfo_reads(recv, guarded, sink, hits)
    find_global_errinfo_reads(args, true, sink, hits) if args
    return
  end

  if sanitizing_sink_call?(node)
    find_global_errinfo_reads(sink_call_arg0(node), guarded, :sanitized, hits)
    Array(sink_call_remaining_args(node)).each { |a| find_global_errinfo_reads(a, guarded, :forwarded, hits) }
    return
  end

  if !guarded && node.type == :GVAR && GLOBAL_ERRINFO_NAMES.include?(node.children[0])
    hits << [node.first_lineno, sink || :raw]
  end

  node.children.each { |c| find_global_errinfo_reads(c, guarded, sink, hits) }
end

# Three buckets, priority RAW > FORWARDED > SANITIZED (a single sinkless
# read makes the whole arm RAW regardless of what else it also does):
#   RAW        — at least one read of the bound exception outside any
#                sanitizing sink call entirely. Needs review.
#   FORWARDED  — every read is inside a sanitizing sink call, but at least
#                one sits in an argument OTHER than position 0 (what the
#                helper logs, never returns) — e.g. `rescued_error_result(e,
#                message: "...: " + e.message)`. The exception reaches the
#                helper, but part of its content is returned verbatim
#                anyway. This is a DELIBERATE-LOOKING carve-out, not a
#                leak the scanner failed to see and not a proven-safe
#                pattern either — its own bucket so it is counted and
#                re-auditable rather than either invisible (blind spot 4's
#                original mistake) or drowned in RAW (which would recreate
#                the noise Addition 2 existed to fix: 33 such arms exist in
#                core today, mostly the sweep's own reviewed
#                `message: e.message` idiom).
#   SANITIZED  — every read is argument position 0 of a sanitizing sink
#                call. Nothing reaches the returned value except what the
#                helper's own logic decides to return.
def scan_file(file, raw, forwarded, sanitized)
  src = File.read(file)
  ast = begin
    AST.parse(src)
  rescue SyntaxError => e
    warn "exception_forwarding_scan: SKIPPED (parse error) #{file}: #{e.message}"
    return
  end

  find_resbodies(ast, []).each do |rb|
    _classes, body, _else = rb.children
    var_name = exc_var_name(body)
    stmts = body_statements(body).reject { |s| errinfo_binding(s) }

    hits = []
    stmts.each do |s|
      find_reads(s, var_name, false, nil, hits) if var_name
      find_global_errinfo_reads(s, false, nil, hits)
    end

    # The tripwire: does ANY statement mention the bound name (or $!/
    # $ERROR_INFO) at all, by the coarse, type-agnostic check above? If
    # so, the fine matchers above MUST have produced at least one hit —
    # if they didn't, that is exactly blind spot 5's signature (a real
    # reference the fine matcher's node-type list does not recognize),
    # and printing a smaller, internally-consistent total would repeat
    # it. Fail loudly here instead of silently undercounting.
    mentioned = stmts.any? { |s| (var_name && mentions_name?(s, var_name)) || mentions_name?(s, :$!) || mentions_name?(s, :$ERROR_INFO) }
    if mentioned && hits.empty?
      raise "exception_forwarding_scan: CONSERVATION VIOLATION at #{file}:#{rb.first_lineno} — " \
            "the rescued exception's name appears somewhere in this rescue arm's body, but no " \
            "fine-grained matcher (find_reads / find_global_errinfo_reads) found a hit. This means " \
            "a read shape exists here that this scanner's node-type matchers do not recognize — " \
            "the exact failure mode that made blind spot 5 (IMP-9553e923e1bc) undercount silently. " \
            "Investigate this arm by hand before trusting any count from this run."
    end
    next if hits.empty?

    entry = "#{file}:#{rb.first_lineno}"
    sinks = hits.map { |_line, sink| sink }
    if sinks.any?(:raw)
      raw << entry
    elsif sinks.any?(:forwarded)
      forwarded << entry
    else
      sanitized << entry
    end
  end
end

if $PROGRAM_NAME == __FILE__
  raw = []
  forwarded = []
  sanitized = []
  ARGV.each do |root|
    files = File.file?(root) ? [root] : Dir.glob(File.join(root, "**", "*.rb"))
    files.sort.each { |file| scan_file(file, raw, forwarded, sanitized) }
  end

  puts "RAW — needs review, exception content does not provably route through a sanitizing sink (#{raw.size}):"
  puts raw.sort
  puts
  puts "FORWARDED-BY-INTENT — routes through #{SANITIZING_SINK_METHODS.join(', ')} but a non-arg0 argument " \
       "also reads the exception (#{forwarded.size}):"
  puts forwarded.sort
  puts
  puts "SANITIZED — every read is argument position 0 of #{SANITIZING_SINK_METHODS.join(', ')} (#{sanitized.size}):"
  puts sanitized.sort
  puts
  puts "TOTAL: #{raw.size + forwarded.size + sanitized.size}"
end
