# frozen_string_literal: true

require "spec_helper"

describe StripeChargeablePix do
  let(:chargeable) { described_class.new(zip_code: "22041-080") }

  it "identifies as the stripe charge processor" do
    expect(chargeable.charge_processor_id).to eq("stripe")
  end

  it "requests a pix payment intent through stripe_charge_params" do
    expect(chargeable.stripe_charge_params).to eq(payment_method_types: ["pix"])
  end

  it "is ready without loading any remote payment method" do
    expect(chargeable.prepare!).to be(true)
  end

  it "cannot be saved for off-session reuse" do
    expect(chargeable.reusable_token!(nil)).to be_nil
  end

  it "does not require an Indian e-mandate" do
    expect(chargeable.requires_mandate?).to be(false)
  end

  it "exposes the buyer zip code and no card details" do
    expect(chargeable.zip_code).to eq("22041-080")
    expect(chargeable.last4).to be_nil
    expect(chargeable.card_type).to be_nil
    expect(chargeable.country).to be_nil
    expect(chargeable.payment_method_id).to be_nil
  end
end
