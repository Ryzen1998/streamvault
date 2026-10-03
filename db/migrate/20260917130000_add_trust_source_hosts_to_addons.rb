# frozen_string_literal: true

class AddTrustSourceHostsToAddons < ActiveRecord::Migration[8.1]
  def change
    add_column :addons, :trust_source_hosts, :boolean, default: false, null: false
  end
end
