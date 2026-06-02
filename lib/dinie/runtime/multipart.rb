# frozen_string_literal: true

require "stringio"
require "faraday/multipart"

module Dinie
  module Internal
    # Transport wrapper for a `multipart/form-data` request body (architecture §10/§14, story 009).
    #
    # The runtime serializes a normal request body to a JSON String (the JSON-only path in
    # {HttpClient#serialize_body}). The KYC attachment upload — the project's only multipart
    # endpoint (`POST /customers/{id}/kyc-attachments`) — needs `multipart/form-data` instead, so
    # this is the seam Ruby adds that the V0.2 TS runtime deferred (the tracked RUNTIME GAP).
    #
    # An instance holds the deterministic scalar field-map (`fields`) plus the optional binary
    # `file` part. {HttpClient} recognizes it in `serialize_body`, hands {#to_faraday_body} to
    # Faraday with a bare `multipart/form-data` content type, and Faraday's `:multipart` request
    # middleware (mounted on the shared connection) appends the boundary and encodes every entry
    # — scalars become plain form-data parts, the `file` becomes a binary part. Setting the
    # content type explicitly forces multipart encoding even for the email variant, which carries
    # no `file` part (only a scalar `value`).
    #
    # ── runtime ↔ generated boundary (architecture §4) ──
    # Lives in `runtime/` (CODEOWNER humans). It is transport-aware (Faraday multipart parts) so
    # the generated KYC layer stays transport-agnostic: `Dinie::Kyc.serialize_upload` produces a
    # plain {Dinie::Kyc::UploadForm} (the conformance unit — fields + opaque file), and the
    # customers resource wraps it here at the boundary.
    class Multipart
      # Content type Faraday's multipart middleware matches on; it appends `; boundary=…` itself.
      CONTENT_TYPE = "multipart/form-data"
      # Fallback MIME type for a wrapped file part when the caller passes a bare IO/String. The API
      # validates the real format from the bytes; the SDK does not sniff it.
      DEFAULT_FILE_CONTENT_TYPE = "application/octet-stream"
      # Fallback filename for a wrapped file part with no `#path`.
      DEFAULT_FILE_FILENAME = "upload"

      # @return [Hash{Symbol => String}] the scalar form fields (alphabetical — R-ORDER)
      attr_reader :fields
      # @return [Object, nil] the file part (a `Faraday::Multipart::FilePart`, an IO, or raw bytes)
      attr_reader :file

      # @param fields [Hash{Symbol => String}] scalar form fields
      # @param file [Object, nil] optional binary file: a `Faraday::Multipart::FilePart`/`ParamPart`
      #   (passed through), an IO (`File.open(...)`), or a String of raw bytes
      def initialize(fields:, file: nil)
        @fields = fields
        @file = file
      end

      # The Faraday multipart body: the scalar fields plus a `file` part wrapped for upload when
      # present. Faraday's `:multipart` middleware encodes the returned Hash.
      #
      # @return [Hash{Symbol => Object}]
      def to_faraday_body
        body = @fields.dup
        body[:file] = wrap_file(@file) unless @file.nil?
        body
      end

      private

      # Wrap a caller-supplied file into a Faraday multipart part. An already-wrapped part passes
      # through; an IO is wrapped directly; a String is treated as raw bytes via a StringIO.
      def wrap_file(file)
        return file if multipart_part?(file)

        io = file.respond_to?(:read) ? file : StringIO.new(file.to_s)
        filename = file.respond_to?(:path) && file.path ? File.basename(file.path) : DEFAULT_FILE_FILENAME
        Faraday::Multipart::FilePart.new(io, DEFAULT_FILE_CONTENT_TYPE, filename)
      end

      def multipart_part?(file)
        file.is_a?(Faraday::Multipart::FilePart) || file.is_a?(Faraday::Multipart::ParamPart)
      end
    end
  end
end
