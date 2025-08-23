class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class

  # UUID generation is handled by the database using gen_random_uuid()
  # No need for manual UUID generation
end
