# frozen_string_literal: true

module Notifications
  # The plaintext of one push (docs/dev/PUSH.md): the inbox's own sentence in
  # the recipient's locale, or the generic copy when the device hides the
  # content, plus where it opens and the unread count. Never coordinates,
  # workout content beyond the title the inbox shows, or remote HTML. The
  # encrypted plaintext stays under 2 KB: the body is shortened to fit.
  class PushPayload
    VERSION = 1
    MAX_BYTES = 2_048
    MAX_TITLE_LENGTH = 100
    HIDDEN_THREAD = "allure"
    ELLIPSIS = "…"

    def initialize(notification:, subscription:)
      @notification = notification
      @subscription = subscription
      @user = notification.user
    end

    def to_h
      config = Allure::Federation.config
      {
        "v" => VERSION,
        "origin" => config.base_url,
        "id" => @notification.id.to_s,
        "url" => config.base_url + Rails.application.routes.url_helpers.notification_path(@notification.id),
        "title" => title,
        "body" => body,
        "badge" => @user.notifications.unread.count,
        "thread" => @subscription.hide_content? ? HIDDEN_THREAD : @notification.kind
      }
    end

    def to_json(*)
      payload = to_h
      json = JSON.generate(payload)
      while json.bytesize >= MAX_BYTES && payload["body"] != ELLIPSIS
        payload["body"] = shorten(payload["body"], json.bytesize - MAX_BYTES + 1)
        json = JSON.generate(payload)
      end
      json
    end

    # The sentence `NotificationsHelper#notification_text` shows in the inbox,
    # rendered through the application's own view context (route helpers,
    # actor helpers, the recipient as the current account). The partial is a
    # text template, so nothing is HTML-escaped: the device shows plain text.
    def self.text(notification, session:)
      rendered = I18n.with_locale(notification.user.locale) do
        Current.set(session:) do
          ApplicationController.renderer.render(partial: "notifications/push_text", formats: [ :text ],
                                                locals: { notification: })
        end
      end
      rendered.to_str.squish
    end

    private

    def title
      name = ENV.fetch("INSTANCE_NAME", "").strip.presence || Allure::Federation.config.host
      name.truncate(MAX_TITLE_LENGTH, omission: ELLIPSIS)
    end

    def body
      return I18n.with_locale(@user.locale) { I18n.t("push.hidden_body") } if @subscription.hide_content?

      text = self.class.text(@notification, session: @subscription.session)
      text.presence || I18n.with_locale(@user.locale) { I18n.t("push.hidden_body") }
    end

    # Drops at least `excess` bytes (JSON escaping counted generously) and
    # ends on an ellipsis.
    def shorten(text, excess)
      budget = text.bytesize - (excess * 2) - ELLIPSIS.bytesize
      return ELLIPSIS if budget <= 0

      text.byteslice(0, budget).scrub("").sub(/\s+\S*\z/, "") + ELLIPSIS
    end
  end
end
