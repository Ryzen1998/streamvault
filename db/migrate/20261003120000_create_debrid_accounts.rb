# frozen_string_literal: true

class CreateDebridAccounts < ActiveRecord::Migration[8.1]
  def change
    create_table :debrid_accounts do |t|
      t.string :service, null: false
      t.text :api_key, null: false
      t.datetime :verified_at
      t.text :last_error
      t.timestamps
    end
  end
end
