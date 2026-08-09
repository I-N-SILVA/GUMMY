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
`StripeChargeablePix` exists and is reached through the `LocalPaymentMethod` catalog rather than a
hardcoded branch. `reusable_token!` already returned nil, and `can_be_charged_off_session?` now
returns false, so a multi-seller cart — which requests `off_session` to avoid repeated SCA prompts —
can no longer ask Stripe to confirm a Pix intent with no buyer attached.

### 3. Purchase "awaiting payment" state — done
A Pix intent sits in `requires_action` with a `pix_display_qr_code` next action. `requires_action?`
deliberately means "needs SCA via stripe.js" and so excludes it, and `processing?` is false too, which
meant every place that decides whether a purchase may complete treated a Pix purchase as neither
pending nor successful. Two consequences, both fixed:

- `Purchase::CompletionHandler#ensure_completion` and `Purchase#charge!` would have **failed** the
  purchase the moment checkout finished.
- `Purchase::CreateService` gates on `requires_sca?`, which is false for Pix, so it would have called
  `handle_purchase_success` → `update_balance_and_mark_successful!`, **crediting the seller and
  delivering the product before the buyer had paid anything**.

`ChargeIntent#pending_confirmation?` now names the state those call sites actually care about — the
charge exists but its outcome arrives later — and covers SCA, `processing`, and the Pix QR alike.
`Purchase#awaiting_payment_confirmation?` is the purchase-level equivalent used where `requires_sca?`
was standing in for it.

Abandonment respects the method's own deadline: `ChargeIntent#time_to_complete` defaults to
`TIME_TO_COMPLETE_SCA` (15 minutes) but returns the remaining time on `pix_expires_at` for a Pix
intent, floored at the SCA window. Scheduling `FailAbandonedPurchaseWorker` at 15 minutes would
otherwise cancel a Pix charge the buyer could still legitimately pay. The worker itself needed no
change: its early-run guard only prevents running *before* the SCA window, never forces a cancel at
it.

### 4. Webhook routing
`StripeChargeProcessor.handle_stripe_event` (line 674) already turns Stripe charge events into
`ChargeEvent`s that flow to `Purchase::ChargeEventsHandler`. Verify that the
`payment_intent.processing` -> `payment_intent.succeeded` (or `charge.succeeded`) sequence for
Pix produces a `TYPE_CHARGE_SUCCEEDED` event and marks the purchase paid. Add handling for the
expiry/cancellation case.

### 5. Frontend (checkout) — backend contract done, UI outstanding
`Order::ChargeService` now returns a Pix branch alongside the SCA ones, carrying no error but
signalling that checkout is unfinished:

```json
{ "success": true, "requires_pix_payment": true,
  "pix": { "qr_code": "...", "qr_code_image_url": "...", "expires_at": "..." },
  "order": { "id": "..." } }
```

`success: true` with a `requires_*` flag follows the convention the `requires_card_action` and
`requires_card_setup` branches already use. Without this branch a pending Pix purchase fell through
to `purchase.purchase_response` and read as a completed sale.

What remains is the UI: **checkout never sends `params[:pix]` today**, so Pix is unreachable by
buyers no matter what the backend supports. `PaymentForm.tsx` needs a Pix option, driven by
`LocalPaymentMethod.available_for(merchant_account)` rather than a hardcoded country test, and the
existing presentational `PixPayment` component needs wiring to the response above plus polling until
the purchase is confirmed, so `status` flips from `awaiting` to `confirmed`.

When a second asynchronous method is added, this response shape should generalize — the flag and the
payload are Pix-specific today because generalizing from one example would be guesswork.

### 6. Tests
Add VCR-backed specs (scoped per file) for chargeable creation and the processing -> succeeded
webhook flow against Stripe test mode with Pix enabled.
