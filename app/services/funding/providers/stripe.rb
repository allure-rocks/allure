# frozen_string_literal: true

require "json"
require "uri"

module Funding
  module Providers
    # Rails-facing Stripe adapter (docs/dev/FUNDING.md). The webhook body only
    # supplies an event type and object id after HMAC verification; every fact
    # used for binding, state or money is read back through the pinned API.
    class Stripe
      PORTAL_HOST = "billing.stripe.com"
      BILLING_REASONS = %w[subscription_create subscription_cycle].freeze
      SUPPORTED_EVENTS = %w[
        checkout.session.completed invoice.paid invoice.payment_failed
        customer.subscription.updated customer.subscription.deleted charge.refunded
        refund.created refund.updated
        charge.dispute.created charge.dispute.updated charge.dispute.closed
      ].freeze
      # Only settled outcomes are recorded; pending/canceled refund statuses
      # carry no reviewable fact. A dispute whose charge was refunded returned
      # the funds, so it is a loss for the operator.
      REFUND_STATUSES = { "succeeded" => "succeeded", "failed" => "failed" }.freeze
      DISPUTE_STATUSES = {
        "warning_needs_response" => "open", "warning_under_review" => "open", "warning_closed" => "won",
        "needs_response" => "open", "under_review" => "open", "charge_refunded" => "lost",
        "won" => "won", "lost" => "lost"
      }.freeze
      STATUSES = {
        "incomplete" => "incomplete", "incomplete_expired" => "incomplete", "trialing" => "incomplete",
        "active" => "active", "past_due" => "past_due", "unpaid" => "past_due",
        "paused" => "paused", "canceled" => "canceled"
      }.freeze

      class Unsupported < StandardError; end
      private_constant :Unsupported

      class << self
        def slug = "stripe"

        def enabled? = Allure::Funding::Config.stripe_enabled?

        # The HTTPS origin of Stripe's hosted customer portal, allowed in the
        # Content-Security-Policy `form-action` (Chrome checks the redirect of
        # the portal form's POST too).
        def portal_origin = "https://#{PORTAL_HOST}"

        def checkout_url(tier:, reference:)
          link = Allure::Funding::Config.stripe_checkout_link(tier)
          price = Allure::Funding::Config.stripe_price(tier)
          return unless link && price
          unless reference.is_a?(String) && reference.match?(/\A[A-Za-z0-9_-]{1,200}\z/)
            raise ArgumentError, "invalid Stripe checkout reference"
          end

          uri = URI.parse(link)
          query = URI.decode_www_form(uri.query.to_s).reject { |key, _value| key == "client_reference_id" }
          uri.query = URI.encode_www_form(query + [ [ "client_reference_id", reference ] ])
          uri.to_s
        end

        def verify!(request)
          payload = Allure::Funding::Stripe::Signature.verify!(
            request.raw_post, request.get_header("HTTP_STRIPE_SIGNATURE"),
            secret: Allure::Funding::Config.stripe_webhook_secret
          )
          event = JSON.parse(payload)
          type = event["type"]
          return nil unless SUPPORTED_EVENTS.include?(type)

          object_id = identifier(event.dig("data", "object", "id"))
          case type
          when "checkout.session.completed" then checkout_notification(object_id)
          when "invoice.paid" then invoice_notification(object_id, kind: "payment")
          when "invoice.payment_failed" then failed_invoice_notification(object_id)
          when "customer.subscription.updated", "customer.subscription.deleted" then subscription_notification(object_id)
          when "charge.refunded" then refunded_charge_notification(object_id)
          when "refund.created", "refund.updated" then refund_notification(object_id)
          when "charge.dispute.created", "charge.dispute.updated", "charge.dispute.closed" then dispute_notification(object_id)
          end
        rescue JSON::ParserError
          raise Allure::Funding::Providers::VerificationError, "invalid Stripe event JSON"
        rescue Unsupported
          nil
        end

        def portal_url(subscription:, return_url:)
          validate_local_subscription!(subscription)
          validate_return_url!(return_url)
          response = client.post_form("/v1/billing_portal/sessions", {
            "customer" => subscription.customer_id, "return_url" => return_url
          })
          url = response["url"].to_s
          uri = URI.parse(url)
          raise Allure::Funding::Stripe::Error, "Stripe portal URL is invalid" unless uri.is_a?(URI::HTTPS) && uri.host == PORTAL_HOST

          uri.to_s
        rescue URI::InvalidURIError
          raise Allure::Funding::Stripe::Error, "Stripe portal URL is invalid"
        end

        # Stops future charges without changing any locally recorded paid
        # period. Called even while the public funding switch is off.
        def cancel(subscription:)
          validate_local_subscription!(subscription)
          path = "/v1/subscriptions/#{identifier(subscription.external_id)}"
          current = client.get(path)
          unless stopping?(current)
            current = if %w[incomplete incomplete_expired trialing].include?(current["status"])
                        client.delete(path)
            else
                        client.post_form(path, { "cancel_at_period_end" => "true" })
            end
          end
          unless stopping?(current)
            raise Allure::Funding::Stripe::Error, "Stripe subscription cancellation was not confirmed"
          end

          cancellation_state(subscription, current)
        rescue Allure::Funding::Stripe::Error => error
          # A 404 is terminal only when the original provider account explains
          # it: the persisted customer must still be retrievable there and the
          # subscription absent from its list. Wrong-account or wrong-mode
          # credentials 404 both lookups and must fail closed (PAY-104).
          raise unless error.status == 404 && subscription_gone?(subscription)

          canceled_state(subscription)
        end

        # Authenticated recovery uses the exact same invoice normalization and
        # durable binding path as a webhook, and also inspects refund and
        # dispute state (PAY-105). With no `since`, replay all pages; the
        # recurring job supplies a bounded window instead.
        def reconcile(since: nil)
          processed = 0
          [
            [ "/v1/invoices", { "status" => "paid" }, ->(id) { invoice_notification(id, kind: "payment") } ],
            [ "/v1/refunds", {}, ->(id) { refund_notification(id) } ],
            [ "/v1/disputes", {}, ->(id) { dispute_notification(id) } ]
          ].each do |collection, params, build|
            params = params.merge("limit" => 100)
            params["created[gte]"] = since.to_i if since
            loop do
              page = client.get(collection, params)
              rows = page["data"]
              raise Allure::Funding::Stripe::Error, "Stripe recovery page is malformed" unless rows.is_a?(Array)

              rows.each do |row|
                notification = build.call(identifier(row["id"]))
                next unless notification

                yield notification if block_given?
                processed += 1
              end
              break unless page["has_more"] && rows.any?

              params["starting_after"] = identifier(rows.last["id"])
            end
          end
          processed
        rescue Unsupported
          raise Allure::Funding::Stripe::Error, "Stripe recovery page is malformed"
        end

        private

        def client = Allure::Funding::Stripe::Client.new

        def checkout_notification(session_id)
          ignore_unsupported do
            session = fetch_object("/v1/checkout/sessions", session_id)
            unless session["mode"] == "subscription" && session["status"] == "complete"
              raise Unsupported, "not a completed subscription checkout"
            end
            subscription_id = related_id(session["subscription"])
            customer_id = related_id(session["customer"])
            subscription = fetch_object("/v1/subscriptions", subscription_id)
            state = subscription_state(subscription)
            binding = binding_for_session(session, subscription_id:, customer_id:)
            notification(binding:, state:)
          end
        end

        def invoice_notification(invoice_id, kind:)
          ignore_unsupported do
            invoice = fetch_object("/v1/invoices", invoice_id)
            subscription_id = related_id(invoice["subscription"])
            event = invoice_event(invoice, kind:, subscription_id:, reference: nil)
            subscription = fetch_object("/v1/subscriptions", subscription_id)
            state = subscription_state(subscription)
            binding = binding_for_subscription(subscription_id, customer_id: state.customer_id, fallback_tier: nil)
            # The invoice line's configured price is the authoritative tier of
            # the recorded payment; the checkout's tier only establishes the
            # durable account association and must never overwrite it (PAY-103).
            event = event.with(reference: binding.reference)
            notification(event:, binding:, state:)
          end
        end

        def failed_invoice_notification(invoice_id)
          ignore_unsupported do
            invoice = fetch_object("/v1/invoices", invoice_id)
            subscription_id = related_id(invoice["subscription"])
            state = subscription_state(fetch_object("/v1/subscriptions", subscription_id))
            notification(state:)
          end
        end

        def subscription_notification(subscription_id)
          ignore_unsupported do
            notification(state: subscription_state(fetch_object("/v1/subscriptions", subscription_id)))
          end
        end

        def refunded_charge_notification(charge_id)
          ignore_unsupported do
            charge = fetch_object("/v1/charges", charge_id)
            invoice_notification(related_id(charge["invoice"]), kind: "refund")
          end
        end

        # A refund object carries its own identity, amount and outcome (PAY-105);
        # the original payment is the invoice behind its charge.
        def refund_notification(refund_id)
          ignore_unsupported do
            refund = fetch_object("/v1/refunds", refund_id)
            status = REFUND_STATUSES[refund["status"]]
            raise Unsupported, "unsupported refund status" unless status

            payment_external_id = payment_external_id_for(related_id(refund["charge"]))
            raise Unsupported, "refund has no invoice" unless payment_external_id

            notification(reversal: Allure::Funding::Reversal.new(
              kind: "refund", external_id: identifier(refund["id"]), status:,
              amount_cents: integer(refund["amount"], positive: true), currency: currency(refund["currency"]),
              reported_at: timestamp(refund["created"]), payment_external_id:
            ))
          end
        end

        def dispute_notification(dispute_id)
          ignore_unsupported do
            dispute = fetch_object("/v1/disputes", dispute_id)
            status = DISPUTE_STATUSES[dispute["status"]]
            raise Unsupported, "unsupported dispute status" unless status

            payment_external_id = payment_external_id_for(related_id(dispute["charge"]))
            raise Unsupported, "dispute has no charge" unless payment_external_id

            notification(reversal: Allure::Funding::Reversal.new(
              kind: "dispute", external_id: identifier(dispute["id"]), status:,
              amount_cents: integer(dispute["amount"], positive: true), currency: currency(dispute["currency"]),
              reported_at: timestamp(dispute["created"]), payment_external_id:
            ))
          end
        end

        # The original paid invoice identity behind a charge.
        def payment_external_id_for(charge_id)
          return nil if charge_id.nil?

          charge = fetch_object("/v1/charges", charge_id)
          related_id(charge["invoice"])
        end

        def invoice_event(invoice, kind:, subscription_id:, reference:)
          unless invoice["status"] == "paid" && invoice["paid"] == true && invoice["paid_out_of_band"] == false &&
                 invoice["collection_method"] == "charge_automatically" && BILLING_REASONS.include?(invoice["billing_reason"])
            raise Unsupported, "not an automatically paid annual subscription invoice"
          end
          amount = integer(invoice["amount_paid"], positive: true)
          integer(invoice["total"], positive: true)
          integer(invoice["amount_remaining"])
          raise Unsupported, "invoice is not settled" unless invoice["amount_remaining"].zero?
          raise Unsupported, "invoice has no settled charge" if related_id(invoice["charge"]).nil?

          line = supported_invoice_line(invoice["lines"])
          price_tier(line["price"])
          starts_at = timestamp(line.dig("period", "start"))
          expires_at = timestamp(line.dig("period", "end"))
          raise Unsupported, "invalid billed period" unless expires_at > starts_at

          Allure::Funding::Event.new(
            kind:, external_id: identifier(invoice["id"]), tier: price_tier(line["price"]), reference:,
            paid_at: timestamp(invoice.dig("status_transitions", "paid_at")), amount_cents: amount,
            currency: currency(invoice["currency"]), subscription_id:, period_start: starts_at, period_end: expires_at
          )
        end

        def supported_invoice_line(lines)
          unless lines.is_a?(Hash) && lines["has_more"] == false && lines["data"].is_a?(Array) && lines["data"].one?
            raise Unsupported, "ambiguous invoice lines"
          end
          line = lines["data"].first
          unless line["type"] == "subscription" && line["proration"] == false && line["quantity"] == 1
            raise Unsupported, "unsupported invoice line"
          end
          price_tier(line["price"])
          line
        end

        def binding_for_subscription(subscription_id, customer_id:, fallback_tier:)
          page = client.get("/v1/checkout/sessions", { "subscription" => subscription_id, "limit" => 100 })
          sessions = page["data"]
          raise Unsupported, "malformed checkout list" unless sessions.is_a?(Array)

          session_id = sessions.filter_map { |session| session["id"] if session["mode"] == "subscription" }.first
          return unmatched_binding(subscription_id, customer_id:, tier: fallback_tier) unless session_id

          session = fetch_object("/v1/checkout/sessions", identifier(session_id))
          binding_for_session(session, subscription_id:, customer_id:)
        rescue Unsupported
          unmatched_binding(subscription_id, customer_id:, tier: fallback_tier)
        end

        def binding_for_session(session, subscription_id:, customer_id:)
          unless related_id(session["subscription"]) == subscription_id && related_id(session["customer"]) == customer_id
            raise Unsupported, "checkout relationship mismatch"
          end
          lines = client.get("/v1/checkout/sessions/#{identifier(session['id'])}/line_items", { "limit" => 100 })
          tier = supported_checkout_tier(lines)
          reference = session["client_reference_id"]
          reference = nil unless reference.is_a?(String) && reference.length <= Funding::Reference::MAX_LENGTH
          Allure::Funding::CheckoutBinding.new(
            subscription_id:, customer_id:, tier:, reference:, created_at: timestamp(session["created"])
          )
        end

        def supported_checkout_tier(lines)
          unless lines.is_a?(Hash) && lines["has_more"] == false && lines["data"].is_a?(Array) && lines["data"].one?
            raise Unsupported, "ambiguous checkout lines"
          end
          line = lines["data"].first
          raise Unsupported, "unsupported checkout quantity" unless line["quantity"] == 1

          price_tier(line["price"])
        end

        def unmatched_binding(subscription_id, customer_id:, tier:)
          Allure::Funding::CheckoutBinding.new(
            subscription_id:, customer_id:, tier:, reference: nil, created_at: nil
          )
        end

        def subscription_state(subscription)
          subscription_id = identifier(subscription["id"])
          customer_id = related_id(subscription["customer"])
          items = subscription["items"]
          unless items.is_a?(Hash) && items["has_more"] == false && items["data"].is_a?(Array) && items["data"].one?
            raise Unsupported, "ambiguous subscription items"
          end
          item = items["data"].first
          raise Unsupported, "unsupported subscription quantity" unless item["quantity"] == 1

          status = STATUSES[subscription["status"]]
          raise Unsupported, "unsupported subscription status" unless status

          Allure::Funding::SubscriptionState.new(
            subscription_id:, customer_id:, tier: price_tier(item["price"]), status:,
            cancel_at_period_end: scheduled_cancellation?(subscription),
            canceled_at: optional_timestamp(subscription["canceled_at"])
          )
        end

        # Stripe schedules a cancellation either with the legacy
        # cancel_at_period_end flag or with cancel_at (a timestamp — the
        # hosted portal cancels this way); for an annual subscription both
        # mean the renewal stops at the paid period's end.
        def scheduled_cancellation?(subscription)
          subscription["cancel_at_period_end"] == true || subscription["cancel_at"].is_a?(Integer)
        end

        def canceled_state(subscription)
          Allure::Funding::SubscriptionState.new(
            subscription_id: subscription.external_id, customer_id: subscription.customer_id,
            tier: subscription.tier, status: "canceled", cancel_at_period_end: false, canceled_at: Time.current
          )
        end

        # True only when the subscription is verifiably gone from the persisted
        # customer's subscription list in the account that answers. The stored
        # customer_id is the provenance anchor tying the credentials to the
        # original Stripe account: if the customer is not retrievable (or the
        # list call fails), the 404 is unexplained and this raises, leaving the
        # cancellation unresolved instead of trusted (PAY-104).
        def subscription_gone?(subscription)
          customer_id = identifier(subscription.customer_id)
          customer = client.get("/v1/customers/#{customer_id}")
          raise Allure::Funding::Stripe::Error, "Stripe customer read-back identity mismatch" unless customer["id"] == customer_id

          params = { "status" => "all", "limit" => 100 }
          loop do
            page = client.get("/v1/customers/#{customer_id}/subscriptions", params)
            rows = page["data"]
            raise Allure::Funding::Stripe::Error, "Stripe subscription list is malformed" unless rows.is_a?(Array)

            return false if rows.any? { |row| row["id"] == subscription.external_id }
            break unless page["has_more"] && rows.any?

            params["starting_after"] = identifier(rows.last["id"])
          end
          true
        end

        def cancellation_state(subscription, current)
          Allure::Funding::SubscriptionState.new(
            subscription_id: subscription.external_id, customer_id: subscription.customer_id,
            tier: subscription.tier, status: STATUSES.fetch(current["status"], subscription.status),
            cancel_at_period_end: scheduled_cancellation?(current),
            canceled_at: optional_timestamp(current["canceled_at"])
          )
        end

        def stopping?(subscription)
          subscription["status"] == "canceled" || scheduled_cancellation?(subscription)
        end

        def price_tier(price)
          unless price.is_a?(Hash) && price.dig("recurring", "interval") == "year" &&
                 price.dig("recurring", "interval_count") == 1
            raise Unsupported, "not an annual recurring price"
          end
          tier = Allure::Funding::Config.stripe_tier_for_price(identifier(price["id"]))
          raise Unsupported, "price is not configured for exactly one tier" unless tier

          tier
        end

        def fetch_object(collection, id)
          object = client.get("#{collection}/#{identifier(id)}")
          raise Unsupported, "provider read-back identity mismatch" unless object["id"] == id

          object
        end

        def related_id(value)
          value = value["id"] if value.is_a?(Hash)
          return nil if value.nil?

          identifier(value)
        end

        def identifier(value)
          value = value.to_s
          raise Unsupported, "invalid Stripe identifier" unless value.match?(/\A[A-Za-z0-9_]{1,255}\z/)

          value
        end

        def integer(value, positive: false)
          unless value.is_a?(Integer) && value >= 0 && (!positive || value.positive?)
            raise Unsupported, "invalid Stripe integer"
          end
          value
        end

        def timestamp(value)
          integer(value)
          Time.at(value).utc
        end

        def optional_timestamp(value) = value.nil? ? nil : timestamp(value)

        def currency(value)
          value = value.to_s.upcase
          raise Unsupported, "invalid currency" unless value.match?(/\A[A-Z]{3}\z/)

          value
        end

        def notification(event: nil, binding: nil, state: nil, reversal: nil)
          Allure::Funding::Notification.new(event:, binding:, state:, reversal:)
        end

        def ignore_unsupported
          yield
        rescue Unsupported
          nil
        end

        def validate_local_subscription!(subscription)
          unless subscription.is_a?(FundingSubscription) && subscription.provider == slug && subscription.user_id.present?
            raise ArgumentError, "a matched Stripe subscription is required"
          end
          identifier(subscription.customer_id)
        end

        def validate_return_url!(return_url)
          uri = URI.parse(return_url.to_s)
          return if %w[http https].include?(uri.scheme) && uri.host.present? && uri.userinfo.nil?

          raise ArgumentError, "invalid Stripe portal return URL"
        rescue URI::InvalidURIError
          raise ArgumentError, "invalid Stripe portal return URL"
        end
      end
    end
  end
end
