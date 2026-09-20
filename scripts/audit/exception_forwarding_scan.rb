#!/usr/bin/env ruby
# frozen_string_literal: true
#
# IMP-095a5fe91b4a — exception-forwarding scanner, corrected.
#
# Finds MCP tool rescue arms that let an exception's raw #message/#class
# reach a value the tool returns (and, from there, ai_messages.processing_metadata
# and the model provider — see IMP-5ed95e651b80). Prints "path:line" per
# flagged rescue arm; classification (safe / needs fixing / already
# excluded by design, e.g. ActiveRecord::RecordInvalid) is a manual step —
# this script only enumerates candidates.
#
# Usage:
#   ruby scripts/audit/exception_forwarding_scan.rb <root-or-file> [<root-or-file> ...]
#
# Typical roots: server/app/services/ai/tools, extensions/<name>/server/app/services/ai/tools
#
# THIS IS THE SECOND VERSION of this instrument. The first (used for
# IMP-5ed95e651b80) had two blind spots, both fixed here:
#
#   1. BLOCK-LEVEL RESCUES. It walked rescue nodes reachable only from method
#      DEFINITION bodies, so a rescue attached to a block —
#      `ids.map do |id| ... rescue StandardError => e ... end` — was
#      structurally invisible. This version walks the WHOLE AST (every node
#      type recurses into its children) looking for RESBODY nodes, wherever
#      they sit.
#
#   2. RETURN-SHAPE KEYING. It only flagged a candidate whose body returned
#      one of a few known shapes (`error:`, `error_result(`, `success: false`).
#      A rescue returning `{ id:, ok:, reason: e.message }` — or any other
#      shape — was invisible for that reason alone, even at method-definition
#      level. This version flags a rescue arm if the bound exception
#      variable's `.message`/`.class` is read ANYWHERE in the body outside a
#      `Rails.logger.<level>(...)` call's argument list, regardless of what
#      the body does with the value.
#
# A further wrinkle the block-level case surfaces: `rescue X => e` binds via
# an LASGN when the enclosing scope is a method/top-level body, but via a
# DASGN (dynamic/block-local assignment) when the rescue sits inside a
# block — and the exception variable is then referenced via DVAR, not LVAR.
# Both shapes are handled uniformly below; assuming only one, as the first
# version implicitly did, is the same class of miss as blind spot 1.
#
# VALIDATE BEFORE TRUSTING: this is the SECOND demonstrated defect in this
# instrument (the first version's author also found and fixed a multi-class
# `rescue A, B => e` truncation bug mid-measurement). Before trusting any
# count this script produces, point it at arms already known to be fixed
# and confirm it does not re-flag them, and at a known miss and confirm it
# does.

AST = RubyVM::AbstractSyntaxTree

LOGGER_LEVELS = %i[debug info warn error fatal unknown].freeze

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

# `rescue X => e` binds via LASGN (local assignment) when the rescue's
# enclosing scope is a method/top-level body, but via DASGN (dynamic/
# block-local assignment) when the rescue sits inside a block (e.g.
# `ids.map do |id| ... rescue StandardError => e ... end`). Both shapes
# must be recognised — this is exactly the block-vs-method distinction the
# prior version of this scanner missed, so treat them uniformly rather than
# assuming one.
ERRINFO_ASSIGN_TYPES = %i[LASGN DASGN].freeze
EXC_VAR_REF_TYPES = %i[LVAR DVAR].freeze

def errinfo_lasgn?(stmt)
  return false unless stmt.is_a?(AST::Node) && ERRINFO_ASSIGN_TYPES.include?(stmt.type)
  _var, val = stmt.children
  val.is_a?(AST::Node) && val.type == :ERRINFO
end

# The `=> e` binding is the assignment of ERRINFO — it may be the first
# statement of the body, or (for a bare `rescue => e` with no further body)
# the entire body. Find it wherever it is among the top-level statements.
def exc_var_name(body_node)
  body_statements(body_node).each do |stmt|
    return stmt.children[0] if errinfo_lasgn?(stmt)
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

# Walk `node`, recording the line of every CALL to `exc_var.message` /
# `exc_var.class` that is NOT inside a Rails.logger.<level>(...) call's
# argument list. `guarded` is true while walking such an argument list.
def find_unguarded_refs(node, exc_var, guarded, hits)
  return unless node.is_a?(AST::Node)

  if node.type == :CALL
    recv, mid, args = node.children
    if !guarded && recv.is_a?(AST::Node) && EXC_VAR_REF_TYPES.include?(recv.type) &&
       recv.children[0] == exc_var && %i[message class].include?(mid)
      hits << node.first_lineno
    end
    if rails_logger_call?(node)
      find_unguarded_refs(recv, exc_var, guarded, hits)
      find_unguarded_refs(args, exc_var, true, hits) if args
      return
    end
  end

  node.children.each { |c| find_unguarded_refs(c, exc_var, guarded, hits) }
end

if $PROGRAM_NAME == __FILE__
  results = []
  ARGV.each do |root|
    files = File.file?(root) ? [root] : Dir.glob(File.join(root, "**", "*.rb"))
    files.sort.each do |file|
      src = File.read(file)
      ast = begin
        AST.parse(src)
      rescue SyntaxError
        next
      end
      find_resbodies(ast, []).each do |rb|
        _classes, body, _else = rb.children
        exc_var = exc_var_name(body)
        next unless exc_var

        stmts = body_statements(body).reject { |s| errinfo_lasgn?(s) }
        hits = []
        stmts.each { |s| find_unguarded_refs(s, exc_var, false, hits) }
        next if hits.empty?

        results << "#{file}:#{rb.first_lineno}"
      end
    end
  end

  puts results.sort
end
