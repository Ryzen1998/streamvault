# frozen_string_literal: true

class StatsController < ApplicationController
  before_action :authenticate_user!

  def show
    @stats = Playback::WatchStats.new(current_user).call
  end
end
