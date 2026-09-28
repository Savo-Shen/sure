# Override Active Storage blob serving to enforce authorization
Rails.application.config.to_prepare do
  module ActiveStorageAttachmentAuthorization
    extend ActiveSupport::Concern
    # Transaction and AccountStatement have bespoke checks below. The remaining
    # protected types all belong_to :family and share the family-scoped check:
    # Import covers the SureImport/PdfImport STI attachments, which store the
    # base-class name as record_type. Anything else in the whitelist fails
    # closed in `protected_attachment_authorized?` without loading the record,
    # so a stale/unknown record_type can never bypass authorization.
    # ArchivedExport is deliberately excluded: it has no family (the family is
    # deleted before archiving) and is served through the token-authenticated
    # ArchivedExportsController instead.
    FAMILY_SCOPED_RECORD_TYPES = %w[Import FamilyExport FamilyDocument].freeze
    PROTECTED_RECORD_TYPES = (FAMILY_SCOPED_RECORD_TYPES + %w[Transaction AccountStatement]).freeze

    included do
      include Authentication
      before_action :authorize_protected_attachment
    end

    private

      def authorize_protected_attachment
        # Direct uploads create unattached blobs; model/controller code authorizes the later attachment.
        return if is_a?(ActiveStorage::DirectUploadsController)
        return unless authorized_blob

        attachments = authorized_attachments
        raise ActiveRecord::RecordNotFound if attachments.empty?

        protected_attachments = attachments.select { |attachment| attachment.record_type.in?(PROTECTED_RECORD_TYPES) }
        return if protected_attachments.empty?
        return if protected_attachments.all? { |attachment| protected_attachment_authorized?(attachment) }

        raise ActiveRecord::RecordNotFound
      end

      def protected_attachment_authorized?(attachment)
        case attachment.record_type
        when "Transaction"
          transaction_attachment_authorized?(attachment)
        when "AccountStatement"
          account_statement_attachment_authorized?(attachment)
        when *FAMILY_SCOPED_RECORD_TYPES
          family_scoped_attachment_authorized?(attachment)
        else
          false
        end
      end

      def transaction_attachment_authorized?(attachment)
        transaction = attachment.record
        return false if transaction.nil?

        account = transaction.entry.account
        return false unless Current.family == account.family

        # Cross-ledger access is blocked by the family check above; this also
        # enforces intra-ledger account shares (a shared account's transactions
        # are only visible to users the account is shared with).
        Current.family.accounts.accessible_by(Current.user).exists?(account.id)
      rescue ActiveRecord::RecordNotFound, NoMethodError
        false
      end

      # Import (SureImport/PdfImport), FamilyExport and FamilyDocument all
      # belong_to :family — the record's family must be the user's active ledger.
      def family_scoped_attachment_authorized?(attachment)
        record = attachment.record
        return false if record.nil?

        record.family == Current.family
      rescue ActiveRecord::RecordNotFound, NoMethodError
        false
      end

      def account_statement_attachment_authorized?(attachment)
        statement = attachment.record
        return false if statement.nil?

        statement.viewable_by?(Current.user)
      rescue ActiveRecord::RecordNotFound
        false
      end

      def authorized_attachments
        return nil unless authorized_blob

        @authorized_attachments ||= ActiveStorage::Attachment.where(blob: authorized_blob).to_a
      end

      def authorized_blob
        @blob || @representation&.blob || disk_service_blob
      end

      def disk_service_blob
        return nil unless is_a?(ActiveStorage::DiskController) && action_name == "show"

        key = decode_verified_key&.fetch(:key, nil)
        return nil if key.blank?

        blob_key = key.to_s[%r{\Avariants/([^/]+)/}, 1] || key
        ActiveStorage::Blob.find_by(key: blob_key)
      rescue ActiveStorage::InvalidKeyError
        nil
      end

      def new_session_url
        Rails.application.routes.url_helpers.new_session_url(active_storage_auth_url_options)
      end

      def new_registration_url
        Rails.application.routes.url_helpers.new_registration_url(active_storage_auth_url_options)
      end

      def active_storage_auth_url_options
        {
          protocol: request.protocol,
          host: request.host,
          port: request.optional_port
        }.compact
      end
  end

  [
    ActiveStorage::Blobs::RedirectController,
    ActiveStorage::Blobs::ProxyController,
    ActiveStorage::Representations::RedirectController,
    ActiveStorage::Representations::ProxyController,
    (ActiveStorage::DiskController if defined?(ActiveStorage::DiskController)),
    (ActiveStorage::DirectUploadsController if defined?(ActiveStorage::DirectUploadsController))
  ].compact.each do |controller|
    controller.include ActiveStorageAttachmentAuthorization
  end
end
