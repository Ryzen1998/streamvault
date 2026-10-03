require "rails_helper"

RSpec.describe Streams::StremioAddonProvider do
  subject(:provider) { described_class.new(addon: entry) }

  let(:entry) do
    Addons::Registry::Entry.new(url: "https://addon.example.com/manifest.json", name: "Test Addon")
  end

  def stub_streams(body)
    stub_request(:get, "https://addon.example.com/stream/movie/tt1375666.json")
      .to_return(status: 200, body: body.to_json, headers: { "Content-Type" => "application/json" })
  end

  it "returns ranked candidates with a distinct provider label" do
    stub_streams(
      "streams" => [
        {
          "name" => "Addon 1080p",
          "behaviorHints" => { "filename" => "Movie 2024 1080p WEB-DL.mkv" },
          "url" => "https://addon.example.com/api/v1/proxy/file"
        }
      ]
    )

    result = provider.streams("tt1375666", "movie", default_language: "ENG", preferred_languages: [ "ENG" ])

    expect(result).to be_success
    expect(result.data.length).to eq(1)
    expect(result.data.first.provider).to eq("Streams::StremioAddonProvider[Test Addon]")
  end

  it "returns failure when the addon errors" do
    stub_request(:get, "https://addon.example.com/stream/movie/tt1375666.json").to_return(status: 500)

    expect(provider.streams("tt1375666", "movie")).to be_failure
  end

  it "fails without an imdb id" do
    expect(provider.streams("", "movie")).to be_failure
  end

  it "exposes its base URL for origin validation" do
    expect(provider.resolve_base_urls).to eq([ "https://addon.example.com" ])
  end
end
