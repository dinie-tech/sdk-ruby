# frozen_string_literal: true

# A list item only needs to respond to `#id` (the cursor source — architecture §11).
Item = Struct.new(:id)

RSpec.describe Dinie::Page do
  # A fake transport keyed by cursor (idempotent — re-fetching a cursor returns the same page, like
  # a real server). Records every cursor it is asked for so specs can assert the auto-pager follows
  # `starting_after = last item id`. `nil` cursor ⇒ the first page.
  def fetcher(mapping, cursors: [])
    lambda do |cursor|
      cursors << cursor
      mapping.fetch(cursor) { raise "unexpected cursor #{cursor.inspect}" }
    end
  end

  let(:page_one) { { data: [Item.new("a"), Item.new("b")], has_more: true } }
  let(:page_two) { { data: [Item.new("c"), Item.new("d")], has_more: false } }
  let(:two_pages) { { nil => page_one, "b" => page_two } }

  describe "construction (eager first page)" do
    it "exposes the first page's data and has_more, and is frozen" do
      page = described_class.from_fetch(fetcher({ nil => page_one }))
      expect(page.data.map(&:id)).to eq(%w[a b])
      expect(page.has_more).to be(true)
      expect(page).to be_frozen
    end

    it "coerces a missing has_more to false" do
      page = described_class.from_fetch(->(_cursor) { { data: [Item.new("a")] } })
      expect(page.has_more).to be(false)
      expect(page.next_page?).to be(false)
    end
  end

  describe "#each / #auto_paging_each (auto-pagination)" do
    it "yields every item of every page, following the cursor (starting_after = last item id)" do
      cursors = []
      page = described_class.from_fetch(fetcher(two_pages, cursors: cursors))
      expect(page.each.map(&:id)).to eq(%w[a b c d])
      expect(cursors).to eq([nil, "b"])
    end

    it "stops by has_more, NOT by page size — a full page with has_more: false is terminal" do
      cursors = []
      full = { data: [Item.new("a"), Item.new("b")], has_more: false }
      page = described_class.from_fetch(fetcher({ nil => full }, cursors: cursors))
      expect(page.auto_paging_each.map(&:id)).to eq(%w[a b])
      expect(cursors).to eq([nil]) # never fetched a second page
    end

    it "treats an empty page as terminal (no infinite loop on { data: [], has_more: true })" do
      page = described_class.from_fetch(->(_cursor) { { data: [], has_more: true } })
      expect(page.next_page?).to be(false)
      expect(page.each.to_a).to eq([])
    end

    it "returns an Enumerator without a block, enabling lazy first/map across pages" do
      page = described_class.from_fetch(fetcher(two_pages))
      expect(page.each).to be_a(Enumerator)
      expect(page.each.first(3).map(&:id)).to eq(%w[a b c])
      expect(page.each.lazy.map(&:id).first(3)).to eq(%w[a b c])
    end
  end

  describe "#each_page (manual page-by-page)" do
    it "yields each Page in order, following the cursor" do
      cursors = []
      page = described_class.from_fetch(fetcher(two_pages, cursors: cursors))
      pages = []
      page.each_page { |current| pages << current.data.map(&:id) }
      expect(pages).to eq([%w[a b], %w[c d]])
      expect(cursors).to eq([nil, "b"])
    end

    it "returns an Enumerator of pages without a block" do
      page = described_class.from_fetch(fetcher(two_pages))
      expect(page.each_page).to be_a(Enumerator)
      expect(page.each_page.map { |current| current.data.map(&:id) }).to eq([%w[a b], %w[c d]])
    end
  end

  describe "#next_page? / #next_page" do
    it "navigates one page at a time using the last item's id as the cursor" do
      cursors = []
      page = described_class.from_fetch(fetcher(two_pages, cursors: cursors))
      expect(page.next_page?).to be(true)
      nxt = page.next_page
      expect(nxt.data.map(&:id)).to eq(%w[c d])
      expect(nxt.next_page?).to be(false)
      expect(cursors).to eq([nil, "b"])
    end

    it "raises past the last page" do
      page = described_class.from_fetch(fetcher({ nil => { data: [Item.new("a")], has_more: false } }))
      expect { page.next_page }.to raise_error(Dinie::Error, /no next page/i)
    end
  end

  describe "#first(n) — lazy take across pages" do
    it "takes n items across pages, fetching only as many pages as needed" do
      cursors = []
      page = described_class.from_fetch(fetcher(two_pages, cursors: cursors))
      expect(page.first(3).map(&:id)).to eq(%w[a b c])
      expect(cursors).to eq([nil, "b"])
    end

    it "returns a single item when called with no argument (no extra fetch)" do
      cursors = []
      page = described_class.from_fetch(fetcher({ nil => page_one }, cursors: cursors))
      expect(page.first.id).to eq("a")
      expect(cursors).to eq([nil])
    end
  end

  describe ".paginated? (the /banks discriminator — architecture §7.5/§11)" do
    it "is true when the envelope carries has_more (a cursor list)" do
      expect(described_class.paginated?({ data: [], has_more: false })).to be(true)
      expect(described_class.paginated?({ data: [], has_more: true })).to be(true)
    end

    it "is false for a flat envelope like /banks (no has_more)" do
      expect(described_class.paginated?([{ id: "bank_1" }])).to be(false)
      expect(described_class.paginated?({ data: [{ id: "bank_1" }] })).to be(false)
    end
  end
end
