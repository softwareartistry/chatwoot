module SamlOmniauthCallbackHandling
  extend ActiveSupport::Concern

  private

  def auth_hash
    request.env['omniauth.auth'] || super
  end

  def handle_saml_auth
    account_id = extract_saml_account_id
    relay_state = saml_relay_state

    return handle_saml_auth_error(relay_state, 'saml-not-enabled') unless saml_enabled_for_account?(account_id)

    @resource = SamlUserBuilder.new(auth_hash, account_id).perform

    if @resource.persisted?
      mark_account_as_active(account_id)
      return sign_in_saml_user(relay_state, account_id)
    end

    handle_saml_auth_error(relay_state, 'saml-authentication-failed')
  rescue SamlUserBuilder::AuthenticationFailed
    handle_saml_auth_error(relay_state, 'saml-authentication-failed')
  end

  def extract_saml_account_id
    params[:account_id] || request.env['omniauth.params']&.dig('account_id')
  end

  # Without this, the post-login redirect falls back to whichever account the
  # user was last active in (see User#active_account_user), ignoring the
  # account_id the SSO link explicitly requested.
  def mark_account_as_active(account_id)
    @resource.account_users.find_by(account_id: account_id)&.update(active_at: Time.now.utc)
  end

  def saml_relay_state
    params[:RelayState] || request.env['omniauth.params']&.dig('RelayState')
  end

  def for_mobile?(relay_state)
    relay_state.to_s.casecmp('mobile').zero?
  end

  def sign_in_saml_user(relay_state, account_id)
    return sign_in_user_on_mobile if for_mobile?(relay_state)

    sign_in_user(sso_account_id: account_id)
  end

  def sign_in_user_on_mobile
    # See comment in sign_in_user for why this is captured before skip_confirmation!
    needs_password_reset = oauth_user_needs_password_reset?
    @resource.skip_confirmation! if confirmable_enabled?
    set_random_password_if_oauth_user if needs_password_reset

    # once the resource is found and verified
    # we can just send them to the login page again with the SSO params
    # that will log them in
    encoded_email = ERB::Util.url_encode(@resource.email)
    params = { email: encoded_email, sso_auth_token: @resource.generate_sso_auth_token }.to_query

    mobile_deep_link_base = GlobalConfigService.load('MOBILE_DEEP_LINK_BASE', 'chatwootapp')
    redirect_to "#{mobile_deep_link_base}://auth/saml?#{params}", allow_other_host: true
  end

  def handle_saml_auth_error(relay_state, error)
    return redirect_to_mobile_error(error) if for_mobile?(relay_state)

    redirect_to login_page_url(error: error)
  end

  def redirect_to_mobile_error(error)
    mobile_deep_link_base = GlobalConfigService.load('MOBILE_DEEP_LINK_BASE', 'chatwootapp')
    redirect_to "#{mobile_deep_link_base}://auth/saml?error=#{ERB::Util.url_encode(error)}", allow_other_host: true
  end

  def saml_enabled_for_account?(account_id)
    return false if account_id.blank?

    account = Account.find_by(id: account_id)

    return false if account.nil?
    return false unless account.feature_enabled?('saml')

    AccountSamlSettings.find_by(account_id: account_id).present?
  end
end
