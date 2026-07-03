# SAML SSO Provider (Community Edition)
# Adds SAML authentication support with per-account (multi-tenant) configuration.

# SAML setup proc for multi-tenant configuration
SAML_SETUP_PROC = proc do |env|
  request = ActionDispatch::Request.new(env)

  # Extract account_id from various sources
  account_id = request.params['account_id'] ||
               env['omniauth.params']&.dig('account_id')
  relay_state = request.params['RelayState'] || ''

  if account_id
    # Keep SAML request context in OmniAuth env so the callback can be processed
    # without depending on the Rails session cookie.
    env['omniauth.params'] ||= {}
    env['omniauth.params']['account_id'] = account_id
    env['omniauth.params']['RelayState'] = relay_state

    # Find SAML settings for this account
    settings = AccountSamlSettings.find_by(account_id: account_id)

    if settings
      # Configure the strategy options dynamically.
      # kc_idp_hint is passed through the library's runtime-params mechanism: the
      # incoming `idp_hint` request param is mapped onto the outgoing `kc_idp_hint`
      # SAML URL param, so omniauth-saml/ruby-saml builds (and would sign) it correctly.
      env['omniauth.strategy'].options[:idp_sso_service_url_runtime_params] = { RelayState: :RelayState, idp_hint: :kc_idp_hint }
      env['omniauth.strategy'].options[:assertion_consumer_service_url] = "#{ENV.fetch('FRONTEND_URL', 'http://localhost:3000')}/omniauth/saml/callback?account_id=#{account_id}"
      env['omniauth.strategy'].options[:sp_entity_id] = settings.sp_entity_id
      env['omniauth.strategy'].options[:idp_entity_id] = settings.idp_entity_id
      env['omniauth.strategy'].options[:idp_sso_service_url] = settings.sso_url
      env['omniauth.strategy'].options[:idp_cert] = settings.certificate
      env['omniauth.strategy'].options[:name_identifier_format] = 'urn:oasis:names:tc:SAML:1.1:nameid-format:emailAddress'
    else
      # Set a dummy certificate to avoid the error
      env['omniauth.strategy'].options[:idp_cert] = 'DUMMY'
    end
  else
    # Set a dummy certificate to avoid the error
    env['omniauth.strategy'].options[:idp_cert] = 'DUMMY'
  end
end

Rails.application.config.middleware.use OmniAuth::Builder do
  # SAML provider with setup phase for multi-tenant configuration
  provider :saml, setup: SAML_SETUP_PROC
end
