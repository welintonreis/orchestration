require "net/http"
require "json"

module AiQuota
  module Fetch
    # Shared HTTP plumbing for the provider fetchers. Follows the house style
    # from CloudflareService: Net::HTTP, no gem, errors carried as data rather
    # than raised at the view.
    class Base
      TIMEOUT = 10

      def initialize(account)
        @account = account
      end

      def call
        raise NotImplementedError
      end

      private

      attr_reader :account

      def get_json(url, headers = {})
        request_json(Net::HTTP::Get, url, headers)
      end

      def post_json(url, body, headers = {})
        request_json(Net::HTTP::Post, url, headers) { |req| req.body = body.to_json }
      end

      def request_json(verb, url, headers)
        uri = URI(url)
        req = verb.new(uri)
        headers.each { |k, v| req[k] = v }
        req["Accept"] = "application/json"
        req["Content-Type"] = "application/json" if verb == Net::HTTP::Post
        yield req if block_given?

        res = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
                              open_timeout: TIMEOUT, read_timeout: TIMEOUT) do |http|
          http.request(req)
        end

        [ res.code.to_i, safe_parse(res.body) ]
      rescue StandardError => e
        [ 0, { "error" => { "message" => e.message } } ]
      end

      def safe_parse(body)
        JSON.parse(body.to_s)
      rescue JSON::ParserError
        {}
      end

      # Providers phrase an expired credential half a dozen ways; the card needs
      # to tell "reauthenticate" apart from "provider is down".
      def auth_error?(status, payload)
        return true if status == 401

        text = payload.to_s.downcase
        text.match?(/expired|unauthorized|authentication|re-?authorize/)
      end
    end
  end
end
