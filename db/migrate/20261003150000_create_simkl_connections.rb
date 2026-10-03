# frozen_string_literal: true

class CreateSimklConnections < ActiveRecord::Migration[8.1]
  def change
    create_table :simkl_connections do |t|
      t.references :user, null: false, foreign_key: true, index: { unique: true }
      t.text :access_token, null: false
      t.string :username
      t.datetime :last_synced_at
      t.text :last_error
      t.timestamps
    end

    add_column :playback_progresses, :simkl_synced_at, :datetime
  end
end
