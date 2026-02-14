# frozen_string_literal: true

module A2aArtifactExtractionConcern
  extend ActiveSupport::Concern

  private

  def extract_artifacts(response)
    artifacts = []

    # Extract code blocks as artifacts
    response.to_s.scan(/```(\w+)?\n(.*?)```/m) do |lang, code|
      artifacts << {
        'id' => SecureRandom.uuid,
        'name' => "code_#{artifacts.size + 1}.#{lang || 'txt'}",
        'mime_type' => mime_type_for_language(lang),
        'parts' => [{ 'type' => 'text', 'text' => code }]
      }
    end

    # Extract JSON blocks as data artifacts
    response.to_s.scan(/```json\n(.*?)```/m) do |json|
      parsed_data = begin
        JSON.parse(json[0])
      rescue JSON::ParserError
        json[0]
      end
      artifacts << {
        'id' => SecureRandom.uuid,
        'name' => "data_#{artifacts.size + 1}.json",
        'mime_type' => 'application/json',
        'parts' => [{ 'type' => 'data', 'data' => parsed_data }]
      }
    end

    artifacts
  end

  def mime_type_for_language(lang)
    case lang&.downcase
    when 'python', 'py' then 'text/x-python'
    when 'javascript', 'js' then 'text/javascript'
    when 'typescript', 'ts' then 'text/typescript'
    when 'ruby', 'rb' then 'text/x-ruby'
    when 'json' then 'application/json'
    when 'yaml', 'yml' then 'text/yaml'
    when 'html' then 'text/html'
    when 'css' then 'text/css'
    when 'sql' then 'text/x-sql'
    when 'bash', 'sh' then 'text/x-shellscript'
    else 'text/plain'
    end
  end
end
