# frozen_string_literal: true

class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class

  # Include UuidGenerator by default for all models
  # This ensures all models use UUIDv7 format for primary keys
  include UuidGenerator
end
