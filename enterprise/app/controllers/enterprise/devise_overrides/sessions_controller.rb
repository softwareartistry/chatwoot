module Enterprise::DeviseOverrides::SessionsController
  # SAML password-blocking is handled OSS-side (SamlAuthenticationHelper is
  # already included directly into DeviseOverrides::SessionsController), so
  # upstream's enterprise-gated duplicate of that same check is intentionally
  # not pulled in here. DeviceVerificationConcern is unrelated to SAML and is
  # kept.
  include Enterprise::DeviseOverrides::DeviceVerificationConcern

  def render_create_success
    create_audit_event('sign_in') unless @impersonation
    super
  end

  def destroy
    create_audit_event('sign_out') unless impersonation_session?
    super
  end

  def impersonation_session?
    token_entry = @resource&.tokens&.dig(@token&.client) || {}
    token_entry['impersonation'] || token_entry[:impersonation]
  end

  def create_audit_event(action)
    return unless @resource

    account_ids = @resource.accounts.ids
    return if account_ids.empty?

    rows = audit_event_rows(action, account_ids)
    inserted = Enterprise::AuditLog.insert_all!(rows, returning: %w[id]) # rubocop:disable Rails/SkipsModelValidations
    enqueue_session_ip_lookup(rows.first[:remote_address], account_ids, inserted.rows.flatten)
  end

  # Geolocation is optional, so nothing here may interrupt authentication.
  def enqueue_session_ip_lookup(remote_address, account_ids, audit_ids)
    return if remote_address.blank?
    return unless Account.feature_ip_lookup.exists?(id: account_ids)

    Enterprise::AuditLogSessionIpLookupJob.perform_later(audit_ids, remote_address)
  rescue StandardError => e
    Rails.logger.warn "Enterprise::AuditLogSessionIpLookupJob could not be enqueued: #{e.message}"
  end

  def audit_event_rows(action, account_ids)
    base_version = Enterprise::AuditLog.unscoped.auditable_finder(@resource.id, 'User').maximum(:version) || 0
    request_uuid = ::Audited.store[:current_request_uuid].presence || SecureRandom.uuid
    created_at = Time.zone.now

    account_ids.each_with_index.map do |account_id, index|
      {
        auditable_id: @resource.id,
        auditable_type: 'User',
        user_id: @resource.id,
        user_type: 'User',
        username: @resource.email,
        action: action,
        associated_id: account_id,
        associated_type: 'Account',
        version: base_version + index + 1,
        request_uuid: request_uuid,
        remote_address: ::Audited.store[:current_remote_address],
        created_at: created_at
      }
    end
  end
end
