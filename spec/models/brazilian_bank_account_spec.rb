# frozen_string_literal: true

require "spec_helper"

describe BrazilianBankAccount do
  describe "#bank_account_type" do
    it "returns BR" do
      expect(create(:brazilian_bank_account).bank_account_type).to eq("BR")
    end
  end

  describe "#country" do
    it "returns BR" do
      expect(create(:brazilian_bank_account).country).to eq("BR")
    end
  end

  describe "#currency" do
    it "returns brl" do
      expect(create(:brazilian_bank_account).currency).to eq("brl")
    end
  end

  describe "#routing_number" do
    it "combines the bank code and branch code" do
      ba = create(:brazilian_bank_account, bank_code: "341", branch_code: "0001")
      expect(ba).to be_valid
      expect(ba.routing_number).to eq("341-0001")
    end
  end

  describe "#account_number_visual" do
    it "returns the visual account number" do
      expect(create(:brazilian_bank_account, account_number_last_four: "6789").account_number_visual).to eq("******6789")
    end
  end

  describe "#validate_bank_code" do
    it "allows 3 digits only" do
      expect(build(:brazilian_bank_account, bank_code: "001")).to be_valid
      expect(build(:brazilian_bank_account, bank_code: "341")).to be_valid
      expect(build(:brazilian_bank_account, bank_code: "ABC")).not_to be_valid
      expect(build(:brazilian_bank_account, bank_code: "0011")).not_to be_valid
      expect(build(:brazilian_bank_account, bank_code: "01")).not_to be_valid
    end
  end

  describe "#validate_branch_code" do
    it "allows four or five digits" do
      expect(build(:brazilian_bank_account, branch_code: "0001")).to be_valid
      expect(build(:brazilian_bank_account, branch_code: "12345")).to be_valid
      expect(build(:brazilian_bank_account, branch_code: "001")).not_to be_valid
      expect(build(:brazilian_bank_account, branch_code: "ABCD")).not_to be_valid
    end
  end

  describe "#validate_account_number" do
    it "allows four to thirteen digits" do
      expect(build(:brazilian_bank_account, account_number: "1234")).to be_valid
      expect(build(:brazilian_bank_account, account_number: "000123456789")).to be_valid
      expect(build(:brazilian_bank_account, account_number: "123")).not_to be_valid
      expect(build(:brazilian_bank_account, account_number: "12345678901234")).not_to be_valid
    end
  end

  describe "account types" do
    it "allows checking account types" do
      bank_account = build(:brazilian_bank_account, account_type: BrazilianBankAccount::AccountType::CHECKING)
      expect(bank_account).to be_valid
      expect(bank_account.account_type).to eq(BrazilianBankAccount::AccountType::CHECKING)
    end

    it "allows savings account types" do
      bank_account = build(:brazilian_bank_account, account_type: BrazilianBankAccount::AccountType::SAVINGS)
      expect(bank_account).to be_valid
      expect(bank_account.account_type).to eq(BrazilianBankAccount::AccountType::SAVINGS)
    end

    it "invalidates other account types" do
      bank_account = build(:brazilian_bank_account, account_type: "evil_account_type")
      expect(bank_account).not_to be_valid
    end

    it "translates a nil account type to the default (checking)" do
      bank_account = build(:brazilian_bank_account, account_type: nil)
      expect(bank_account).to be_valid
      expect(bank_account.account_type).to eq(BrazilianBankAccount::AccountType::CHECKING)
    end
  end
end
