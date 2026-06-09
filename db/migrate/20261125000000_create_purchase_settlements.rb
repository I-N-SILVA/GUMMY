# frozen_string_literal: true

class CreatePurchaseSettlements < ActiveRecord::Migration[7.1]
  def change
    create_table :purchase_settlements do |t|
      t.bigint :purchase_id, null: false
      t.string :currency, null: false
      t.bigint :amount_cents, null: false
      t.bigint :fee_cents, null: false, default: 0
      t.decimal :conversion_rate, precision: 18, scale: 9
      t.timestamps

      t.index :purchase_id, unique: true
    end
  end
end
