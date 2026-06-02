# frozen_string_literal: true

RSpec.describe Dinie do
  describe "VERSION" do
    it "is a semantic version string" do
      expect(Dinie::VERSION).to be_a(String)
      expect(Dinie::VERSION).to match(/\A\d+\.\d+\.\d+/)
    end
  end
end
