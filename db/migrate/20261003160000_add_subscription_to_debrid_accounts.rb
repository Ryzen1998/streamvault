# frozen_string_literal: true

class AddSubscriptionToDebridAccounts < ActiveRecord::Migration[8.1]
  def change
    add_column :debrid_accounts, :plan, :string
    add_column :debrid_accounts, :expires_at, :datetime
  end
end
