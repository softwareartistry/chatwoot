class DeviseOverrides::OmniauthCallbacksController < DeviseTokenAuth::OmniauthCallbacksController
  include EmailHelper

  def redirect_callbacks
    return omniauth_success if params[:provider] == 'saml'

    super
  end

  def omniauth_success
    return handle_saml_auth if auth_hash&.dig('provider') == 'saml'

    get_resource_from_auth_hash

    @resource.present? ? sign_in_user : sign_up_user
  end

  def omniauth_failure
    return super unless params[:strategy] == 'saml'

    relay_state = saml_relay_state
    error = params[:message] || 'authentication-failed'

    if for_mobile?(relay_state)
      redirect_to_mobile_error(error)
    else
      redirect_to login_page_url(error: "saml-#{error}")
    end
  end

  private

  def auth_hash
    request.env['omniauth.auth'] || super
  end

  def handle_saml_auth
    account_id = extract_saml_account_id
    relay_state = saml_relay_state

    return handle_saml_auth_error(relay_state, 'saml-not-enabled') unless saml_enabled_for_account?(account_id)

    @resource = SamlUserBuilder.new(auth_hash, account_id).perform

    return sign_in_saml_user(relay_state) if @resource.persisted?

    handle_saml_auth_error(relay_state, 'saml-authentication-failed')
  rescue SamlUserBuilder::AuthenticationFailed
    handle_saml_auth_error(relay_state, 'saml-authentication-failed')
  end

  def extract_saml_account_id
    params[:account_id] || request.env['omniauth.params']&.dig('account_id')
  end

  def saml_relay_state
    params[:RelayState] || request.env['omniauth.params']&.dig('RelayState')
  end

  def for_mobile?(relay_state)
    relay_state.to_s.casecmp('mobile').zero?
  end

  def sign_in_saml_user(relay_state)
    return sign_in_user_on_mobile if for_mobile?(relay_state)

    sign_in_user
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

  def sign_in_user
    # Capture before skip_confirmation! sets confirmed_at, which would
    # make oauth_user_needs_password_reset? return false and skip the
    # password reset for persisted unconfirmed users.
    needs_password_reset = oauth_user_needs_password_reset?
    @resource.skip_confirmation! if confirmable_enabled?
    set_random_password_if_oauth_user if needs_password_reset

    # once the resource is found and verified
    # we can just send them to the login page again with the SSO params
    # that will log them in
    encoded_email = ERB::Util.url_encode(@resource.email)
    redirect_to login_page_url(email: encoded_email, sso_auth_token: @resource.generate_sso_auth_token)
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

  def sign_up_user
    return redirect_to login_page_url(error: 'no-account-found') unless account_signup_allowed?
    return redirect_to login_page_url(error: 'business-account-only') unless validate_signup_email_is_business_domain?

    create_account_for_user
    set_random_password_if_oauth_user
    token = @resource.send(:set_reset_password_token)
    frontend_url = ENV.fetch('FRONTEND_URL', nil)
    redirect_to "#{frontend_url}/app/auth/password/edit?config=default&reset_password_token=#{token}"
  end

  def login_page_url(error: nil, email: nil, sso_auth_token: nil)
    frontend_url = ENV.fetch('FRONTEND_URL', nil)
    params = { email: email, sso_auth_token: sso_auth_token }.compact
    params[:error] = error if error.present?

    "#{frontend_url}/app/login?#{params.to_query}"
  end

  def account_signup_allowed?
    GlobalConfigService.account_signup_enabled?
  end

  def resource_class(_mapping = nil)
    User
  end

  def get_resource_from_auth_hash # rubocop:disable Naming/AccessorMethodName
    email = auth_hash.dig('info', 'email')
    @resource = resource_class.from_email(email)
  end

  def validate_signup_email_is_business_domain?
    # return true if the user is a business account, false if it is a blocked domain account
    Account::SignUpEmailValidationService.new(auth_hash['info']['email']).perform
  rescue CustomExceptions::Account::InvalidEmail
    false
  end

  def create_account_for_user
    @resource, @account = AccountBuilder.new(
      account_name: extract_domain_without_tld(auth_hash['info']['email']),
      user_full_name: auth_hash['info']['name'],
      email: auth_hash['info']['email'],
      locale: I18n.locale,
      confirmed: auth_hash['info']['email_verified']
    ).perform
    Avatar::AvatarFromUrlJob.perform_later(@resource, auth_hash['info']['image'])
  end

  def oauth_user_needs_password_reset?
    @resource.present? && (@resource.new_record? || !@resource.confirmed?)
  end

  def set_random_password_if_oauth_user
    # Password must satisfy secure_password requirements (uppercase, lowercase, number, special char)
    @resource.update(password: "#{SecureRandom.hex(16)}aA1!") if @resource.persisted?
  end

  def default_devise_mapping
    'user'
  end
end

DeviseOverrides::OmniauthCallbacksController.prepend_mod_with('DeviseOverrides::OmniauthCallbacksController')
