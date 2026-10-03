require "rails_helper"

RSpec.describe Addons::StreamParser do
  subject(:parser) { described_class.new }

  let(:aiostreams_stream) do
    {
      "name" => "AIOStreams 2160p",
      "description" => "📄 Movie 2024 2160p WEB-DL.mkv\n💾 12.5 GB",
      "behaviorHints" => {
        "filename" => "Movie 2024 2160p WEB-DL.mkv",
        "videoSize" => 13_421_772_800,
        "bingeGroup" => "aiostreams|realdebrid|73cc9adbfdcd986f31b013eed1df3ae9786e318d"
      },
      "url" => "https://aiostreams.example.com/api/v1/proxy/e.x.y/file.mkv"
    }
  end

  let(:torrentio_stream) do
    {
      "name" => "Torrentio 4K",
      "title" => "Movie 2024 2160p BluRay",
      "infoHash" => "deadbeef",
      "seeders" => 42,
      "url" => "https://torrentio.strem.fun/resolve/realdebrid=key/file"
    }
  end

  it "parses addon-proxied streams using behaviorHints" do
    candidate = parser.parse([ aiostreams_stream ], provider: "T").first

    expect(candidate.filename).to eq("Movie 2024 2160p WEB-DL.mkv")
    expect(candidate.raw_size).to eq(13_421_772_800)
    expect(candidate.size).to eq("12.5 GB")
    expect(candidate.quality).to eq("4K")
    expect(candidate.info_hash).to eq("73cc9adbfdcd986f31b013eed1df3ae9786e318d")
    expect(candidate.resolve_url).to eq("https://aiostreams.example.com/api/v1/proxy/e.x.y/file.mkv")
    expect(candidate.provider).to eq("T")
  end

  it "does not treat descriptive bingeGroup segments as an info hash" do
    stream = aiostreams_stream.merge(
      "behaviorHints" => { "bingeGroup" => "com.aiostreams.viren070|2160p|BluRay REMUX|FraMeSToR" }
    )

    expect(parser.parse([ stream ], provider: "T").first.info_hash).to be_nil
  end

  it "prefers a top-level infoHash when present" do
    stream = aiostreams_stream.merge("infoHash" => "deadbeef")

    expect(parser.parse([ stream ], provider: "T").first.info_hash).to eq("deadbeef")
  end

  it "parses Torrentio-style streams" do
    candidate = parser.parse([ torrentio_stream ], provider: "T").first

    expect(candidate.info_hash).to eq("deadbeef")
    expect(candidate.seeders).to eq(42)
    expect(candidate.quality).to eq("4K")
  end

  it "skips streams without a url" do
    expect(parser.parse([ torrentio_stream.merge("url" => nil) ], provider: "T")).to eq([])
  end

  it "ignores non-hash entries" do
    expect(parser.parse([ nil, "nope", 42 ], provider: "T")).to eq([])
  end

  it "flags cached streams" do
    stream = aiostreams_stream.merge("name" => "AIOStreams ⚡ 2160p")
    expect(parser.parse([ stream ], provider: "T").first.cached).to be(true)
  end

  it "flags uncached streams as not cached" do
    expect(parser.parse([ aiostreams_stream ], provider: "T").first.cached).to be(false)
  end

  it "extracts sanitized proxyHeaders request headers" do
    stream = aiostreams_stream.merge(
      "behaviorHints" => aiostreams_stream["behaviorHints"].merge(
        "proxyHeaders" => { "request" => { "user-agent" => "Stremio", "Host" => "evil" } }
      )
    )

    expect(parser.parse([ stream ], provider: "T").first.request_headers)
      .to eq("User-Agent" => "Stremio")
  end

  it "defaults request headers to an empty hash" do
    expect(parser.parse([ aiostreams_stream ], provider: "T").first.request_headers).to eq({})
  end
end
