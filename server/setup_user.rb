user = User.first
user.update!(password: "ComplexP@ssw0rd2024!", password_confirmation: "ComplexP@ssw0rd2024!")
user.verify_email!
puts "User ready: #{user.email}"
puts "User roles: #{user.roles.pluck(:name)}"