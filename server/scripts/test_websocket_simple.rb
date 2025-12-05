# frozen_string_literal: true

# Simple WebSocket broadcast test - just sends a message without full workflow execution

# Get existing workflow run to broadcast to
run = AiWorkflowRun.order(created_at: :desc).first

unless run
  puts "❌ No workflow runs found in database"
  exit 1
end

puts "✓ Found workflow run: #{run.run_id}"
puts "  Status: #{run.status}"
puts "  Created: #{run.created_at}"
puts ""
puts "Broadcasting test message..."
puts "  Stream: ai_orchestration:workflow_run:#{run.run_id}"
puts ""
puts "👀 Check browser console for: [WebSocket] Message received"
puts "   The message should include: event='test.message'"
puts ""

# Broadcast a simple test message
message = {
  event: 'test.message',
  resource_type: 'workflow_run',
  resource_id: run.run_id,
  payload: {
    test: true,
    message: 'WebSocket routing test',
    timestamp: Time.current.iso8601
  },
  timestamp: Time.current.iso8601
}

# Send to the stream
stream_key = "ai_orchestration:workflow_run:#{run.run_id}"
ActionCable.server.broadcast(stream_key, message)

puts "✓ Broadcast sent to: #{stream_key}"
puts ""
puts "If you're subscribed to this workflow run in the browser,"
puts "you should see the debug logs in the console now."
