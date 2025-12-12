# frozen_string_literal: true

# Service for managing audit log integrity using cryptographic hash chains
# Ensures SOC 2 / PCI DSS compliance for immutable audit trails
class AuditLogIntegrityService
  HASH_ALGORITHM = "SHA256"
  GENESIS_HASH = "GENESIS_BLOCK_0000000000000000000000000000000000000000000000000000000000000000"

  class IntegrityError < StandardError; end
  class ChainBrokenError < IntegrityError; end
  class HashMismatchError < IntegrityError; end
  class SequenceError < IntegrityError; end

  class << self
    # Calculate integrity hash for an audit log entry
    def calculate_hash(audit_log, previous_hash: nil)
      # Get the previous hash if not provided
      previous_hash ||= get_previous_hash(audit_log)

      # Build the data string to hash
      data = build_hash_data(audit_log, previous_hash)

      # Calculate SHA256 hash
      Digest::SHA256.hexdigest(data)
    end

    # Advisory lock key for sequence number assignment
    # Using a fixed key to serialize all sequence assignments without row-level locks
    SEQUENCE_LOCK_KEY = 1_234_567_890

    # Apply integrity hash to a new audit log before save
    def apply_integrity(audit_log)
      return if audit_log.integrity_hash.present?

      # In test environment, use simple assignment without locking to avoid
      # deadlocks from RSpec's multi-connection transactional tests
      if Rails.env.test?
        apply_integrity_without_lock(audit_log)
      else
        apply_integrity_with_lock(audit_log)
      end

      audit_log
    end

    private

    # Test-safe version without advisory locks
    def apply_integrity_without_lock(audit_log)
      last_entry = AuditLog
        .where.not(sequence_number: nil)
        .order(sequence_number: :desc)
        .first

      if last_entry
        audit_log.sequence_number = last_entry.sequence_number + 1
        audit_log.previous_hash = last_entry.integrity_hash
      else
        audit_log.sequence_number = 1
        audit_log.previous_hash = GENESIS_HASH
      end

      audit_log.integrity_hash = calculate_hash(audit_log, previous_hash: audit_log.previous_hash)
    end

    # Production version with advisory lock for concurrency safety
    def apply_integrity_with_lock(audit_log)
      ActiveRecord::Base.transaction do
        # Acquire advisory lock to serialize sequence number assignment
        ActiveRecord::Base.connection.execute(
          "SELECT pg_advisory_xact_lock(#{SEQUENCE_LOCK_KEY})"
        )

        last_entry = AuditLog
          .where.not(sequence_number: nil)
          .order(sequence_number: :desc)
          .first

        if last_entry
          audit_log.sequence_number = last_entry.sequence_number + 1
          audit_log.previous_hash = last_entry.integrity_hash
        else
          audit_log.sequence_number = 1
          audit_log.previous_hash = GENESIS_HASH
        end

        audit_log.integrity_hash = calculate_hash(audit_log, previous_hash: audit_log.previous_hash)
      end
    end

    public

    # Verify the integrity of a single audit log entry
    def verify_entry(audit_log)
      return { valid: true, reason: "No integrity hash present" } if audit_log.integrity_hash.blank?

      expected_hash = calculate_hash(audit_log, previous_hash: audit_log.previous_hash)

      if audit_log.integrity_hash == expected_hash
        { valid: true }
      else
        {
          valid: false,
          reason: "Hash mismatch",
          expected: expected_hash,
          actual: audit_log.integrity_hash
        }
      end
    end

    # Verify the entire chain or a range of entries
    def verify_chain(from_sequence: nil, to_sequence: nil, batch_size: 1000)
      results = {
        total_entries: 0,
        verified_entries: 0,
        invalid_entries: [],
        chain_intact: true,
        verification_started_at: Time.current
      }

      # Build query
      query = AuditLog.where.not(sequence_number: nil).order(sequence_number: :asc)
      query = query.where("sequence_number >= ?", from_sequence) if from_sequence
      query = query.where("sequence_number <= ?", to_sequence) if to_sequence

      previous_entry = nil
      expected_previous_hash = GENESIS_HASH

      # Process in batches for memory efficiency
      query.find_in_batches(batch_size: batch_size) do |batch|
        batch.each do |entry|
          results[:total_entries] += 1

          # Check sequence continuity
          if previous_entry && entry.sequence_number != previous_entry.sequence_number + 1
            results[:chain_intact] = false
            results[:invalid_entries] << {
              id: entry.id,
              sequence_number: entry.sequence_number,
              error: "Sequence gap detected",
              expected_sequence: previous_entry.sequence_number + 1
            }
          end

          # Verify previous hash linkage
          if entry.previous_hash != expected_previous_hash
            results[:chain_intact] = false
            results[:invalid_entries] << {
              id: entry.id,
              sequence_number: entry.sequence_number,
              error: "Previous hash mismatch",
              expected: expected_previous_hash,
              actual: entry.previous_hash
            }
          end

          # Verify entry integrity
          verification = verify_entry(entry)
          if verification[:valid]
            results[:verified_entries] += 1
          else
            results[:chain_intact] = false
            results[:invalid_entries] << {
              id: entry.id,
              sequence_number: entry.sequence_number,
              error: verification[:reason],
              expected: verification[:expected],
              actual: verification[:actual]
            }
          end

          # Update for next iteration
          expected_previous_hash = entry.integrity_hash
          previous_entry = entry
        end
      end

      results[:verification_completed_at] = Time.current
      results[:duration_seconds] = (results[:verification_completed_at] - results[:verification_started_at]).round(2)
      results[:integrity_percentage] = results[:total_entries] > 0 ?
        (results[:verified_entries].to_f / results[:total_entries] * 100).round(2) : 100.0

      results
    end

    # Verify chain and update verification timestamp
    def verify_and_mark(from_sequence: nil, to_sequence: nil)
      results = verify_chain(from_sequence: from_sequence, to_sequence: to_sequence)

      if results[:chain_intact]
        # Update chain_verified_at for all verified entries
        query = AuditLog.where.not(sequence_number: nil)
        query = query.where("sequence_number >= ?", from_sequence) if from_sequence
        query = query.where("sequence_number <= ?", to_sequence) if to_sequence

        # Note: This bypasses the immutability trigger because chain_verified_at is allowed
        query.update_all(chain_verified_at: Time.current)
      end

      results
    end

    # Backfill integrity hashes for existing audit logs
    def backfill_integrity(batch_size: 1000)
      results = {
        total_processed: 0,
        already_hashed: 0,
        newly_hashed: 0,
        errors: [],
        started_at: Time.current
      }

      # Process entries without integrity hash, ordered by creation date
      AuditLog
        .where(integrity_hash: nil)
        .order(created_at: :asc)
        .find_in_batches(batch_size: batch_size) do |batch|
          batch.each do |entry|
            results[:total_processed] += 1

            begin
              apply_integrity(entry)
              entry.save!(validate: false) # Bypass validations for backfill
              results[:newly_hashed] += 1
            rescue => e
              results[:errors] << {
                id: entry.id,
                error: e.message
              }
            end
          end
        end

      results[:completed_at] = Time.current
      results[:duration_seconds] = (results[:completed_at] - results[:started_at]).round(2)
      results
    end

    # Get chain statistics
    def chain_statistics
      {
        total_entries: AuditLog.count,
        entries_with_integrity: AuditLog.where.not(integrity_hash: nil).count,
        entries_without_integrity: AuditLog.where(integrity_hash: nil).count,
        entries_verified: AuditLog.where.not(chain_verified_at: nil).count,
        latest_sequence: AuditLog.maximum(:sequence_number) || 0,
        last_verification: AuditLog.maximum(:chain_verified_at),
        chain_started_at: AuditLog.where(sequence_number: 1).pick(:created_at)
      }
    end

    # Export chain for external verification
    def export_chain(from_sequence: nil, to_sequence: nil, format: :json)
      query = AuditLog.where.not(sequence_number: nil).order(sequence_number: :asc)
      query = query.where("sequence_number >= ?", from_sequence) if from_sequence
      query = query.where("sequence_number <= ?", to_sequence) if to_sequence

      entries = query.map do |entry|
        {
          sequence_number: entry.sequence_number,
          integrity_hash: entry.integrity_hash,
          previous_hash: entry.previous_hash,
          action: entry.action,
          resource_type: entry.resource_type,
          resource_id: entry.resource_id,
          user_id: entry.user_id,
          created_at: entry.created_at.iso8601
        }
      end

      case format
      when :json
        entries.to_json
      when :csv
        require "csv"
        CSV.generate do |csv|
          csv << entries.first.keys if entries.any?
          entries.each { |e| csv << e.values }
        end
      else
        entries
      end
    end

    private

    def get_previous_hash(audit_log)
      # If sequence number is set, find the previous entry
      if audit_log.sequence_number.present? && audit_log.sequence_number > 1
        previous_entry = AuditLog
          .where(sequence_number: audit_log.sequence_number - 1)
          .pick(:integrity_hash)

        previous_entry || GENESIS_HASH
      else
        GENESIS_HASH
      end
    end

    def build_hash_data(audit_log, previous_hash)
      # Deterministic data string for hash calculation
      # Order matters - changes to this will break verification
      [
        audit_log.id,
        audit_log.action,
        audit_log.resource_type,
        audit_log.resource_id,
        audit_log.user_id,
        audit_log.account_id,
        audit_log.ip_address,
        audit_log.user_agent,
        normalize_details(audit_log.details),
        audit_log.created_at&.to_i,
        audit_log.sequence_number,
        previous_hash
      ].map(&:to_s).join("|")
    end

    def normalize_details(details)
      return "" if details.blank?

      # Sort keys for deterministic JSON
      case details
      when Hash
        JSON.generate(details.sort.to_h)
      when String
        details
      else
        details.to_s
      end
    end
  end
end
