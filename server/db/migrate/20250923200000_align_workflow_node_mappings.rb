# frozen_string_literal: true

class AlignWorkflowNodeMappings < ActiveRecord::Migration[8.0]
  def up
    # Update existing workflow nodes with aligned input/output mappings
    # This ensures clean data flow between nodes

    AiWorkflowNode.find_each do |node|
      updated_config = node.configuration.dup

      case node.node_type
      when 'ai_agent'
        # Add default input/output mappings if not present
        updated_config['input_mapping'] ||= {}
        updated_config['output_mapping'] ||= {}

        # Set standard mappings
        updated_config['input_mapping'] = {
          'prompt' => 'input',
          'context' => 'context',
          'data' => 'data'
        }.merge(updated_config['input_mapping'])

        updated_config['output_mapping'] = {
          'output' => 'response',
          'result' => 'response',
          'data' => 'response'
        }.merge(updated_config['output_mapping'])

        updated_config['context_variables'] ||= [ 'input', 'context', 'data' ]

      when 'api_call'
        # Ensure proper body and response mapping
        if updated_config['method'] != 'GET'
          updated_config['body'] ||= {
            'input' => '{{input}}',
            'data' => '{{data}}'
          }
        end

        updated_config['response_mapping'] ||= {
          'output' => 'body',
          'result' => 'body.result',
          'data' => 'body.data'
        }

      when 'webhook'
        updated_config['headers'] ||= { 'Content-Type' => 'application/json' }
        updated_config['payload_template'] ||= {
          'input' => '{{input}}',
          'data' => '{{data}}',
          'context' => '{{context}}'
        }

      when 'condition'
        updated_config['input_variable'] ||= 'input'
        updated_config['output_mapping'] ||= {
          'output' => 'input',
          'result' => 'condition_result',
          'data' => 'input'
        }

      when 'loop'
        updated_config['iteration_source'] ||= 'data.items'
        updated_config['output_mapping'] ||= {
          'output' => 'results',
          'result' => 'results',
          'data' => 'results'
        }

      when 'transform'
        updated_config['input_mapping'] ||= {
          'source' => 'input',
          'data' => 'data'
        }
        updated_config['output_mapping'] ||= {
          'output' => 'transformed',
          'result' => 'transformed',
          'data' => 'transformed'
        }

      when 'delay'
        updated_config['pass_through_data'] = true
        updated_config['output_mapping'] ||= {
          'output' => 'input',
          'result' => 'input',
          'data' => 'data'
        }

      when 'human_approval'
        updated_config['approval_message'] ||= 'Please review: {{input}}'
        updated_config['notification_template'] ||= 'Approval needed for: {{data}}'
        updated_config['output_mapping'] ||= {
          'output' => 'approval_result',
          'result' => 'approval_result',
          'data' => 'input_data',
          'approved' => 'approved'
        }

      when 'sub_workflow'
        updated_config['input_mapping'] ||= {
          'input' => 'input',
          'data' => 'data',
          'context' => 'context'
        }
        updated_config['output_mapping'] ||= {
          'output' => 'output',
          'result' => 'result',
          'data' => 'data'
        }

      when 'merge'
        updated_config['output_mapping'] ||= {
          'output' => 'merged_data',
          'result' => 'merged_data',
          'data' => 'merged_data'
        }

      when 'split'
        updated_config['condition_variable'] ||= 'input'
        updated_config['output_mapping'] ||= {
          'output' => 'input',
          'data' => 'data'
        }
      end

      # Only update if configuration changed
      if updated_config != node.configuration
        node.update_column(:configuration, updated_config)
        puts "Updated node #{node.node_id} (#{node.node_type}) with aligned mappings"
      end
    end

    puts "Workflow node mapping alignment complete"
  end

  def down
    # This migration doesn't need to be reversed as it only adds defaults
    # The original configurations are preserved where they existed
    puts "Rollback not required - original configurations preserved"
  end
end
