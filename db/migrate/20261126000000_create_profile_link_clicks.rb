# frozen_string_literal: true

class CreateProfileLinkClicks < ActiveRecord::Migration[7.1]
  def change
    create_table :profile_link_clicks do |t|
      t.bigint :seller_profile_section_id, null: false
      t.string :link_id, null: false
      t.date :clicked_on, null: false
      t.bigint :clicks_count, null: false, default: 0
      t.timestamps

      t.index [:seller_profile_section_id, :link_id, :clicked_on],
              unique: true, name: "index_profile_link_clicks_on_section_and_link_and_day"
      t.index [:seller_profile_section_id, :clicked_on]
    end
  end
end
