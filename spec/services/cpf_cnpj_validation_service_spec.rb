# frozen_string_literal: true

require "spec_helper"

describe CpfCnpjValidationService do
  describe "#process" do
    context "with a CPF" do
      it "returns true for a valid CPF" do
        expect(described_class.new("11144477735").process).to be(true)
      end

      it "ignores punctuation in a valid CPF" do
        expect(described_class.new("111.444.777-35").process).to be(true)
      end

      it "returns false when the check digits are wrong" do
        expect(described_class.new("11144477700").process).to be(false)
      end

      it "returns false for a repeated-digit CPF" do
        expect(described_class.new("00000000000").process).to be(false)
      end
    end

    context "with a CNPJ" do
      it "returns true for a valid CNPJ" do
        expect(described_class.new("11222333000181").process).to be(true)
      end

      it "ignores punctuation in a valid CNPJ" do
        expect(described_class.new("11.222.333/0001-81").process).to be(true)
      end

      it "returns false when the check digits are wrong" do
        expect(described_class.new("11222333000100").process).to be(false)
      end

      it "returns false for a repeated-digit CNPJ" do
        expect(described_class.new("11111111111111").process).to be(false)
      end
    end

    context "with invalid input" do
      it "returns false for the wrong number of digits" do
        expect(described_class.new("123").process).to be(false)
      end

      it "returns false for a blank value" do
        expect(described_class.new("").process).to be(false)
      end

      it "returns false for nil" do
        expect(described_class.new(nil).process).to be(false)
      end
    end
  end
end
