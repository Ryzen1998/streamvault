require "rails_helper"

RSpec.describe "Catalog", type: :request do
  let(:user) { create(:user) }

  before { sign_in user }

  def json_headers
    { "Content-Type" => "application/json" }
  end

  def stub_cinemeta(metas, skip: nil)
    base = "https://v3-cinemeta.strem.io/catalog/movie/top"
    url = skip ? "#{base}/skip=#{skip}.json" : "#{base}.json"
    stub_request(:get, url)
      .to_return(status: 200, body: { "metas" => metas }.to_json, headers: json_headers)
  end

  it "renders the first page of a Cinemeta catalog" do
    stub_cinemeta([ { "id" => "tt1", "name" => "One" } ])

    get catalog_path(type: "movie", catalog_id: "top", provider: "cinemeta", title: "Top Movies")

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Top Movies")
    expect(response.body).to include("One")
  end

  it "paginates by offset and detects more pages" do
    stub_cinemeta([ { "id" => "tt1", "name" => "One" }, { "id" => "tt2", "name" => "Two" } ])
    stub_cinemeta([ { "id" => "tt3", "name" => "Three" } ], skip: 1)

    get catalog_path(type: "movie", catalog_id: "top", provider: "cinemeta", title: "Top", size: 1)

    expect(response.body).to include("One")
    expect(response.body).not_to include("Three")
    expect(response.body).to include("Next")

    get catalog_path(type: "movie", catalog_id: "top", provider: "cinemeta", title: "Top", size: 1, page: 2)

    expect(response.body).to include("Three")
    expect(response.body).to include("Previous")
  end

  it "pages an addon catalog" do
    addon = create(:addon, url: "https://addon.example.com/manifest.json")
    stub_request(:get, "https://addon.example.com/manifest.json")
      .to_return(
        status: 200,
        body: {
          "id" => "org.test", "name" => "Test", "types" => %w[movie],
          "catalogs" => [ { "type" => "movie", "id" => "top", "name" => "Top" } ]
        }.to_json,
        headers: json_headers
      )
    stub_request(:get, "https://addon.example.com/catalog/movie/top.json")
      .to_return(status: 200, body: { "metas" => [ { "id" => "tt1", "name" => "Addon One" } ] }.to_json, headers: json_headers)

    get catalog_path(type: "movie", catalog_id: "top", provider: "addon", reference: addon.id.to_s, title: "Top")

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Addon One")
  end

  it "shows an empty state when a page has no items" do
    stub_cinemeta([])

    get catalog_path(type: "movie", catalog_id: "top", provider: "cinemeta", title: "Top")

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("No items on this page")
  end

  it "requires authentication" do
    sign_out user

    get catalog_path(type: "movie", catalog_id: "top", provider: "cinemeta")

    expect(response).to redirect_to(new_user_session_path)
  end
end
