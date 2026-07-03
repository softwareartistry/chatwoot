module Enterprise::DeviseOverrides::OmniauthCallbacksController
  private

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
