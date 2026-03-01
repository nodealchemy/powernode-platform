# frozen_string_literal: true

module Ai
  module Agui
    class StateSyncService
      # RFC 6902 JSON Patch Operations
      SUPPORTED_OPERATIONS = %w[add remove replace move copy test].freeze

      class PatchError < StandardError; end
      class ConflictError < StandardError; end
      class TestFailedError < PatchError; end

      def initialize(session:)
        @session = session
      end

      # Push state delta to session using RFC 6902 JSON Patch
      def push_state(state_delta:)
        Rails.logger.info "[AG-UI StateSyncService] Pushing state delta for session: #{@session.id}"

        current_state = @session.state || {}
        new_state = apply_patch(current_state.deep_dup, state_delta)

        @session.update!(state: new_state)
        sequence = @session.increment_sequence!

        {
          sequence: sequence,
          snapshot: new_state
        }
      rescue PatchError => e
        Rails.logger.error "[AG-UI StateSyncService] Patch error: #{e.message}"
        raise
      end

      # Handle client-side state updates with conflict detection
      def receive_client_state(client_state:, client_sequence:)
        Rails.logger.info "[AG-UI StateSyncService] Receiving client state for session: #{@session.id}"

        server_sequence = @session.sequence_number

        if client_sequence < server_sequence
          Rails.logger.warn "[AG-UI StateSyncService] Conflict detected: client_seq=#{client_sequence}, server_seq=#{server_sequence}"
          raise ConflictError, "State conflict: client sequence #{client_sequence} is behind server sequence #{server_sequence}"
        end

        @session.update!(state: client_state)
        sequence = @session.increment_sequence!

        {
          accepted: true,
          sequence: sequence,
          snapshot: client_state
        }
      end

      # Return current state snapshot
      def snapshot
        {
          state: @session.state || {},
          sequence: @session.sequence_number
        }
      end

      # Apply RFC 6902 JSON Patch operations to state
      def apply_patch(state, operations)
        operations = Array(operations)

        operations.each do |op|
          operation = op.is_a?(Hash) ? op : op.to_h
          op_type = (operation["op"] || operation[:op]).to_s

          unless SUPPORTED_OPERATIONS.include?(op_type)
            raise PatchError, "Unsupported operation: #{op_type}"
          end

          path = operation["path"] || operation[:path]
          value = operation["value"] || operation[:value]
          from = operation["from"] || operation[:from]

          case op_type
          when "add"
            state = apply_add(state, path, value)
          when "remove"
            state = apply_remove(state, path)
          when "replace"
            state = apply_replace(state, path, value)
          when "move"
            state = apply_move(state, from, path)
          when "copy"
            state = apply_copy(state, from, path)
          when "test"
            apply_test(state, path, value)
          end
        end

        state
      end

      private

      # ==========================================
      # RFC 6902 Operations
      # ==========================================

      def apply_add(state, path, value)
        keys = parse_path(path)
        return value if keys.empty?

        parent = navigate_to_parent(state, keys)
        last_key = keys.last

        if parent.is_a?(Array)
          idx = last_key == "-" ? parent.length : last_key.to_i
          parent.insert(idx, value)
        else
          parent[last_key] = value
        end

        state
      end

      def apply_remove(state, path)
        keys = parse_path(path)
        raise PatchError, "Cannot remove root" if keys.empty?

        parent = navigate_to_parent(state, keys)
        last_key = keys.last

        if parent.is_a?(Array)
          idx = last_key.to_i
          raise PatchError, "Index #{idx} out of bounds" if idx >= parent.length
          parent.delete_at(idx)
        else
          raise PatchError, "Key '#{last_key}' not found" unless parent.key?(last_key)
          parent.delete(last_key)
        end

        state
      end

      def apply_replace(state, path, value)
        keys = parse_path(path)
        return value if keys.empty?

        parent = navigate_to_parent(state, keys)
        last_key = keys.last

        if parent.is_a?(Array)
          idx = last_key.to_i
          raise PatchError, "Index #{idx} out of bounds" if idx >= parent.length
          parent[idx] = value
        else
          raise PatchError, "Key '#{last_key}' not found for replace" unless parent.key?(last_key)
          parent[last_key] = value
        end

        state
      end

      def apply_move(state, from, path)
        from_keys = parse_path(from)
        value = get_value(state, from_keys)
        state = apply_remove(state, from)
        apply_add(state, path, value)
      end

      def apply_copy(state, from, path)
        from_keys = parse_path(from)
        value = get_value(state, from_keys).deep_dup
        apply_add(state, path, value)
      end

      def apply_test(state, path, expected_value)
        keys = parse_path(path)
        actual_value = get_value(state, keys)

        unless actual_value == expected_value
          raise TestFailedError, "Test failed: expected #{expected_value.inspect} at #{path}, got #{actual_value.inspect}"
        end
      end

      # ==========================================
      # Path Navigation Helpers
      # ==========================================

      def parse_path(path)
        return [] if path.nil? || path == "" || path == "/"

        # RFC 6901 JSON Pointer - split by '/' and unescape
        parts = path.to_s.split("/")
        parts.shift if parts.first == ""

        parts.map do |part|
          part.gsub("~1", "/").gsub("~0", "~")
        end
      end

      def navigate_to_parent(state, keys)
        return state if keys.length <= 1

        parent_keys = keys[0..-2]
        current = state

        parent_keys.each do |key|
          if current.is_a?(Array)
            current = current[key.to_i]
          elsif current.is_a?(Hash)
            current = current[key]
          else
            raise PatchError, "Cannot navigate through #{current.class} with key '#{key}'"
          end

          raise PatchError, "Path not found at key '#{key}'" if current.nil?
        end

        current
      end

      def get_value(state, keys)
        return state if keys.empty?

        current = state
        keys.each do |key|
          if current.is_a?(Array)
            current = current[key.to_i]
          elsif current.is_a?(Hash)
            current = current[key]
          else
            raise PatchError, "Cannot navigate through #{current.class}"
          end
        end

        current
      end
    end
  end
end
