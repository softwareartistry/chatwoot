module SamlAuthenticationHelper
  def saml_user_attempting_password_auth?(email, sso_auth_token: nil)
    return false if email.blank?

    user = User.from_email(email)
    return false unless user&.provider == 'saml'

    # Administrators always keep password login as a fallback so they can never be
    # locked out of the dashboard when SAML is enabled for their account.
    return false if user.account_users.administrator.exists?

    return false if sso_auth_token.present? && user.valid_sso_auth_token?(sso_auth_token)

    true
  end

  def reject_saml_user_password_login
    return unless saml_user_attempting_password_auth?(params[:email], sso_auth_token: params[:sso_auth_token])

    message = I18n.t('messages.login_saml_user')
    render json: { success: false, message: message, errors: [message] }, status: :unauthorized
  end
end
