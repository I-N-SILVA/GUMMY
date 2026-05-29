# Pix integration (Stripe)

Pix is Brazil's instant payment system. This document tracks the implementation of Pix
as a payment method on top of the existing Stripe processor.

## Why Pix lives inside the Stripe processor (not a new top-level processor)

`ChargeProcessor` dispatches every operation by `merchant_account.charge_processor_id`
(see `app/business/payments/charging/charge_processor.rb`, e.g. `create_payment_intent_or_charge!`
at line 134). A Stripe-backed Pix charge settles into the seller's **Stripe** merchant
account, so its `charge_processor_id` is still `"stripe"`. Adding a separate `"pix"` entry to
`CHARGE_PROCESSOR_CLASS_MAP` would require a merchant account with that id, which does not exist.
Pix is therefore a new **payment method type** within `StripeChargeProcessor`, mirroring how
the codebase already models cards.

## Async model

Unlike a card authorization, Pix is asynchronous:

1. We create a PaymentIntent with `payment_method_types: ["pix"]`.
2. Stripe returns the intent in `requires_action` with `next_action.type == "pix_display_qr_code"`.
3. We show the buyer the QR code / copy-and-paste ("copia e cola") string.
4. The buyer pays in their bank app. The intent moves to `processing`, then `succeeded`.
5. Stripe notifies us via webhook; the purchase is confirmed at that point.

## Done

- `StripeIntentStatus::ACTION_TYPE_PIX_DISPLAY_QR_CODE` constant.
- `StripeChargeIntent` recognizes the Pix QR `next_action` (previously it would call
  `ErrorNotifier.notify` for any non-`use_stripe_sdk` action), and exposes
  `displays_pix_qr_code?`, `pix_qr_code`, `pix_qr_code_image_url`, and `pix_expires_at`.
  `requires_action?` deliberately still means "needs SCA via stripe.js", so existing card
  SCA handling is unchanged.
- Specs in `spec/business/payments/charging/implementations/stripe/stripe_charge_intent_spec.rb`.

## Remaining work

### 1. BRL currency path
`StripeChargeProcessor#create_payment_intent_or_charge!`
(`app/business/payments/charging/implementations/stripe/stripe_charge_processor.rb:219`)
hardcodes `currency: "usd"`. Stripe Pix only settles in `brl`. The Pix path must send
`currency: "brl"` with the amount in BRL cents. This is the largest piece, because the
surrounding purchase/charge pipeline assumes USD settlement — audit `Purchase` amount fields
and `app/services/order/create_service.rb` for the conversion points before changing this.

### 2. Pix chargeable
Add `StripeChargeablePix` alongside `StripeChargeablePaymentMethod`. It supplies
`stripe_charge_params` for a Pix intent (`payment_method_types: ["pix"]`, no saved customer,
not reusable — Pix cannot be stored for off-session reuse, so `can_be_saved?` is false and
`off_session` must be false). Wire it into `StripeChargeProcessor#get_chargeable_for_params`
(line 34) so a `pix` param from checkout produces this chargeable.

### 3. Purchase "in progress / awaiting payment" state
Because confirmation is async, the purchase must hold in a pending state after the intent is
created and only succeed when the webhook arrives. Reuse the SCA "in progress" machinery that
`FailAbandonedPurchaseWorker` already exercises, and confirm a Pix-specific expiry aligned with
`pix_expires_at`.

### 4. Webhook routing
`StripeChargeProcessor.handle_stripe_event` (line 674) already turns Stripe charge events into
`ChargeEvent`s that flow to `Purchase::ChargeEventsHandler`. Verify that the
`payment_intent.processing` -> `payment_intent.succeeded` (or `charge.succeeded`) sequence for
Pix produces a `TYPE_CHARGE_SUCCEEDED` event and marks the purchase paid. Add handling for the
expiry/cancellation case.

### 5. Frontend (checkout)
`app/javascript/components/Checkout/` needs a Pix option that, after intent creation, renders the
QR image + copy-and-paste code (from `pix_qr_code`/`pix_qr_code_image_url`) and polls or
subscribes until the purchase is confirmed, with a countdown to `pix_expires_at`. Use the
`checkout.payWithPix` / `checkout.awaitingPayment` / `checkout.paymentConfirmed` i18n keys added
in the localization phase.

### 6. Tests
Add VCR-backed specs (scoped per file) for chargeable creation and the processing -> succeeded
webhook flow against Stripe test mode with Pix enabled.
