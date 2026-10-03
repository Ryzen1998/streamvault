# frozen_string_literal: true

class HomeController < ApplicationController
  before_action :authenticate_user!

  def index
    @recommendations = RecommendationService.for(current_user)
    @continue_watching = fetch_continue_watching
    @recently_added = current_user.collection_entries.library.where("created_at > ?", 2.weeks.ago).recently_added.limit(20)
    @wishlist_preview = current_user.collection_entries.wishlist.recently_added.limit(20)
    @rows = Catalog::Resolver.new.home_rows
  end

  private

  def fetch_continue_watching
    result = Playback::ContinueWatchingQuery.new(current_user).call
    result.success? ? result.data : []
  end
end
