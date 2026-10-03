# frozen_string_literal: true

class CreateAddons < ActiveRecord::Migration[8.1]
  def change
    create_table :addons do |t|
      t.string :url, null: false
      t.string :name
      t.string :manifest_id
      t.json :manifest_types
      t.boolean :enabled, default: true, null: false
      t.integer :position, default: 0, null: false
      t.datetime :last_checked_at
      t.text :last_error
      t.timestamps
    end

    add_index :addons, :url, unique: true
    add_index :addons, :enabled
  end
end
