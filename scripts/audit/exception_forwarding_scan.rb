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
# Typical roots: server/app, extensions/<name>/server/app — NOT narrowed to
# .../ai/tools. A tool's return value is not the only path to the model
# provider: a service or skill-executor result an MCP tool wraps reaches it
# just the same, and three of this scanner's own reported counts were
# wrong (twice independently, by two different people running the same
# command) because the ai/tools-only scope was documented right here and
# every run inherited it. Point this at the whole app tree; a narrower
# root is a choice the CALLER makes deliberately, not this script's default.
#
# THIS IS THE THIRD VERSION of this instrument. It has been examined
# adversarially four times and a defect found each time — treat that
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
# OUTPUT IS SPLIT INTO TWO BUCKETS, RAW and SANITIZED, both counted in the
# total — nothing is hidden. A rescue arm whose EVERY read of the bound
# exception passes as an argument to `rescued_error_result` (the audited
# helper introduced in IMP-095a5fe91b4a: it logs the raw exception
# server-side and returns only a caller-supplied or generic safe message)
# is SANITIZED; any arm with even one read that does not is RAW. This is
# NOT a special case of the kind that caused blind spot 4 — that one
# narrowed what counts as a READ, syntactically, so a read could vanish
# from the count entirely. This narrows nothing: every hit stays in the
# total, unconditionally, and is only ever LABELED by which sink it flows
# through. Without this split, IMP-7e08feaf4ebf's core count read as
# 199 candidates when only 3 were unreviewed — the other 196 either
# already routed through the audited helper or were pre-existing
# RecordInvalid/InvalidPageRequest/etc. arms, and an instrument whose
# answer needs a manual re-read of most of its own output before it means
# anything has not really been repaired.
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

# Read-node type a rescued exception is referenced through, keyed by the
# assignment-node type that bound it. Determined generically from the
# assignment shape rather than hand-listing "method-scope vs block-scope"
# as two separate cases — the same reasoning applies to any further
# binding shape (e.g. a class variable) without another special case.
ASSIGN_TO_READ_TYPE = {
  LASGN: :LVAR,
  DASGN: :DVAR,
  IASGN: :IVAR,
  GASGN: :GVAR,
  CVASGN: :CVAR
}.freeze

# `$!` and (via the stdlib `English` library's alias) `$ERROR_INFO` both
# read the currently-rescued exception even with NO `=> e` binding at all.
GLOBAL_ERRINFO_NAMES = [:$!, :$ERROR_INFO].freeze

def find_resbodies(node, acc)
  return acc unless node.is_a?(AST::Node)
  acc << node if node.type == :RESBODY
  node.children.each { |c| find_resbodies(c, acc) }
  acc
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
# body) the entire body. Returns [var_name, read_node_type] or nil.
def errinfo_binding(stmt)
  return nil unless stmt.is_a?(AST::Node)
  read_type = ASSIGN_TO_READ_TYPE[stmt.type]
  return nil unless read_type
  name, val = stmt.children
  return nil unless val.is_a?(AST::Node) && val.type == :ERRINFO
  [name, read_type]
end

def exc_var_binding(body_node)
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

def sink_call_args(node)
  case node.type
  when :FCALL then node.children[1]
  when :CALL then node.children[2]
  end
end

# Walk `node`, recording every reference to the bound exception — a node of
# `read_type` (LVAR/DVAR/IVAR/GVAR/CVAR, matched to how it was bound) naming
# `var_name` — that is NOT inside a Rails.logger.<level>(...) call's
# argument list. Each recorded hit is tagged :raw or :sanitized depending
# on whether it sits inside a SANITIZING_SINK_METHODS call's argument list
# (see the file header) — never dropped either way. This is deliberately
# NOT an allowlist of methods called on the reference: whatever the body
# does with the reference once found (call .message on it, call .record
# .errors.full_messages.join(', ') on it, pass it bare as an argument,
# interpolate it into a string) is a read of the exception, and the
# instrument's job is to say so and how it flows, not to guess which uses
# are interesting.
def find_reads(node, var_name, read_type, guarded, sink, hits)
  return unless node.is_a?(AST::Node)

  if rails_logger_call?(node)
    recv, _mid, args = node.children
    find_reads(recv, var_name, read_type, guarded, sink, hits)
    find_reads(args, var_name, read_type, true, sink, hits) if args
    return
  end

  if sanitizing_sink_call?(node)
    args = sink_call_args(node)
    find_reads(args, var_name, read_type, guarded, :sanitized, hits) if args
    return
  end

  if !guarded && node.type == read_type && node.children[0] == var_name
    hits << [node.first_lineno, sink || :raw]
  end

  node.children.each { |c| find_reads(c, var_name, read_type, guarded, sink, hits) }
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
    args = sink_call_args(node)
    find_global_errinfo_reads(args, guarded, :sanitized, hits) if args
    return
  end

  if !guarded && node.type == :GVAR && GLOBAL_ERRINFO_NAMES.include?(node.children[0])
    hits << [node.first_lineno, sink || :raw]
  end

  node.children.each { |c| find_global_errinfo_reads(c, guarded, sink, hits) }
end

# An arm is SANITIZED only if EVERY read of the bound exception in its
# body goes through a SANITIZING_SINK_METHODS call — one read that bypasses
# the sink (even alongside others that don't) makes the whole arm RAW,
# because a single unsanitized read is the leak regardless of how many
# other reads are safely handled.
def scan_file(file, raw, sanitized)
  src = File.read(file)
  ast = begin
    AST.parse(src)
  rescue SyntaxError => e
    warn "exception_forwarding_scan: SKIPPED (parse error) #{file}: #{e.message}"
    return
  end

  find_resbodies(ast, []).each do |rb|
    _classes, body, _else = rb.children
    binding = exc_var_binding(body)
    stmts = body_statements(body).reject { |s| errinfo_binding(s) }

    hits = []
    stmts.each do |s|
      find_reads(s, binding[0], binding[1], false, nil, hits) if binding
      find_global_errinfo_reads(s, false, nil, hits)
    end
    next if hits.empty?

    entry = "#{file}:#{rb.first_lineno}"
    if hits.all? { |_line, sink| sink == :sanitized }
      sanitized << entry
    else
      raw << entry
    end
  end
end

if $PROGRAM_NAME == __FILE__
  raw = []
  sanitized = []
  ARGV.each do |root|
    files = File.file?(root) ? [root] : Dir.glob(File.join(root, "**", "*.rb"))
    files.sort.each { |file| scan_file(file, raw, sanitized) }
  end

  puts "RAW — needs review, exception content does not provably route through a sanitizing sink (#{raw.size}):"
  puts raw.sort
  puts
  puts "SANITIZED — every read routes through #{SANITIZING_SINK_METHODS.join(', ')} (#{sanitized.size}):"
  puts sanitized.sort
  puts
  puts "TOTAL: #{raw.size + sanitized.size}"
end
