# frozen_string_literal: true

# Example: Using the Modular Workflow Orchestration Services
#
# This example demonstrates how to use the new modular workflow services
# instead of the monolithic WorkflowOrchestrator. The modular approach
# provides better separation of concerns and easier testing.
#
# Services Used:
# - Mcp::WorkflowExecutor: Handles node execution and flow control
# - Mcp::WorkflowStateManager: Manages state transitions
# - Mcp::WorkflowEventStore: Records all execution events
#
# Benefits of Modular Approach:
# - Each service has single responsibility
# - Services can be tested independently
# - State and event management can be customized
# - Easier to understand and maintain

module Examples
  module Services
    # ModularWorkflowExecutionExample - Shows how to orchestrate workflows using modular services
    class ModularWorkflowExecutionExample
      def initialize(workflow_run)
        @workflow_run = workflow_run
      end

      # =============================================================================
      # BASIC USAGE: Execute workflow with all components
      # =============================================================================

      def basic_execution
        # Create component services
        state_manager = Mcp::WorkflowStateManager.new(workflow_run: @workflow_run)
        event_store = Mcp::WorkflowEventStore.new(workflow_run: @workflow_run)
        executor = Mcp::WorkflowExecutor.new(
          workflow_run: @workflow_run,
          state_manager: state_manager,
          event_store: event_store
        )

        # Execute workflow
        result = executor.execute

        # Access events after execution
        timeline = event_store.build_timeline
        summary = event_store.execution_summary

        puts "Execution completed!"
        puts "  Nodes executed: #{result[:node_count]}"
        puts "  Duration: #{result[:duration_ms]}ms"
        puts "  Total events: #{event_store.event_count}"
        puts "  Timeline entries: #{timeline.count}"

        { result: result, timeline: timeline, summary: summary }
      end

      # =============================================================================
      # ADVANCED USAGE: Custom state management
      # =============================================================================

      def execution_with_custom_state_tracking
        # Create services
        state_manager = Mcp::WorkflowStateManager.new(workflow_run: @workflow_run)
        event_store = Mcp::WorkflowEventStore.new(workflow_run: @workflow_run)

        # Initialize workflow
        puts "Initializing workflow..."
        state_manager.transition!(:pending, :initializing)

        # Record custom event
        event_store.record_event(
          event_type: 'workflow.custom.initialized',
          event_data: {
            message: 'Custom initialization complete',
            custom_field: 'example value'
          }
        )

        # Create executor
        executor = Mcp::WorkflowExecutor.new(
          workflow_run: @workflow_run,
          state_manager: state_manager,
          event_store: event_store
        )

        # Execute
        result = executor.execute

        # Check final state
        puts "Final state: #{state_manager.current_state}"
        puts "Is terminal? #{state_manager.terminal_state?}"

        result
      end

      # =============================================================================
      # ERROR HANDLING: Graceful failure with event recording
      # =============================================================================

      def execution_with_error_handling
        state_manager = Mcp::WorkflowStateManager.new(workflow_run: @workflow_run)
        event_store = Mcp::WorkflowEventStore.new(workflow_run: @workflow_run)
        executor = Mcp::WorkflowExecutor.new(
          workflow_run: @workflow_run,
          state_manager: state_manager,
          event_store: event_store
        )

        begin
          result = executor.execute

          puts "Success! Final status: #{result[:status]}"
          result

        rescue Mcp::WorkflowExecutor::ExecutionError => e
          puts "Execution failed: #{e.message}"

          # State should be 'failed'
          puts "Current state: #{state_manager.current_state}"

          # Get failure events
          error_events = event_store.get_events_by_type('node.execution.failed')
          puts "Failed nodes: #{error_events.count}"

          # Get execution summary
          summary = event_store.execution_summary
          puts "Total errors: #{summary[:errors]}"

          # Export events for debugging
          event_export = event_store.export_events(format: :json)
          File.write('/tmp/workflow_failure_events.json', event_export)
          puts "Events exported to /tmp/workflow_failure_events.json"

          raise
        end
      end

      # =============================================================================
      # MONITORING: Track execution progress
      # =============================================================================

      def execution_with_monitoring
        state_manager = Mcp::WorkflowStateManager.new(workflow_run: @workflow_run)
        event_store = Mcp::WorkflowEventStore.new(workflow_run: @workflow_run)

        # Monitor state changes
        state_changes = []
        original_transition = state_manager.method(:transition!)

        state_manager.define_singleton_method(:transition!) do |from, to|
          state_changes << { from: from, to: to, at: Time.current }
          original_transition.call(from, to)
        end

        # Execute
        executor = Mcp::WorkflowExecutor.new(
          workflow_run: @workflow_run,
          state_manager: state_manager,
          event_store: event_store
        )

        result = executor.execute

        # Analyze execution
        puts "\nExecution Analysis:"
        puts "=" * 50

        # State transitions
        puts "\nState Transitions:"
        state_changes.each do |change|
          puts "  #{change[:from]} → #{change[:to]} at #{change[:at].strftime('%H:%M:%S')}"
        end

        # Event distribution
        puts "\nEvent Distribution:"
        event_counts = event_store.get_events.group_by { |e| e[:event_type] }
                                 .transform_values(&:count)
        event_counts.each do |type, count|
          puts "  #{type}: #{count}"
        end

        # Timeline
        puts "\nExecution Timeline:"
        timeline = event_store.build_timeline
        timeline.first(5).each do |entry|
          puts "  [#{entry[:sequence]}] #{entry[:timestamp].strftime('%H:%M:%S.%L')} - #{entry[:summary]}"
        end

        result
      end

      # =============================================================================
      # TESTING: Inject mock services
      # =============================================================================

      def execution_with_mocked_services
        # Create mock state manager
        mock_state_manager = double('StateManager')
        allow(mock_state_manager).to receive(:transition!)
        allow(mock_state_manager).to receive(:execute_node)
        allow(mock_state_manager).to receive(:transition_to_completed)
        allow(mock_state_manager).to receive(:transition_to_failed)

        # Create mock event store
        mock_event_store = double('EventStore')
        allow(mock_event_store).to receive(:record_event)
        allow(mock_event_store).to receive(:record_node_started)
        allow(mock_event_store).to receive(:record_node_completed)
        allow(mock_event_store).to receive(:record_node_failed)
        allow(mock_event_store).to receive(:record_execution_failed)
        allow(mock_event_store).to receive(:event_count).and_return(0)

        # Create executor with mocks
        executor = Mcp::WorkflowExecutor.new(
          workflow_run: @workflow_run,
          state_manager: mock_state_manager,
          event_store: mock_event_store
        )

        # Execute
        result = executor.execute

        # Verify interactions
        expect(mock_state_manager).to have_received(:transition!).at_least(:once)
        expect(mock_event_store).to have_received(:record_event).at_least(:once)

        puts "Mock execution completed successfully"
        result
      end

      # =============================================================================
      # COMPARISON: Monolithic vs Modular
      # =============================================================================

      def comparison_example
        puts "\n" + "=" * 80
        puts "COMPARISON: Monolithic vs Modular Orchestration"
        puts "=" * 80

        # OLD WAY: Monolithic orchestrator
        puts "\nOLD WAY (Monolithic):"
        puts "-" * 80
        puts <<~OLD
          # Single 917-line class handles everything
          orchestrator = Mcp::WorkflowOrchestrator.new(workflow_run: run)
          result = orchestrator.execute

          # Problems:
          # - Can't customize state management
          # - Can't test components independently
          # - Hard to understand with 900+ lines
          # - Violates Single Responsibility Principle
          # - Tight coupling between concerns
        OLD

        # NEW WAY: Modular services
        puts "\nNEW WAY (Modular):"
        puts "-" * 80
        puts <<~NEW
          # Separate focused services
          state_manager = Mcp::WorkflowStateManager.new(workflow_run: run)
          event_store = Mcp::WorkflowEventStore.new(workflow_run: run)
          executor = Mcp::WorkflowExecutor.new(
            workflow_run: run,
            state_manager: state_manager,
            event_store: event_store
          )
          result = executor.execute

          # Benefits:
          # ✅ Each service < 450 lines, focused on one concern
          # ✅ Can customize any component
          # ✅ Easy to test independently
          # ✅ Clear separation of concerns
          # ✅ Follows Single Responsibility Principle
          # ✅ Services use shared base abstractions
        NEW

        puts "\n" + "=" * 80
        puts "Code Metrics Comparison:"
        puts "-" * 80
        puts "Monolithic Orchestrator:  917 lines  (1 file)"
        puts "Modular Services:        1150 lines  (3 files)"
        puts "  - WorkflowExecutor:     420 lines"
        puts "  - WorkflowStateManager: 280 lines"
        puts "  - WorkflowEventStore:   450 lines"
        puts "\nBenefits:"
        puts "✅ Better separation of concerns"
        puts "✅ Easier to test (can mock individual services)"
        puts "✅ Easier to understand (each file < 500 lines)"
        puts "✅ More flexible (can customize components)"
        puts "✅ Follows SOLID principles"
        puts "=" * 80
      end
    end
  end
end

# =============================================================================
# USAGE EXAMPLES
# =============================================================================

# Example 1: Basic execution
# workflow_run = AiWorkflowRun.find(params[:id])
# example = Examples::Services::ModularWorkflowExecutionExample.new(workflow_run)
# result = example.basic_execution

# Example 2: With error handling
# result = example.execution_with_error_handling

# Example 3: With monitoring
# result = example.execution_with_monitoring

# Example 4: View comparison
# example.comparison_example
