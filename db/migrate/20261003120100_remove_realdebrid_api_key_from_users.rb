# frozen_string_literal: true

# Debrid keys are instance-wide now (see DebridAccount); users no longer hold one.
class RemoveRealdebridApiKeyFromUsers < ActiveRecord::Migration[8.1]
  def change
    remove_column :users, :realdebrid_api_key, :text
  end
end
