require 'rails_helper'

RSpec.describe User, type: :model do
  describe "associations" do
    it { is_expected.to have_many(:collection_entries).dependent(:destroy) }
    it { is_expected.to have_many(:playback_progresses).dependent(:destroy) }
    it { is_expected.to have_many(:hls_sessions).dependent(:destroy) }
  end

  describe "language defaults" do
    it "defaults preferred_languages to English on create" do
      user = create(:user)
      expect(user.preferred_languages).to eq([ "ENG" ])
      expect(user.default_language).to eq("ENG")
    end
  end

  it "has no per-user debrid key" do
    expect(User.column_names).not_to include("realdebrid_api_key")
  end
end
