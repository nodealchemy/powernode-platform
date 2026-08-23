# frozen_string_literal: true

module Powernode
  module MigrationHelpers
    # Safe `CREATE INDEX CONCURRENTLY` for migrations.
    #
    # WHY THIS EXISTS
    #
    # `add_index ..., algorithm: :concurrently` must run outside a transaction —
    # that is the point of it. The consequence is that PostgreSQL does NOT roll
    # the build back when it fails partway (statement/lock timeout, deadlock, a
    # connection dropped mid-deploy). It leaves the index behind with
    # `pg_index.indisvalid = false`. The planner will never use such an index.
    #
    # The migration raises, so it does not stamp, and the operator re-runs
    # `db:migrate`. On the retry `CREATE INDEX CONCURRENTLY IF NOT EXISTS`
    # matches **by NAME ONLY** — it sees the invalid leftover, silently skips,
    # and the migration stamps as applied. `schema_migrations` then says
    # applied, `db/schema.rb` shows the index, and the index is permanently
    # unusable, with no error anywhere. The full scan the index was added to
    # remove comes back silently.
    #
    # Proven on live PostgreSQL 16: with `probe_negctl_69_ix` already on column
    # `(a)`, `CREATE INDEX CONCURRENTLY IF NOT EXISTS probe_negctl_69_ix ON
    # probe_negctl_69 (b)` was accepted silently and `pg_indexes.indexdef` still
    # read `USING btree (a)`. Neither the definition nor `indisvalid`
    # participates in the existence test.
    #
    # WHAT THIS DOES INSTEAD
    #
    # Before building, it looks the name up in the catalog (in the TABLE's
    # schema, which is where `CREATE INDEX` would put it) and decides:
    #
    #   nothing there                  -> build it
    #   an INVALID plain index on the
    #     requested table, with NO
    #     build in flight               -> DROP INDEX CONCURRENTLY, then build
    #   a VALID index whose definition
    #     matches semantically          -> no-op, say so, return
    #   anything else                   -> RAISE, naming the index
    #
    # Dropping the invalid one is safe: an invalid index is unusable by
    # definition — the planner cannot pick it and no constraint can be resting
    # on it (the constraint-backed case is excluded explicitly below), so there
    # is nothing to be relying on it. Dropping a VALID index is genuinely
    # destructive — something may be using it right now, and the difference may
    # be deliberate — so this helper never does that. It raises and names the
    # index, leaving the call deliberately to a human.
    #
    # AN INVALID INDEX IS NOT NECESSARILY A CORPSE
    #
    # A `CREATE INDEX CONCURRENTLY` that is STILL RUNNING in another session
    # presents identically to a failed one — measured on PG 16.2:
    # `relkind='i', indisvalid=f, indisready=t, indislive=t`, no constraint.
    # That is exactly the "build it concurrently ahead of the deploy" mitigation
    # an operator is told to use. Dropping it would block on the live build's
    # ShareUpdateExclusiveLock for however long it has left, then destroy the
    # finished index and rebuild it from zero. So the invalid branch is gated
    # twice: `pg_stat_progress_create_index` is consulted first (exact — a
    # corpse has no backend), and the DROP itself runs under a short
    # `lock_timeout` so that a build this process cannot see (a role without
    # `pg_read_all_stats`, or an in-flight concurrent DROP, which has no
    # progress view at all) surfaces as a named error instead of a long block.
    #
    # HOW "SAME DEFINITION" IS DECIDED
    #
    # Not by string-comparing what the migration asked for. Raw text differs for
    # whitespace, schema qualification, default operator classes, default sort
    # order and predicate parenthesisation that are all semantically identical,
    # and a guard that raises on every legitimate re-run is as useless as one
    # that silently skips.
    #
    # Instead both sides are canonicalised by PostgreSQL itself, with the same
    # function. The desired index is built for real — on a throwaway TEMPORARY
    # table created with `LIKE <table>` (column definitions only: no rows, no
    # data copied, ACCESS SHARE on the source) — and `pg_get_indexdef` is read
    # off it. That output is compared to `pg_get_indexdef` of the existing
    # index, from the `USING` keyword onward so that the index and table names
    # (which necessarily differ) drop out. Uniqueness is compared separately.
    # Operator classes, `INCLUDE`, `NULLS NOT DISTINCT`, sort order, collation
    # and the partial `WHERE` predicate all survive into that tail, already
    # normalised, on both sides. Verified against 22 index shapes (pgvector
    # hnsw/ivfflat opclasses, gin_trgm_ops, jsonb_path_ops, ltree gist, inet,
    # domains, enums, generated and identity columns, arrays, column- and
    # index-level COLLATE, DESC NULLS LAST, INCLUDE, NULLS NOT DISTINCT,
    # cast-deparsing partial predicates, expression indexes): every one
    # round-tripped byte-identical.
    #
    # The shadow build only ever runs when a same-name VALID index already
    # exists — the fresh-install path does no extra work at all. If the shadow
    # build cannot be completed, or either definition cannot be parsed, the
    # helper raises rather than guessing.
    #
    # USAGE — from `up`, never from `change`:
    #
    #   class AddSomeIndex < ActiveRecord::Migration[8.0]
    #     include Powernode::MigrationHelpers::ConcurrentIndex
    #     disable_ddl_transaction!
    #
    #     def up
    #       add_index_concurrently :widgets, %i[account_id created_at],
    #                              name: "index_widgets_on_account_and_created"
    #     end
    #
    #     def down
    #       remove_index :widgets, name: "index_widgets_on_account_and_created",
    #                    algorithm: :concurrently, if_exists: true
    #     end
    #   end
    module ConcurrentIndex
      # Raised when the helper will not proceed on its own judgement. Always
      # names the index so the operator can go look at it.
      class UnsafeIndexStateError < StandardError; end

      SHADOW_PREFIX = "zz_pn_ixchk"

      # How long the DROP of an invalid leftover may wait for the table lock
      # before giving up and reporting rather than blocking a deploy. Override
      # per-install; there is nothing magic about the default.
      DEFAULT_DROP_LOCK_TIMEOUT = "5s"

      # Same signature as `add_index`, except that `name:` is REQUIRED and
      # `algorithm:`/`if_not_exists:` are not accepted (they are the two options
      # whose interaction this helper exists to replace).
      def add_index_concurrently(table_name, column_name, name:, **options)
        index_name = name.to_s

        if options.key?(:algorithm) || options.key?(:if_not_exists)
          raise ArgumentError,
                "add_index_concurrently manages :algorithm and :if_not_exists itself " \
                "(index #{index_name}); remove them from the call"
        end

        if connection.is_a?(ActiveRecord::Migration::CommandRecorder)
          raise UnsafeIndexStateError,
                "add_index_concurrently (index #{index_name}) inspects the catalog and cannot be " \
                "recorded/reverted; call it from `def up` with a matching `def down`, not `def change`"
        end

        if connection.transaction_open?
          raise UnsafeIndexStateError,
                "add_index_concurrently (index #{index_name}) needs to run outside a transaction; " \
                "add `disable_ddl_transaction!` to the migration"
        end

        # Resolve schema and BARE relation name in one step. `table_name` may be
        # schema-qualified; every catalog comparison below is against the bare
        # `relname`, and every quoted identifier is assembled part by part —
        # never by handing a composed dotted string to `quote_table_name`, which
        # silently drops the third part of `a.b.c`.
        schema, table = concurrent_index_resolve_table!(table_name, index_name)

        existing = concurrent_index_catalog_row(schema, index_name)
        if existing && !concurrent_index_handle_existing!(existing, schema, table, column_name, options, index_name)
          return
        end

        concurrent_index_create!(table_name, column_name, options, index_name, schema, table)
      end

      private

      # true  -> the caller should go on and build the index
      # false -> nothing more to do (identical index already present)
      # (raises otherwise)
      def concurrent_index_handle_existing!(row, schema, table, column_name, options, index_name)
        action, message = concurrent_index_decide(row, schema, table, column_name, options, index_name)

        case action
        when :skip
          say("index #{index_name} already exists, is valid and matches — #{message}", true)
          concurrent_index_apply_comment(schema, index_name, options[:comment])
          false
        when :drop
          say("index #{index_name} exists but is UNUSABLE (#{message}) — dropping it so the build is real", true)
          concurrent_index_drop_invalid!(schema, table, index_name)
          true
        else
          raise UnsafeIndexStateError, message
        end
      end

      def concurrent_index_create!(table_name, column_name, options, index_name, schema, table)
        add_index(table_name, column_name, **options, name: index_name, algorithm: :concurrently)
      rescue ActiveRecord::StatementInvalid => e
        # TOCTOU: something created this name between the probe and the build.
        # Live installs auto-apply migrations, so two nodes rolling at once is
        # ordinary. Re-probe and re-decide ONCE rather than propagating a bare
        # PG::DuplicateTable — plain `if_not_exists: true` used to tolerate this
        # case and the helper must not be a regression on it.
        raise unless defined?(PG::DuplicateTable) && e.cause.is_a?(PG::DuplicateTable)

        row = concurrent_index_catalog_row(schema, index_name)
        raise if row.nil?

        say("index #{index_name} appeared concurrently during the build — re-checking it", true)
        # The verdict MUST be honoured. On :drop, `handle_existing!` removed a
        # corpse and returns true meaning "now build it"; discarding that would
        # leave NO index at all while the migration still stamps as applied —
        # strictly worse than the dead index this helper exists to prevent.
        # A second 42P07 here is a genuine race we will not paper over.
        return unless concurrent_index_handle_existing!(row, schema, table, column_name, options, index_name)

        add_index(table_name, column_name, **options, name: index_name, algorithm: :concurrently)
      end

      # The schema `CREATE INDEX` would put the index in is the TABLE's schema,
      # not `current_schema()` — so that is where we look the name up.
      # Returns [schema, bare_relname].
      def concurrent_index_resolve_table!(table_name, index_name)
        # `to_regclass` RAISES rather than returning NULL for a name with more
        # than three dotted parts, so the raw PG error is converted here too.
        row = begin
          connection.select_one(<<~SQL.squish, "ConcurrentIndex table resolution")
            SELECT n.nspname AS schema, c.relname AS relname
            FROM pg_class c
            JOIN pg_namespace n ON n.oid = c.relnamespace
            WHERE c.oid = to_regclass(#{connection.quote(table_name.to_s)})
          SQL
        rescue ActiveRecord::StatementInvalid => e
          raise UnsafeIndexStateError,
                "cannot build index #{index_name}: #{table_name.inspect} is not a usable table name " \
                "(#{e.message.lines.first.to_s.strip})"
        end

        return [ row["schema"], row["relname"] ] if row

        raise UnsafeIndexStateError,
              "cannot build index #{index_name}: table #{table_name} does not exist " \
              "(or is not visible on search_path)"
      end

      def concurrent_index_catalog_row(schema, index_name)
        connection.select_one(<<~SQL.squish, "ConcurrentIndex catalog probe")
          SELECT c.oid::text            AS oid,
                 c.relkind::text        AS relkind,
                 i.indisvalid::text     AS indisvalid,
                 i.indisready::text     AS indisready,
                 i.indislive::text      AS indislive,
                 i.indrelid::text       AS table_oid,
                 t.relname              AS on_table,
                 pg_get_indexdef(c.oid) AS indexdef,
                 (SELECT count(*) FROM pg_constraint con WHERE con.conindid = c.oid)::text AS constraint_count
          FROM pg_class c
          JOIN pg_namespace n ON n.oid = c.relnamespace
          LEFT JOIN pg_index i ON i.indexrelid = c.oid
          LEFT JOIN pg_class t ON t.oid = i.indrelid
          WHERE n.nspname = #{connection.quote(schema)} AND c.relname = #{connection.quote(index_name)}
        SQL
      end

      # Returns [:skip | :drop | :fail, message].
      def concurrent_index_decide(row, schema, table, column_name, options, index_name)
        qualified = "#{schema}.#{index_name}"

        unless %w[i I].include?(row["relkind"])
          return [ :fail, "cannot build index #{index_name}: #{qualified} already exists and is not an index " \
                          "(pg_class.relkind = #{row['relkind'].inspect}). Resolve the name collision by hand." ]
        end

        if row["on_table"].to_s != table
          return [ :fail, "cannot build index #{index_name}: an index of that name already exists in schema " \
                          "#{schema}, but on table #{row['on_table']}, not #{table}. Existing definition: " \
                          "#{row['indexdef']}" ]
        end

        indisvalid = row["indisvalid"] == "true"
        indisready = row["indisready"] == "true"

        unless indisvalid && indisready
          if row["relkind"] == "I"
            return [ :fail, "cannot build index #{index_name}: #{qualified} is a PARTITIONED index marked invalid. " \
                            "For a partitioned index that means some partitions have no matching index yet — it is " \
                            "not necessarily a failed build, so this is not safe to drop automatically. " \
                            "Existing definition: #{row['indexdef']}" ]
          end

          if row["constraint_count"].to_i.positive?
            return [ :fail, "cannot build index #{index_name}: #{qualified} is invalid but backs a constraint, so " \
                            "it cannot simply be dropped. Drop the constraint deliberately, then re-run. " \
                            "Existing definition: #{row['indexdef']}" ]
          end

          in_flight = concurrent_index_in_flight_reason(row, table, index_name)
          if in_flight
            return [ :fail, "cannot build index #{index_name}: #{qualified} is invalid, but #{in_flight}. That is " \
                            "consistent with a concurrent index build or drop still RUNNING — not with a failed " \
                            "one — and dropping it would throw that work away. Wait for it to finish (a completed " \
                            "matching build makes this migration a no-op) and re-run, or resolve it deliberately. " \
                            "Existing definition: #{row['indexdef']}" ]
          end

          reason = indisvalid ? "indisready = false" : "indisvalid = false"
          return [ :drop, "#{reason}; left behind by a failed concurrent build" ]
        end

        existing_shape = concurrent_index_comparable(row["indexdef"])
        desired_def = concurrent_index_desired_definition(schema, table, column_name, options, index_name)
        desired_shape = concurrent_index_comparable(desired_def)
        desired_display = concurrent_index_for_display(desired_def, schema, table, index_name)

        if existing_shape.nil? || desired_shape.nil?
          return [ :fail, "cannot decide about index #{index_name}: an index of that name already exists and is " \
                          "valid, but its definition could not be compared to the one requested. " \
                          "Existing: #{row['indexdef']} / requested: #{desired_display}. Resolve by hand." ]
        end

        return [ :skip, "definition #{row['indexdef']}" ] if existing_shape == desired_shape

        [ :fail, "REFUSING to build index #{index_name}: an index of that name already exists on #{table}, is " \
                 "VALID, and has a DIFFERENT definition. Dropping a valid index is destructive — something may be " \
                 "relying on it and the difference may be deliberate — so this is left to you.\n" \
                 "  existing:  #{row['indexdef']}\n" \
                 "  requested: #{desired_display}\n" \
                 "Reconcile them, or drop the existing index deliberately " \
                 "(DROP INDEX CONCURRENTLY #{qualified}) and re-run." ]
      end

      # Discriminates "something is running right now" from "a corpse a failed
      # build left behind". Returns a human reason, or nil for "no evidence of
      # anything in flight". Two gates, because neither alone is enough:
      #
      #   pg_locks (PRIMARY) — privilege-free. MEASURED on PG 16.2: a role
      #     without `pg_read_all_stats` sees the ShareUpdateExclusiveLock row
      #     for another role's build. This is the gate that actually holds in
      #     the headline case (operator pre-builds under their own login, the
      #     deploy connects as the app role) and it is the ONLY one that catches
      #     an in-flight DROP INDEX CONCURRENTLY, which has no progress view.
      #     Necessarily TABLE-scoped: MEASURED, a running CREATE INDEX
      #     CONCURRENTLY holds SUE on the TABLE only, never on the index, so
      #     there is no narrower relation to key on. The cost is a known
      #     false-positive class — VACUUM/ANALYZE/autovacuum also hold SUE — and
      #     it cannot be filtered, because `pg_stat_activity.backend_type` is
      #     NULL cross-role (measured). A false positive here is a loud,
      #     re-runnable refusal; the failure it prevents is destroying a live
      #     build. That trade is deliberate.
      #
      #   pg_stat_progress_create_index (SHARPER MESSAGE, NOT LOAD-BEARING) —
      #     exact when visible, but MEASURED to NULL out `index_relid`/`relid`
      #     for another role's build, so it silently reports "nothing running".
      #     Never rely on it alone.
      #
      # Neither gate closes the millisecond between this decision and the DROP.
      # That TOCTOU is irreducible without holding a lock we cannot hold; the
      # lock-timed DROP in `concurrent_index_drop_invalid!` is what bounds it.
      def concurrent_index_in_flight_reason(row, table, index_name)
        oid = concurrent_index_oid!(row, "oid", index_name)
        table_oid = concurrent_index_oid!(row, "table_oid", index_name)

        held = connection.select_value(<<~SQL.squish, "ConcurrentIndex lock probe").to_s == "true"
          SELECT EXISTS (
            SELECT 1 FROM pg_locks l
            WHERE l.locktype = 'relation'
              AND l.relation = #{table_oid}::oid
              AND l.mode = 'ShareUpdateExclusiveLock'
              AND l.granted
              AND l.pid <> pg_backend_pid()
          )::text
        SQL
        if held
          return "another session holds ShareUpdateExclusiveLock on #{table} " \
                 "(a concurrent index build or drop — or a VACUUM/ANALYZE, which take the same lock)"
        end

        running = begin
          connection.select_value(<<~SQL.squish, "ConcurrentIndex progress probe").to_s == "true"
            SELECT EXISTS (
              SELECT 1 FROM pg_stat_progress_create_index p
              WHERE p.index_relid = #{oid}::oid OR p.relid = #{table_oid}::oid
            )::text
          SQL
        rescue StandardError => e
          # Never silently. The pg_locks gate above already ran and is the one
          # that carries the guarantee, but a failing gate must be visible.
          say("could not read pg_stat_progress_create_index (#{e.class}); " \
              "relying on the pg_locks gate and the lock-timed DROP", true)
          false
        end
        return "pg_stat_progress_create_index reports a CREATE INDEX CONCURRENTLY in progress" if running

        nil
      end

      # OIDs are interpolated into the gate queries, so prove they are integers
      # rather than trusting the catalog row shape. A gate that quietly degrades
      # is the exact failure mode these probes exist to prevent.
      def concurrent_index_oid!(row, key, index_name)
        Integer(row[key])
      rescue TypeError, ArgumentError
        raise UnsafeIndexStateError,
              "cannot decide about index #{index_name}: the catalog probe returned no #{key} " \
              "(#{row[key].inspect}), so whether a build is in flight cannot be determined. Resolve by hand."
      end

      # An in-flight CREATE (or DROP) INDEX CONCURRENTLY holds
      # ShareUpdateExclusiveLock on the table, which our DROP also needs. Bound
      # the wait so an invisible build reports instead of stalling the deploy —
      # and never leave the session's lock_timeout changed.
      def concurrent_index_drop_invalid!(schema, table, index_name)
        target = "#{connection.quote_table_name(schema)}.#{connection.quote_table_name(index_name)}"
        previous = connection.select_value("SHOW lock_timeout")
        timeout = ENV.fetch("PN_CONCURRENT_INDEX_DROP_LOCK_TIMEOUT", DEFAULT_DROP_LOCK_TIMEOUT)

        begin
          connection.execute("SET lock_timeout = #{connection.quote(timeout)}")
          connection.execute("DROP INDEX CONCURRENTLY IF EXISTS #{target}")
        rescue ActiveRecord::LockWaitTimeout => e
          # 55P03: the lock was never acquired, so the DROP did not begin.
          # MEASURED against a live build: refused after exactly the timeout,
          # and the other session's build went on to complete as VALID.
          raise UnsafeIndexStateError,
                "cannot build index #{index_name}: #{schema}.#{index_name} is invalid, but the lock needed to " \
                "drop it could not be taken within #{timeout} (#{e.class}). Another session holds " \
                "ShareUpdateExclusiveLock on #{schema}.#{table} — most likely an in-flight concurrent build or " \
                "drop of this index. NOTHING WAS CHANGED. Wait for it to finish and re-run."
        rescue ActiveRecord::QueryCanceled => e
          # 57014: the lock WAS taken and the drop was cancelled part-way
          # (statement_timeout). DROP INDEX CONCURRENTLY commits indisvalid =
          # false before it waits, so this arm must NOT claim nothing changed.
          raise UnsafeIndexStateError,
                "cannot build index #{index_name}: the DROP of the invalid #{schema}.#{index_name} was cancelled " \
                "part-way (#{e.class}) — most likely statement_timeout. THE DROP MAY HAVE PARTLY APPLIED: the " \
                "index was already invalid and may now also be marked not-live. Inspect pg_index for " \
                "#{schema}.#{index_name}, finish the DROP by hand, then re-run."
        ensure
          begin
            connection.execute("SET lock_timeout = #{connection.quote(previous)}")
          rescue StandardError # rubocop:disable Lint/SuppressedException
            # Restoring a session setting must never mask the real failure
            # (e.g. when the connection itself is gone).
          end
        end
      end

      # `add_index` on PostgreSQL issues `COMMENT ON INDEX` as a separate
      # statement, so the skip path has to do it too or a requested comment is
      # silently dropped whenever the index already exists.
      def concurrent_index_apply_comment(schema, index_name, comment)
        return if comment.nil?

        target = "#{connection.quote_table_name(schema)}.#{connection.quote_table_name(index_name)}"
        connection.execute("COMMENT ON INDEX #{target} IS #{connection.quote(comment)}")
      end

      # Canonical `pg_get_indexdef` text for the index this call WANTS, obtained
      # by actually building it on an empty TEMPORARY clone of the table so that
      # PostgreSQL — not us — does the normalising. Returned RAW (temp-schema
      # names and all): this is the string that gets COMPARED, so nothing may
      # rewrite it. Raises (loud, named) if the shadow build cannot be done.
      def concurrent_index_desired_definition(schema, table, column_name, options, index_name)
        suffix = SecureRandom.hex(6)
        shadow_table = "#{SHADOW_PREFIX}_t_#{suffix}"
        shadow_index = "#{SHADOW_PREFIX}_i_#{suffix}"
        source = "#{connection.quote_table_name(schema)}.#{connection.quote_table_name(table)}"

        begin
          connection.execute(
            "CREATE TEMPORARY TABLE #{connection.quote_table_name(shadow_table)} (LIKE #{source})"
          )
          create_index = connection.build_create_index_definition(
            shadow_table, column_name, **options, name: shadow_index
          )
          connection.execute(connection.schema_creation.accept(create_index))
          connection.select_value(
            "SELECT pg_get_indexdef(to_regclass(#{connection.quote(shadow_index)}))",
            "ConcurrentIndex desired definition"
          )
        rescue StandardError => e
          raise UnsafeIndexStateError,
                "cannot decide about index #{index_name}: an index of that name already exists and is valid, but " \
                "the requested definition could not be canonicalised for comparison (#{e.class}: #{e.message}). " \
                "This step needs TEMPORARY privilege on the database and a session-scoped connection — a locked " \
                "down migration role, or a connection pooler in transaction mode, will break it. Resolve by hand."
        ensure
          begin
            connection.execute("DROP TABLE IF EXISTS #{connection.quote_table_name(shadow_table)}")
          rescue StandardError # rubocop:disable Lint/SuppressedException
            # A temporary table dies with the session; never mask the real error.
          end
        end
      end

      # Cosmetic ONLY — for error messages. Puts the real names back so the
      # operator reads the definition they asked for rather than temp-schema
      # noise. Never fed to `concurrent_index_comparable`.
      def concurrent_index_for_display(definition, schema, table, index_name)
        return definition if definition.blank?

        definition.sub(/\ACREATE (UNIQUE )?INDEX \S+ ON \S+/) do
          "CREATE #{Regexp.last_match(1)}INDEX #{index_name} ON #{schema}.#{table}"
        end
      end

      # [unique?, everything from USING onward] — the part of two indexdefs that
      # is comparable once the (necessarily different) index and table names are
      # dropped. Returns nil when the text cannot be parsed, which the caller
      # turns into a loud failure rather than a guess.
      #
      # Slicing at the FIRST " USING " would mis-slice an index or table whose
      # quoted name contains that substring. Both sides come from
      # `pg_get_indexdef`, so a mis-slice can only ever make two equal
      # definitions compare unequal — a false REFUSAL, never a false skip. It
      # fails closed, so it is left alone rather than parsed properly.
      def concurrent_index_comparable(indexdef)
        return nil if indexdef.blank?

        marker = indexdef.index(" USING ")
        return nil if marker.nil?

        [ indexdef.start_with?("CREATE UNIQUE INDEX "), indexdef[marker..].gsub(/\s+/, " ").strip ]
      end
    end
  end
end
