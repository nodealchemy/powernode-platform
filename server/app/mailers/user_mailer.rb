class UserMailer < ApplicationMailer
  default from: "noreply@powernode.dev"

  def password_reset(user)
    @user = user
    @reset_url = "#{ENV.fetch('FRONTEND_URL', 'http://localhost:3001')}/reset-password?token=#{@user.reset_token}"

    mail(
      to: @user.email,
      subject: "Password Reset Instructions - Powernode"
    )
  end
end
