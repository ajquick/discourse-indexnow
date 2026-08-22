# frozen_string_literal: true

module DiscourseIndexNow
  class KeyAccessibility
    CACHE_TTL = 5.minutes.to_i

    class << self
      def check(key)
        return false if key.blank?

        cache_key = "indexnow:key_check:#{Digest::SHA256.hexdigest(key)}"
        cached = Discourse.redis.get(cache_key)
        return cached == "true" unless cached.nil?

        accessible = probe(key)
        Discourse.redis.setex(cache_key, CACHE_TTL, accessible.to_s)
        accessible
      rescue Excon::Error
        false
      end

      private

      def probe(key)
        response =
          Excon.get(
            "#{Discourse.base_url}/#{key}.txt",
            connect_timeout: 10,
            read_timeout: 10,
            expects: [200],
          )

        response.body.to_s.strip == key
      rescue Excon::Error::HTTPStatus
        false
      end
    end
  end
end
