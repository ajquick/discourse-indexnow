# frozen_string_literal: true

require "json"
require "excon"

module DiscourseIndexNow
  class Client
    ENDPOINT = "https://api.indexnow.org/indexnow"
    MAX_URLS = 10_000

    class SubmissionError < StandardError
    end

    def self.submit_batch(urls)
      urls = Array(urls)
      if urls.size > MAX_URLS
        raise SubmissionError, "IndexNow batches cannot contain more than #{MAX_URLS} URLs"
      end

      response =
        Excon.post(
          ENDPOINT,
          body: JSON.generate(payload(urls)),
          headers: {
            "Content-Type" => "application/json",
          },
          connect_timeout: 10,
          read_timeout: 10,
          expects: [200, 202],
        )

      { success: true, status: response.status }
    rescue Excon::Error::HTTPStatus => e
      status = e.response.status
      result = { success: false, status: status, error: "HTTP #{status}" }
      result[:retry_after] = retry_after(e.response) if status == 429
      result
    rescue Excon::Error::Timeout, Excon::Error::Socket => e
      { success: false, error: e.message }
    end

    def self.payload(urls)
      urls = Array(urls)
      {
        host: Discourse.current_hostname,
        key: SiteSetting.indexnow_api_key,
        keyLocation: "#{Discourse.base_url}/#{SiteSetting.indexnow_api_key}.txt",
        urlList: urls,
      }
    end

    def self.retry_after(response)
      value = response.headers["Retry-After"] || response.headers["retry-after"]
      seconds = value.to_i
      seconds.positive? ? seconds : nil
    end
  end
end
