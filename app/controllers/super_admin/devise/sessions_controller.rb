# frozen_string_literal: true

# When SUPER_ADMIN_SSO_ENABLED is set, super admin is gated behind a reverse proxy
# (e.g. oauth2-proxy) that authenticates against an IdP and passes identity via
# trusted request headers. Password login is bypassed entirely in that mode: the
# proxy is expected to strip any client-supplied value for these headers before
# setting them from the authenticated session, and SUPER_ADMIN_SSO_SECRET is a
# second factor so a misconfigured auth_request block can't be used to spoof the
# email header alone.
class SuperAdmin::Devise::SessionsController < Devise::SessionsController
  PROXY_EMAIL_HEADER = ENV.fetch('SUPER_ADMIN_SSO_EMAIL_HEADER', 'X-Auth-Request-Email')
  PROXY_SECRET_HEADER = ENV.fetch('SUPER_ADMIN_SSO_SECRET_HEADER', 'X-Auth-Request-Proxy-Secret')

  def new
    return super unless sso_proxy_enabled?

    admin = super_admin_from_proxy_headers
    return render_proxy_auth_failed unless admin

    sign_in(:super_admin, admin)
    redirect_to super_admin_users_path
  end

  def create
    return render_proxy_auth_failed if sso_proxy_enabled?
    return redirect_to(super_admin_session_path, flash: { error: @error_message }) unless valid_credentials?

    sign_in(:super_admin, @super_admin)
    flash.discard
    redirect_to super_admin_users_path
  end

  def destroy
    sign_out
    flash.discard
    redirect_to '/'
  end

  private

  def sso_proxy_enabled?
    ENV.fetch('SUPER_ADMIN_SSO_ENABLED', 'false').to_s == 'true'
  end

  def super_admin_from_proxy_headers
    return nil unless valid_proxy_secret?

    email = request.headers[PROXY_EMAIL_HEADER].presence
    return nil unless email

    SuperAdmin.from_email(email)
  end

  # Fails closed: with no secret configured, this never authenticates via headers.
  def valid_proxy_secret?
    expected_secret = ENV.fetch('SUPER_ADMIN_SSO_SECRET', nil)
    return false if expected_secret.blank?

    ActiveSupport::SecurityUtils.secure_compare(expected_secret, request.headers[PROXY_SECRET_HEADER].to_s)
  end

  def render_proxy_auth_failed
    render plain: 'Forbidden', status: :forbidden
  end

  def valid_credentials?
    @super_admin = SuperAdmin.find_by!(email: params[:super_admin][:email])
    raise StandardError, 'Invalid Password' unless @super_admin.valid_password?(params[:super_admin][:password])

    true
  rescue StandardError => e
    Rails.logger.error e.message
    @error_message = 'Invalid credentials. Please try again.'
    false
  end
end
