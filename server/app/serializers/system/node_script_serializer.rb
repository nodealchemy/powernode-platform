# frozen_string_literal: true

module System
  class NodeScriptSerializer
    def initialize(script)
      @script = script
    end

    def as_json
      {
        id: @script.id,
        name: @script.name,
        description: @script.description,
        variety: @script.variety,
        data: @script.data,
        enabled: @script.enabled,
        public: @script.public,
        created_at: @script.created_at,
        updated_at: @script.updated_at
      }
    end
  end
end
