require "rails_helper"

RSpec.describe Addon do
  it "appends /manifest.json when given a bare base URL" do
    addon = described_class.new(url: "https://aiostreams.example.com/stremio/u/p")
    addon.valid?

    expect(addon.url).to eq("https://aiostreams.example.com/stremio/u/p/manifest.json")
  end

  it "keeps a full manifest URL intact and exposes its base" do
    addon = described_class.new(url: "https://aiostreams.example.com/stremio/u/p/manifest.json")
    addon.valid?

    expect(addon.manifest_base_url).to eq("https://aiostreams.example.com/stremio/u/p")
  end

  it "rejects non-http URLs" do
    addon = described_class.new(url: "ftp://example.com/manifest.json")

    expect(addon).not_to be_valid
    expect(addon.errors[:url]).to be_present
  end

  it "requires a URL" do
    expect(described_class.new(url: "")).not_to be_valid
  end

  it "prefers name, then manifest id, then host for display" do
    addon = described_class.new(url: "https://example.com/manifest.json", manifest_id: "org.example")
    expect(addon.display_name).to eq("org.example")

    addon.name = "My Addon"
    expect(addon.display_name).to eq("My Addon")
  end

  it "exposes scopes for enabled, ordered addons" do
    first = create(:addon, position: 2)
    second = create(:addon, position: 1)
    create(:addon, enabled: false)

    expect(described_class.enabled.ordered).to eq([ second, first ])
  end
end
