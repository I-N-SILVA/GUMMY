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
- Buyer-facing `PixPayment` component (`app/javascript/components/Checkout/PixPayment.tsx`): renders
  the QR image, the copy-and-paste code, a live countdown to expiry, and awaiting/confirmed/expired
  states using the `checkout.pix*` i18n keys. It is presentational and does not yet receive live data
  or drive confirmation polling (see remaining items 1, 4, 5).
- `StripeChargeablePix` (`app/business/payments/charging/implementations/stripe/stripe_chargeable_pix.rb`):
  the chargeable for a Pix intent. It supplies `stripe_charge_params` of
  `{ payment_method_types: ["pix"] }`, returns `nil` from `reusable_token!` (Pix is single-use and
  cannot be saved off-session), and exposes nil card fields like `PaypalChargeable`. Wired into
  `StripeChargeProcessor#get_chargeable_for_params` behind a `params[:pix]` flag so a `pix` param
  from checkout produces this chargeable. Unit specs in
  `spec/business/payments/charging/implementations/stripe/stripe_chargeable_pix_spec.rb`.

## Remaining work

### 1. BRL currency path — done
`create_payment_intent_or_charge!` no longer hardcodes `currency: "usd"`. It sends
`merchant_account.settlement_currency` with the amount, application fee, and destination transfer all
converted at one rate by `SettlementConversion`, and records the result on the purchase via
`PurchaseSettlement`. A Brazilian Stripe Connect account with the `brl_settlement` flag on therefore
produces a `brl` intent, which is what Pix requires. See
`docs/brazil/multi-currency-settlement.md` (Phase 2) for the design and, importantly, for the two
items that must be closed before the flag can be enabled for a real seller — partial refunds of
non-USD charges currently raise rather than refund the wrong amount.

### 2. Pix chargeable — done
See the "Done" section above. `StripeChargeablePix` exists and is wired into
`StripeChargeProcessor#get_chargeable_for_params`. Still open from the original note:
`off_session` must be forced to false for Pix and `can_be_saved?` should treat Pix as
unsaveable — both belong with the purchase-state work in item 3, where the charge is actually
created and confirmed.

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
The presentational `PixPayment` component exists. What remains is integration: add a Pix option to
the payment selector in `PaymentForm.tsx`, pass the intent's `pix_qr_code` / `pix_qr_code_image_url` /
`pix_expires_at` from the backend (these must be serialized into the order/charge response), and poll
or subscribe until the purchase is confirmed so `status` flips from `awaiting` to `confirmed`.

### 6. Tests
Add VCR-backed specs (scoped per file) for chargeable creation and the processing -> succeeded
webhook flow against Stripe test mode with Pix enabled.
