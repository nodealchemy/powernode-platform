# frozen_string_literal: true

# Core's own referent on FileManagement::ErasureReferentRegistry
# (IMP-d97f6e3bbc2b): chat_message_attachments.file_object_id is a NO ACTION
# foreign key with no inverse association, so a GDPR erasure of a
# chat-attached file would raise InvalidForeignKey. The attachment's pointer
# is a convenience (`belongs_to :file_object, optional: true`; #signed_url
# already nil-guards it), so the posture is RELEASE: the pointer is
# nullified inside the file's erasure transaction and the attachment row
# stays. KNOWN RESIDUE: that row (filename, transcription, metadata,
# storage_url) is chat data, and no DELETABLE_DATA_TYPES category erases
# chat_message_attachments today — see docs/operations/compliance.md.
#
# `to_prepare`, not `after_initialize`: the registry is an autoloaded
# service, so a dev-mode reload replaces the constant and drops its handler
# map; to_prepare re-registers after every reload (and once at boot).
# Registration is replace-by-name, so re-running is idempotent.
Rails.application.config.to_prepare do
  FileManagement::ErasureReferentRegistry.register(:chat_message_attachments) do |action, payload|
    case action
    when :holds
      {}
    when :release
      Chat::MessageAttachment.release_file_object!(payload)
      nil
    end
  end
end
