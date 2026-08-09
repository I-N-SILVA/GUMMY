# Testing BRL settlement and Pix

None of this could be executed in the environment the code was written in: no MySQL, no Mongo, no
Redis, no Stripe credentials, and the pinned Ruby (3.4.3) could not be installed. What *was* verified
is stated at the bottom. Everything below is the work of actually proving it.

Do these in order. Each stage assumes the previous one passed.

---

## Stage 0 — Get a working environment

The specs need MySQL, Redis, Elasticsearch and Mongo. `README.md` has the full setup; the short path:

```bash
rbenv install 3.4.3 && bundle install
npm install
docker compose up -d          # mysql, redis, elasticsearch, mongo
bin/rails db:create db:schema:load
bin/rails db:test:prepare
```

Confirm the suite runs at all before trusting any result from it:

```bash
bundle exec rspec spec/models/purchase_settlement_spec.rb
```

If that errors on connection rather than on assertions, fix the environment first — a spec that
cannot connect looks a lot like a spec that passes when you run the whole file and skim the output.

## Stage 1 — Run the specs written alongside this work

These need a database but no Stripe credentials, so they should pass immediately:

```bash
bundle exec rspec \
  spec/business/payments/settlement_conversion_spec.rb \
  spec/business/payments/settlement_currency_policy_spec.rb \
  spec/business/payments/local_payment_method_spec.rb \
  spec/models/purchase_settlement_spec.rb \
  spec/models/merchant_account_spec.rb
```

These touch Stripe and will need cassettes recorded (Stage 2):

```bash
bundle exec rspec \
  spec/business/payments/charging/implementations/stripe/stripe_charge_intent_spec.rb \
  spec/business/payments/charging/implementations/stripe/stripe_chargeable_pix_spec.rb \
  spec/business/payments/charging/implementations/stripe/stripe_charge_processor_spec.rb
```

Then the regression surface — the async-state change touched shared money paths, so run all of it,
not just the Pix parts:

```bash
bundle exec rspec \
  spec/services/purchase/create_service_spec.rb \
  spec/services/order/charge_service_spec.rb \
  spec/models/subscription_spec.rb \
  spec/sidekiq/fail_abandoned_purchase_worker_spec.rb \
  spec/models/purchase_spec.rb
```

**The two things most likely to break here**, both from `pending_confirmation?` now including
`processing`:

1. A spec asserting that a `processing` intent leaves a purchase failed. It will now stay
   `in_progress`. That is the intended fix, so update the spec — but read it first and confirm it was
   asserting the old behavior rather than catching a real regression.
2. `FailAbandonedPurchaseWorker` scheduling assertions. The delay is now
   `purchase.time_to_complete_payment`, which still equals `TIME_TO_COMPLETE_SCA` for cards, so these
   should pass unchanged. If one fails, the intent in that spec is probably a double that does not
   respond to `time_to_complete`.

## Stage 2 — Record the Stripe cassettes

Per CONTRIBUTING.md, do not stub around missing cassettes. Record them against Stripe test mode.

Pix must be enabled on the Stripe test account first (Dashboard → Settings → Payment methods → Pix).
Pix requires a **Brazilian** Stripe account, so you need a test-mode Connect account with
`country: "BR"`. `create_verified_stripe_account(country: "BR")` in the spec helpers is the existing
route.

```bash
export STRIPE_SECRET_KEY=sk_test_...
bundle exec rspec spec/business/payments/charging/implementations/stripe/stripe_charge_processor_spec.rb
```

Cassettes are scoped per file. If you see a test reading another test's response, that scoping broke —
delete the cassette directory for the file and re-record rather than editing YAML by hand.

## Stage 3 — Prove the settlement change end to end

This is the part that moves money, so verify it against Stripe rather than against assertions.

```ruby
# rails console, test mode
seller = User.find_by(email: "...")
Feature.activate_user(:brl_settlement, seller)

account = seller.merchant_account(StripeChargeProcessor.charge_processor_id)
account.country                       # => "BR"
account.settlement_currency           # => "brl"
LocalPaymentMethod.available_for(account).map(&:id)   # => [:pix]
```

Then buy something from that seller with a card and check, **in the Stripe dashboard**:

- [ ] the PaymentIntent's currency is `brl`, not `usd`
- [ ] its amount is the USD price × the rate, not the USD cents reinterpreted as centavos (a $10
      product must charge ~R$54, not R$10 — this is the single most important check on this branch)
