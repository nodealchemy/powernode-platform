# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name          = "powernode_marketing"
  spec.version       = "0.1.0"
  spec.authors       = ["Everett C. Haimes III"]
  spec.summary       = "Marketing extension for Powernode"
  spec.description   = "Marketing campaigns, content calendar, email lists, social media management, and campaign analytics."
  spec.license       = "Proprietary"

  spec.files         = Dir["{app,config,db,lib}/**/*"]
  spec.require_paths = ["lib"]

  spec.add_dependency "rails", ">= 8.0"
end
