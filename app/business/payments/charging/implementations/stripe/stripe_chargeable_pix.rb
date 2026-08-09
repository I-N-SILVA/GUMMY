# frozen_string_literal: true

# Pix is Brazil's instant bank-transfer payment method, offered through Stripe.
#
# Unlike a card, there is no payment method to collect up front: Stripe creates the
# PaymentIntent with `payment_method_types: ["pix"]`, returns a QR code for the buyer
# to scan in their bank app, and confirms the charge asynchronously via webhook (see
# StripeChargeIntent#displays_pix_qr_code?). Pix cannot be stored for off-session reuse,
# so this chargeable exposes no reusable token and none of the card-specific visual
# details — every card field is intentionally nil, matching how PaypalChargeable models
# a non-card method.
class StripeChargeablePix
  attr_reader :zip_code, :payment_method_id, :fingerprint, :funding_type, :last4,
              :number_length, :visual, :expiry_month, :expiry_year, :card_type, :country

  def initialize(zip_code: nil)
    @zip_code = zip_code
  end

  def charge_processor_id
    StripeChargeProcessor.charge_processor_id
  end

  def prepare!
    true
  end

  # Pix is single-use; it can never be saved as a reusable payment method.
  def reusable_token!(_user)
    nil
  end

  def stripe_charge_params
    { payment_method_types: ["pix"] }
  end

  def requires_mandate?
    false
  end

  # The buyer has to scan the code in their banking app, so there is nothing to charge without them
  # present. A multi-seller cart charges off-session to avoid repeated SCA prompts, which would
  # otherwise ask Stripe to confirm a Pix intent with no buyer attached.
  def can_be_charged_off_session?
    false
  end
end
