# frozen_string_literal: true

# Paginated browse page for a single catalog row (addon or Cinemeta).
class CatalogController < ApplicationController
  include ContentParamValidation
  before_action :authenticate_user!

  DEFAULT_PAGE_SIZE = Catalog::Resolver::DEFAULT_PAGE_SIZE
  MAX_PAGE_SIZE = Catalog::Resolver::MAX_PAGE_SIZE

  def index
    @type = params[:type]
    @catalog_id = params[:catalog_id]
    return if reject_invalid_content_type!(@type)

    @page = [ params.fetch(:page, 1).to_i, 1 ].max
    @size = params.fetch(:size, DEFAULT_PAGE_SIZE).to_i.clamp(1, MAX_PAGE_SIZE)
    @title = params[:title].presence || "Catalog"

    result = Catalog::Resolver.new.catalog_page(
      provider: params[:provider],
      reference: params[:reference],
      type: @type,
      catalog_id: @catalog_id,
      genre: params[:genre].presence,
      page: @page,
      size: @size,
      title: params[:title].presence
    )

    if result.success?
      @items = result.data[:items]
      @has_more = result.data[:has_more]
      @next_size = result.data[:next_size]
    else
      @items = []
      @has_more = false
      @next_size = @size
      @error = result.error_message
    end
  end
end
