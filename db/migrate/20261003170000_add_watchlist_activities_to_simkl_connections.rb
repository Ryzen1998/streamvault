# frozen_string_literal: true

class AddWatchlistActivitiesToSimklConnections < ActiveRecord::Migration[8.1]
  def change
    # Simkl's last plan-to-watch activity per type at the previous import, so
    # later imports only ask for what changed (Simkl's sync rules).
    add_column :simkl_connections, :watchlist_activities, :json
  end
end
