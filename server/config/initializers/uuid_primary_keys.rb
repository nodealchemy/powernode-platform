# frozen_string_literal: true

# Configure Rails to use UUIDv7 as the default primary key type
Rails.application.configure do
  config.generators do |g|
    g.orm :active_record, primary_key_type: :string
  end
end
