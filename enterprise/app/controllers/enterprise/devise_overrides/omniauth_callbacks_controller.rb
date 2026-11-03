module Enterprise::DeviseOverrides::OmniauthCallbacksController
  # SAML is handled OSS-side for this installation (see
  # app/controllers/concerns/saml_omniauth_callback_handling.rb), not as an
  # enterprise-gated feature, so upstream's enterprise SAML implementation is
  # intentionally not pulled in here — prepending a second definition of these
  # methods would shadow the OSS ones (prepend wins method resolution) and
  # drop OSS-only fixes like the post-login active-account retention.
  SHOPIFY_BILLING_REDIRECT_PATTERN = %r{\Asettings/billing(?:\?[^#]*)?\z}

  private

  def allowed_google_oauth_redirect?(redirect_url)
    super || redirect_url.match?(SHOPIFY_BILLING_REDIRECT_PATTERN)
  end

  def create_account_for_user
    super
    record_marketing_attribution
  end

  def record_marketing_attribution
    return if @account.blank?

    Internal::Accounts::MarketingAttributionService.new(account: @account, cookies: cookies).perform
  rescue StandardError => e
    ChatwootExceptionTracker.new(e).capture_exception
  end
end
