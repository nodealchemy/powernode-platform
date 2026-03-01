# frozen_string_literal: true

module A2a
  module Skills
    class ChatSkills
      class << self
        def send_message(account:, user:, params:)
          session = Chat::Session.find(params[:session_id])
          verify_access!(account, session.channel)

          gateway = Chat::GatewayService.new(session.channel)
          result = gateway.send_message(
            session,
            params[:content],
            message_type: params[:message_type] || "text"
          )

          {
            message_id: result[:message]&.id,
            delivery_status: result[:message]&.delivery_status
          }
        end

        def list_channels(account:, user:, params:)
          channels = account.chat_channels

          channels = channels.by_platform(params[:platform]) if params[:platform].present?
          channels = channels.where(status: params[:status]) if params[:status].present?

          {
            channels: channels.map(&:channel_summary)
          }
        end

        def get_session(account:, user:, params:)
          session = Chat::Session.joins(:channel)
                                 .where(chat_channels: { account_id: account.id })
                                 .find(params[:session_id])

          {
            session: session.session_details
          }
        end

        def transfer_session(account:, user:, params:)
          session = Chat::Session.joins(:channel)
                                 .where(chat_channels: { account_id: account.id })
                                 .find(params[:session_id])

          new_agent = account.ai_agents.find(params[:agent_id])

          session_manager = Chat::SessionManager.new(session.channel)
          session_manager.transfer_session(session, new_agent)

          { success: true }
        end

        def transcribe_voice(account:, user:, params:)
          attachment = Chat::MessageAttachment
                         .joins(message: { session: :channel })
                         .where(chat_channels: { account_id: account.id })
                         .find(params[:attachment_id])

          unless attachment.audio?
            raise ArgumentError, "Attachment is not an audio file"
          end

          if attachment.transcription.present?
            return { transcription: attachment.transcription }
          end

          # Trigger transcription job
          WorkerJobService.enqueue_chat_transcription(attachment.id)

          { transcription: nil, status: "processing" }
        end

        def get_media(account:, user:, params:)
          attachment = Chat::MessageAttachment
                         .joins(message: { session: :channel })
                         .where(chat_channels: { account_id: account.id })
                         .find(params[:attachment_id])

          unless attachment.safe_to_use?
            raise SecurityError, "Attachment not available - pending security scan"
          end

          {
            url: attachment.download_url,
            mime_type: attachment.mime_type,
            filename: attachment.filename
          }
        end

        private

        def verify_access!(account, channel)
          unless channel.account_id == account.id
            raise SecurityError, "Access denied to channel"
          end
        end
      end
    end
  end
end
