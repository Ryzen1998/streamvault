require "rails_helper"

RSpec.describe StreamSelection do
  let(:user) { create(:user) }
  let(:candidate) do
    StreamCandidate.new(
      title: "Inception 1080p",
      resolve_url: "https://torrentio.strem.fun/resolve/torbox/tb_key/abc/Inception.mkv/0/Inception.mkv",
      filename: "Inception.mkv",
      raw_size: 2_000_000_000,
      video_codec: "h264",
      compatibility_score: 1,
      request_headers: { "User-Agent" => "Stremio" }
    )
  end

  it "round-trips the fields playback needs" do
    token = described_class.issue(user: user, candidate: candidate)

    restored = described_class.resolve(token: token, user: user)

    expect(restored).to have_attributes(
      resolve_url: candidate.resolve_url,
      filename: "Inception.mkv",
      raw_size: 2_000_000_000,
      video_codec: "h264",
      compatibility_score: 1,
      request_headers: { "User-Agent" => "Stremio" }
    )
  end

  it "keeps the resolve URL (and its debrid key) unreadable" do
    token = described_class.issue(user: user, candidate: candidate)

    expect(token).not_to include("tb_key")
    expect(Base64.decode64(token.split("--").first)).not_to include("tb_key")
  end

  it "rejects another user's token" do
    token = described_class.issue(user: create(:user), candidate: candidate)

    expect { described_class.resolve(token: token, user: user) }.to raise_error(described_class::Invalid)
  end

  it "rejects tampered tokens" do
    expect { described_class.resolve(token: "tampered", user: user) }.to raise_error(described_class::Invalid)
  end
end
