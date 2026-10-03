require "rails_helper"

RSpec.describe Streams::TorrentioProvider do
  it "allows slow fallback listings enough time to complete" do
    provider = described_class.new
    connection = provider.instance_variable_get(:@connection)

    expect(connection.options.timeout).to eq(30)
    expect(connection.options.open_timeout).to eq(5)
  end

  describe "#streams" do
    let(:torbox) { Debrid::Account.new(service: "torbox", api_key: "tb_key") }
    let(:torbox_listing) { "https://torrentio.strem.fun/torbox=tb_key%7Cdebridoptions=nodownloadlinks/stream/movie/tt1375666.json" }
    let(:body) do
      {
        "streams" => [
          {
            "name" => "[TB download] Torrentio\n720p",
            "title" => "Inception.2010.720p.x264\n👤 5 💾 1.0 GB",
            "url" => "https://torrentio.strem.fun/resolve/torbox/tb_key/def/Inception720.mkv/0/Inception720.mkv",
            "behaviorHints" => { "filename" => "Inception720.mkv" }
          },
          {
            "name" => "[TB+] Torrentio\n1080p",
            "title" => "Inception.2010.1080p.x264\n👤 50 💾 2.1 GB",
            "url" => "https://torrentio.strem.fun/resolve/torbox/tb_key/abc/Inception.mkv/0/Inception.mkv",
            "behaviorHints" => { "filename" => "Inception.mkv" }
          }
        ]
      }
    end

    it "lists TorBox streams through the instance account, cached-only" do
      listing = stub_request(:get, torbox_listing)
        .to_return(status: 200, body: body.to_json, headers: { "Content-Type" => "application/json" })

      result = described_class.new(debrid: torbox).streams("tt1375666", "movie")

      expect(listing).to have_been_requested
      expect(result.data.map { |stream| [ stream.filename, stream.cached ] })
        .to eq([ [ "Inception.mkv", true ], [ "Inception720.mkv", false ] ])
    end

    it "keeps RealDebrid download links listed" do
      realdebrid = Debrid::Account.new(service: "realdebrid", api_key: "rd_key")
      listing = stub_request(:get, "https://torrentio.strem.fun/realdebrid=rd_key/stream/movie/tt1375666.json")
        .to_return(status: 200, body: { "streams" => [] }.to_json, headers: { "Content-Type" => "application/json" })

      described_class.new(debrid: realdebrid).streams("tt1375666", "movie")

      expect(listing).to have_been_requested
    end

    it "redacts the API key from error logs" do
      stub_request(:get, torbox_listing).to_return(status: 500)
      logger = double("logger", error: nil)

      described_class.new(debrid: torbox, logger: logger).streams("tt1375666", "movie")

      expect(logger).to have_received(:error).with(satisfy { |message| message.include?("[REDACTED]") && !message.include?("tb_key") })
    end
  end
end
