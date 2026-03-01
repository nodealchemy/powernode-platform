# frozen_string_literal: true

module RefreshTokenCookie
  extend ActiveSupport::Concern

  included do
    include ActionController::Cookies
  end

  private

  def set_refresh_cookie(token)
    cookies[:refresh_token] = {
      value: token,
      httponly: true,
      secure: !Rails.env.local?,
      same_site: :strict,
      path: "/api/v1/auth",
      expires: 7.days.from_now
    }
  end

  def delete_refresh_cookie
    cookies.delete(:refresh_token, path: "/api/v1/auth")
  end
end
