# frozen_string_literal: true

module Dinie
  # `Page` — one page of a cursor-paginated list, and the auto-pagination engine over the pages
  # that follow it (architecture §11, RB8). Ports `sdk-js` `src/runtime/paginator.ts` and mirrors
  # the mechanics of OpenAI Ruby's `base_page.rb`. Part of the **public surface** (`Dinie::Page`).
  #
  # Dinie has exactly ONE cursor scheme (inherited contract): `starting_after` (the `id` of the
  # last item of the previous page) + `has_more` (the ONLY end-of-list signal — never
  # `data.length == limit`, since the server may return fewer items with `has_more: true`).
  #
  # A resource's `list*` does the first request **eagerly** and returns a `Page` carrying the
  # first page's `data`, its `has_more`, and a `fetch_page` closure that knows how to fetch the
  # next page (it maps a cursor to the `starting_after` query param and calls the transport).
  # The `Page` owns *when* to call the closure and *what* cursor to pass; the resource owns *how*
  # the closure reaches the network — so this class stays pure and is tested with an in-memory
  # fake (no `HttpClient` coupling).
  #
  # ── Why NOT `include Enumerable` (RB8) ──
  # `Enumerable` would graft on methods that materialize EVERY page eagerly (`to_a`, `count`,
  # `sort`, `min`…). A paginator must stay lazy, so we deliberately define only `#each` (+ its
  # `#auto_paging_each` alias) and `#each_page`; calling either without a block returns an
  # `Enumerator`, which gives `.map` / `.first` / `.lazy` on demand without eager-loading.
  #
  # ── Iteration modes ──
  #   * `#each` / `#auto_paging_each` — yield EVERY item of EVERY following page (auto-paginate).
  #   * `#each_page` — yield page-by-page (manual control via `#next_page?` / `#next_page`).
  #   * `#first(n)` — the first `n` items across pages, fetched lazily (stops as soon as it has `n`).
  #
  # @example auto-paginate every item
  #   client.customers.list(limit: 50).each { |c| puts c.id }
  # @example page-by-page
  #   client.customers.list.each_page { |page| process(page.data) }
  # @example just the first 10, lazily
  #   top = client.customers.list.first(10)
  #
  # @note Items must respond to `#id` — the next page's `starting_after` cursor is the `id` of the
  #   last item on the current page. Every list item in the frozen surface satisfies this.
  class Page
    # Items on this page — already deserialized into typed POROs by the resource's `fetch_page`.
    # @return [Array<Object>]
    attr_reader :data
    # Whether the API reports more pages after this one — the ONLY end-of-list signal.
    # @return [Boolean]
    attr_reader :has_more

    # Message raised by {#next_page} when there is no next page to fetch.
    NO_NEXT_PAGE_MESSAGE = "No next page; guard with `#next_page?` (or check `#has_more`) first."

    class << self
      # Build the FIRST page by invoking `fetch_page` with no cursor (so the closure uses the
      # caller's `starting_after`, if any). This is the entry point a resource's `list*` calls.
      #
      # @param fetch_page [#call] `->(cursor) { { data: [...], has_more: bool } }` — fetches the
      #   page after `cursor` (`nil` ⇒ the first page) and returns the wire envelope
      # @return [Dinie::Page]
      def from_fetch(fetch_page)
        build(fetch_page.call(nil), fetch_page)
      end

      # Wrap a fetched `{ data:, has_more: }` envelope (already item-deserialized) in a `Page`.
      #
      # @api private
      # @param envelope [Hash] `{ data: Array, has_more: Boolean }`
      # @param fetch_page [#call]
      # @return [Dinie::Page]
      def build(envelope, fetch_page)
        new(data: envelope[:data] || [], has_more: envelope[:has_more] == true, fetch_page: fetch_page)
      end

      # The deterministic discriminator (architecture §7.5/§11): a list endpoint is paginated **iff**
      # its envelope carries `has_more`. `/banks` lacks it, so the platform resource (story 010)
      # returns a flat `Array<Bank>` instead of a `Page`. Exposed here so that rule has one home.
      #
      # @param envelope [Object] a parsed response body
      # @return [Boolean] true when the body is a paginated list envelope
      def paginated?(envelope)
        envelope.is_a?(Hash) && envelope.key?(:has_more)
      end
    end

    # @param data [Array<Object>] this page's items
    # @param has_more [Boolean] whether more pages follow
    # @param fetch_page [#call] `->(cursor) { envelope }` for the next page
    def initialize(data:, has_more:, fetch_page:)
      @data = data
      @has_more = has_more
      @fetch_page = fetch_page
      freeze
    end

    # Whether a next page can be fetched. Driven by `has_more`; the `!data.empty?` guard is a safety
    # net — an empty page has no last item (so no cursor), so we stop rather than loop forever on a
    # malformed `{ data: [], has_more: true }`.
    #
    # @return [Boolean]
    def next_page?
      @has_more && !@data.empty?
    end

    # Fetch the next page. The cursor is the `id` of the LAST item on this page (mapped to
    # `starting_after` by the closure). Guard with {#next_page?} before calling.
    #
    # @return [Dinie::Page]
    # @raise [Dinie::Error] when there is no next page
    def next_page
      raise Dinie::Error, NO_NEXT_PAGE_MESSAGE unless next_page?

      self.class.build(@fetch_page.call(@data.last.id), @fetch_page)
    end

    # Auto-paginate: yield every item of this page, then every item of each following page, until
    # `has_more` is false. Without a block, returns an `Enumerator` (`.map` / `.first` / `.lazy`).
    #
    # @yieldparam item [Object]
    # @return [self, Enumerator]
    def each(&block)
      return enum_for(:each) unless block_given?

      page = self
      loop do
        page.data.each(&block)
        break unless page.next_page?

        page = page.next_page
      end
      self
    end
    alias auto_paging_each each

    # Yield page-by-page (manual control), following the cursor until `has_more` is false. Without
    # a block, returns an `Enumerator` over the pages.
    #
    # @yieldparam page [Dinie::Page]
    # @return [self, Enumerator]
    def each_page
      return enum_for(:each_page) unless block_given?

      page = self
      loop do
        yield page
        break unless page.next_page?

        page = page.next_page
      end
      self
    end

    # The first `count` items across pages (or the very first item when `count` is omitted),
    # fetched lazily — only as many pages as needed are requested.
    #
    # @param count [Integer, nil] how many items to take; omit for a single item
    # @return [Object, Array<Object>]
    def first(count = UNSPECIFIED)
      return auto_paging_each.first if count.equal?(UNSPECIFIED)

      auto_paging_each.first(count)
    end

    # Sentinel distinguishing `first` (one item) from `first(n)` (an array) — `nil`/`0` are valid `n`.
    UNSPECIFIED = Object.new
    private_constant :UNSPECIFIED
  end
end
