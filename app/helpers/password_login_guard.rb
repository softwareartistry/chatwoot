module PasswordLoginGuard
  def reject_password_login_when_disabled
    return if GlobalConfigService.load('ENABLE_EMAIL_PASSWORD_LOGIN', 'true').to_s != 'false'
    return if valid_sso_auth_token_request?

    message = I18n.t('messages.password_login_disabled')
    render json: { success: false, message: message, errors: [message] }, status: :forbidden
  end

  def valid_sso_auth_token_request?
    return false if params[:sso_auth_token].blank? || params[:email].blank?

    User.from_email(params[:email])&.valid_sso_auth_token?(params[:sso_auth_token]) || false
  end
end
