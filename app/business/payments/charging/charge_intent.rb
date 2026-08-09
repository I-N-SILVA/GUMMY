# frozen_string_literal: true

# Represents the user's intent to pay. The intent may succeed immediately (resulting in a charge)
# or require additional confirmation from the user (such as 3D Secure).
#
# This is mainly a wrapper around Stripe's PaymentIntent API: https://stripe.com/docs/payments/payment-intents
#
# For other charge-based APIs (PayPal, Braintree) that don't have this notion of "intent" - and result in an
# immediate charge - we wrap the `charge` object in a `ChargeIntent` and set `succeeded` to `true` immediately.
class ChargeIntent
  # `settlement` is the SettlementConversion the charge was created with, present only on intents we
  # just created (it is unknowable when rebuilding an intent from a webhook or a later retrieve).
  attr_accessor :id, :payment_intent, :charge, :client_secret, :settlement

  def requires_action?
    false
  end

  # True when the charge exists but its outcome will only be known later: the buyer still has to act
  # outside checkout — an SCA challenge, or paying a code in their banking app — or the processor is
  # still settling. Such a purchase has to stay in_progress and be completed by the webhook, never by
  # checkout, which would otherwise credit the seller and deliver the product for money that has not
  # arrived yet.
  def pending_confirmation?
    false
  end

  # How long the buyer has to complete a pending charge before it is abandoned and cancelled.
  def time_to_complete
    ChargeProcessor::TIME_TO_COMPLETE_SCA
  end

  def succeeded?
    true
  end

  def canceled?
    false
  end
end
