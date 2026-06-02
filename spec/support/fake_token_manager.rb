# frozen_string_literal: true

# A stand-in for the real OAuth2 `TokenManager` (story 004). Honors the injected DI seam
# {Dinie::Internal::HttpClient} relies on: `#access_token` and `#invalidate!`.
#
# `invalidate!` advances to the next token in the list, so a spec can prove the 401 one-shot
# re-auth used a *fresh* token (assert the second request's `Authorization` header). The token
# endpoint is never hit — there is no network here, which is what keeps the suite zero-network.
class FakeTokenManager
  # @return [Integer] how many times {#invalidate!} was called (the 401 one-shot asserts this)
  attr_reader :invalidate_count

  # @param tokens [Array<String>] the sequence of tokens handed out across invalidations
  def initialize(tokens: ["test-token"])
    @tokens = tokens
    @index = 0
    @invalidate_count = 0
  end

  # @return [String] the current access token (clamped to the last entry)
  def access_token
    @tokens[[@index, @tokens.size - 1].min]
  end

  # Drop the cached token and advance to the next one (mirrors a cache invalidation).
  #
  # @return [void]
  def invalidate!
    @invalidate_count += 1
    @index += 1
  end
end
