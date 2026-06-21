FactoryBot.define do
  factory :role_permission do
    role
    # Permissions are code-defined; a grant references a catalog permission by
    # NAME (validated against Permissions.all_permissions). Use a real catalog
    # permission so the catalog-membership validation passes.
    permission_name { 'users.read' }
  end
end
