Gem::Specification.new do |spec|
  spec.name        = "powernode_enterprise"
  spec.version     = "0.1.0"
  spec.authors     = ["Powernode"]
  spec.summary     = "Powernode Enterprise Edition"
  spec.description = "Enterprise features for Powernode: BaaS, governance, revenue intelligence, credits, marketplace monetization, and more."
  spec.license     = "Proprietary"
  spec.files       = Dir["app/**/*", "config/**/*", "db/**/*", "lib/**/*"]

  spec.add_dependency "rails", "~> 8.1"
end