- [ ] `application_fee_amount` is in BRL and is Gumroad's cut, not the whole amount
- [ ] a `purchase_settlements` row exists with `currency: "brl"`, the converted amount, and the rate
- [ ] the same purchase in USD terms (`Purchase#price_cents`) is unchanged

Then turn the flag off and repeat with any US seller. The PaymentIntent must be byte-identical to
before this branch — `currency: "usd"`, no settlement row. That is the claim the whole design rests
on, so prove it rather than assume it.

### Refunds

- [ ] a **full** refund of the BRL charge succeeds and returns BRL
- [ ] a **partial** refund of the BRL charge raises `ChargeProcessorError` rather than refunding the
      wrong amount

The second one is deliberate, not a bug. Partial refunds have to use the rate the charge settled at,
which `refund!` cannot reach from a bare charge id. **This must be fixed before the flag is enabled
for any real seller** — a Brazilian seller who cannot issue a partial refund is a support problem.

## Stage 4 — Pix, once a buyer can reach it

Checkout only offers Pix when `local_payment_methods` includes it, which requires BRL settlement to
be on for that seller. With the flag off, the option is invisible and nothing below applies.

Stripe's test mode does not have a real banking app, so you drive the intent through its states with
the API directly:

```ruby
# after checkout returns requires_pix_payment
intent = Stripe::PaymentIntent.retrieve(purchase.processor_payment_intent_id,
                                        { stripe_account: account.charge_processor_merchant_id })
intent.status          # => "requires_action"
intent.next_action.type # => "pix_display_qr_code"
```

Check the purchase state at each step:

- [ ] right after checkout, the purchase is `in_progress` — **not** `successful`
- [ ] the seller's balance has **not** moved
- [ ] the buyer has **not** been granted access to the product
- [ ] a `FailAbandonedPurchaseWorker` job is scheduled at roughly `pix_expires_at`, not 15 minutes out

The third and fourth checks are the ones that matter most. Before the async-state fix,
`Purchase::CreateService` would have marked a Pix purchase successful and credited the seller before
the buyer paid anything; a regression there is silent and expensive.

Then drive it to success (Stripe test mode can confirm a Pix intent from the dashboard, or use a
webhook fixture) and confirm the `payment_intent.succeeded` webhook transitions the purchase to
`successful` and credits the seller exactly once.

Finally, let one expire and confirm the purchase ends `failed`, the seller is not credited, and
inventory is released.

## Stage 5 — Frontend

```bash
npx tsc --noEmit
DISABLE_TYPE_CHECKED=1 npx eslint
```

Manually, as a buyer against a BRL-settling seller:

- [ ] a Pix radio appears next to Card, and the Card row becomes a radio rather than a static header
- [ ] selecting Pix hides the card fields and shows the notice
- [ ] the Pay button submits with `pix: true` in the request payload (check the network tab)
- [ ] against a US seller, no Pix option appears at all

There is no JS test framework in this repo, so `tsc` and `eslint` are the only automated frontend
checks. Every behavioral claim above has to be checked by hand.

---

## What is genuinely still missing

Be clear that passing everything above does **not** mean Pix is shippable:

1. **No QR display after submit.** The backend returns `requires_pix_payment` with the code and image
   URL, and `PixPayment.tsx` can render it, but nothing connects the two. The buyer submits and sees
   nothing useful.
2. **No polling.** There is no endpoint to ask "has this purchase been paid yet?" — `confirm` is
   SCA-specific. Something like `GET /purchases/:id/status` returning the purchase state is needed so
   `PixPayment` can flip from `awaiting` to `confirmed`. Poll it, do not trust the client to hold the
   tab open.
3. **Webhook path unverified.** `handle_stripe_event` is believed to route
   `payment_intent.processing` → `payment_intent.succeeded` into a `TYPE_CHARGE_SUCCEEDED` event, but
   nobody has watched a Pix payment actually do it. Stage 4 is where that gets proven.
4. **Partial refunds raise** (Stage 3).
5. **Backtax transfers still assume USD** — see `docs/brazil/multi-currency-settlement.md`.

## What was actually verified when this was written

- `rubocop` clean at the versions pinned in `Gemfile.lock`, across every changed Ruby file.
- `ruby -c` clean on every changed Ruby file.
- `npx tsc --noEmit` exits 0, from a verified-clean baseline. This is meaningful for the payment
  method union: adding `"pix"` to `AnyPaymentMethodResult` made the compiler point at all four places
  that assumed a card shape, and each was handled rather than cast away.
- `npx eslint` clean on every changed TypeScript file.

No RSpec ran. No Stripe call was made. Treat the Ruby as reviewed, not tested.
