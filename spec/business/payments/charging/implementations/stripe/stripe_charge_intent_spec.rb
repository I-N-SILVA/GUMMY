# frozen_string_literal: true

require "spec_helper"

describe StripeChargeIntent, :vcr do
  include StripeChargesHelper

  let(:processor_payment_intent) do
    create_stripe_payment_intent(StripePaymentMethodHelper.success.to_stripejs_payment_method_id,
                                 amount: 1_00,
                                 currency: "usd")
  end

  subject (:stripe_charge_intent) { described_class.new(payment_intent: processor_payment_intent) }

  describe "#id" do
    it "returns the ID of Stripe payment intent" do
      expect(stripe_charge_intent.id).to eq(processor_payment_intent.id)
    end
  end

  describe "#client_secret" do
    it "returns the client secret of Stripe payment intent" do
      expect(stripe_charge_intent.client_secret).to eq(processor_payment_intent.client_secret)
    end
  end

  context "when Stripe payment intent requires confirmation" do
    let(:stripe_payment_method_id) { StripePaymentMethodHelper.success.to_stripejs_payment_method_id }
    let(:processor_payment_intent) do
      params = {
        payment_method: stripe_payment_method_id,
        payment_method_types: ["card"],
        amount: 1_00,
        currency: "usd"
      }
      Stripe::PaymentIntent.create(params)
    end

    it "is not successful" do
      expect(stripe_charge_intent.succeeded?).to eq(false)
    end

    it "requires confirmation" do
      expect(stripe_charge_intent.payment_intent.status == StripeIntentStatus::REQUIRES_CONFIRMATION).to eq(true)
    end

    it "does not load the charge" do
      expect(ChargeProcessor).not_to receive(:get_charge)

      expect(stripe_charge_intent.charge).to be_blank
    end
  end

  context "when Stripe payment intent is successful" do
    let(:stripe_payment_method_id) { StripePaymentMethodHelper.success.to_stripejs_payment_method_id }
    let(:processor_payment_intent) do
      create_stripe_payment_intent(stripe_payment_method_id, amount: 1_00, currency: "usd")
    end

    before do
      processor_payment_intent.confirm
    end

    it "is successful" do
      expect(stripe_charge_intent.succeeded?).to eq(true)
    end

    it "does not require action" do
      expect(stripe_charge_intent.requires_action?).to eq(false)
    end

    it "loads the charge" do
      expect(stripe_charge_intent.charge.id).to eq(processor_payment_intent.latest_charge)
    end
  end

  context "when Stripe payment intent is not successful" do
    let(:processor_payment_intent) do
      create_stripe_payment_intent(nil,
                                   amount: 1_00,
                                   currency: "usd")
    end

    it "is not successful" do
      expect(stripe_charge_intent.succeeded?).to eq(false)
    end

    it "does not require action" do
      expect(stripe_charge_intent.requires_action?).to eq(false)
    end

    it "does not load the charge" do
      expect(ChargeProcessor).not_to receive(:get_charge)

      expect(stripe_charge_intent.charge).to be_blank
    end
  end

  context "when Stripe payment intent is canceled" do
    let(:processor_payment_intent) do
      payment_intent = create_stripe_payment_intent(StripePaymentMethodHelper.success.to_stripejs_payment_method_id,
                                                    amount: 1_00,
                                                    currency: "usd")
      ChargeProcessor.cancel_payment_intent!(MerchantAccount.gumroad(StripeChargeProcessor.charge_processor_id), payment_intent.id)
    end

    it "is canceled" do
      expect(stripe_charge_intent.canceled?).to eq(true)
    end

    it "is not successful" do
      expect(stripe_charge_intent.succeeded?).to eq(false)
    end

    it "does not require action" do
      expect(stripe_charge_intent.requires_action?).to eq(false)
    end

    it "does not load the charge" do
      expect(ChargeProcessor).not_to receive(:get_charge)

      expect(stripe_charge_intent.charge).to be_blank
    end
  end

  context "when Stripe payment intent requires action" do
    let(:stripe_payment_method_id) { StripePaymentMethodHelper.success_with_sca.to_stripejs_payment_method_id }
    let(:processor_payment_intent) do
      create_stripe_payment_intent(stripe_payment_method_id, amount: 1_00, currency: "usd")
    end

    before do
      processor_payment_intent.confirm
    end

    it "is not successful" do
      expect(stripe_charge_intent.succeeded?).to eq(false)
    end

    it "requires action" do
      expect(stripe_charge_intent.requires_action?).to eq(true)
    end

    it "does not load the charge" do
      expect(ChargeProcessor).not_to receive(:get_charge)

      expect(stripe_charge_intent.charge).to be_blank
    end

    context "when next action type is unsupported" do
      before do
        allow(processor_payment_intent.next_action).to receive(:type).and_return "redirect_to_url"
      end

      it "notifies error tracker" do
        expect(ErrorNotifier).to receive(:notify).with(/requires an unsupported action/)
        described_class.new(payment_intent: processor_payment_intent)
      end
    end
  end

  context "when Stripe payment intent displays a Pix QR code" do
    let(:pix_display_qr_code) do
      double(
        data: "00020126360014br.gov.bcb.pix0114+5511999999999",
        image_url_png: "https://example.com/pix-qr.png",
        expires_at: 1_700_000_000
      )
    end
    let(:next_action) { double(type: StripeIntentStatus::ACTION_TYPE_PIX_DISPLAY_QR_CODE, pix_display_qr_code:) }
    let(:processor_payment_intent) do
      double(
        id: "pi_pix_123",
        client_secret: "pi_pix_123_secret",
        status: StripeIntentStatus::REQUIRES_ACTION,
        next_action:
      )
    end

    it "does not notify the error tracker about an unsupported action" do
      expect(ErrorNotifier).not_to receive(:notify)
      described_class.new(payment_intent: processor_payment_intent)
    end

    it "is not successful and does not load a charge" do
      expect(ChargeProcessor).not_to receive(:get_charge)
      expect(stripe_charge_intent.succeeded?).to eq(false)
      expect(stripe_charge_intent.charge).to be_blank
    end

    it "does not require Strong Customer Authentication" do
      expect(stripe_charge_intent.requires_action?).to eq(false)
    end

    it "reports that it displays a Pix QR code" do
      expect(stripe_charge_intent.displays_pix_qr_code?).to eq(true)
    end

    it "exposes the Pix copy-and-paste code and QR image" do
      expect(stripe_charge_intent.pix_qr_code).to eq("00020126360014br.gov.bcb.pix0114+5511999999999")
      expect(stripe_charge_intent.pix_qr_code_image_url).to eq("https://example.com/pix-qr.png")
    end

    it "exposes the expiry as a time" do
      expect(stripe_charge_intent.pix_expires_at).to eq(Time.zone.at(1_700_000_000))
    end

    it "is pending confirmation, so the purchase is not failed while the buyer pays" do
      expect(stripe_charge_intent.pending_confirmation?).to eq(true)
    end

    it "gives the buyer until the code expires rather than the shorter SCA window" do
      travel_to(Time.zone.at(1_700_000_000) - 2.hours) do
        expect(stripe_charge_intent.time_to_complete).to eq(2.hours.to_i)
      end
    end

    it "never gives the buyer less than the SCA window, even once the code has expired" do
      travel_to(Time.zone.at(1_700_000_000) + 1.hour) do
        expect(stripe_charge_intent.time_to_complete).to eq(ChargeProcessor::TIME_TO_COMPLETE_SCA.to_i)
      end
    end
  end

  context "when the payment intent does not display a Pix QR code" do
    let(:processor_payment_intent) do
      create_stripe_payment_intent(StripePaymentMethodHelper.success.to_stripejs_payment_method_id,
                                   amount: 1_00,
                                   currency: "usd")
    end

    it "returns nil for the Pix accessors" do
      expect(stripe_charge_intent.displays_pix_qr_code?).to eq(false)
      expect(stripe_charge_intent.pix_qr_code).to be_nil
      expect(stripe_charge_intent.pix_qr_code_image_url).to be_nil
      expect(stripe_charge_intent.pix_expires_at).to be_nil
    end

    it "falls back to the SCA window" do
      expect(stripe_charge_intent.time_to_complete).to eq(ChargeProcessor::TIME_TO_COMPLETE_SCA)
    end
  end
end
