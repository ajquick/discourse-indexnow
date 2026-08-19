# frozen_string_literal: true

require "json"
require "excon"

module DiscourseIndexNow
  class Client
    ENDPOINT = "https://api.indexnow.org/indexnow"

    class SubmissionError < StandardError
    end

    def self.submit(url)
      response =
        Excon.post(
          ENDPOINT,
          body: JSON.generate(payload(url)),
          headers: {
            "Content-Type" => "application/json",
          },
          connect_timeout: 10,
          read_timeout: 10,
          expects: [200],
        )

      { success: true, status: response.status }
    rescue Excon::Error::HTTPStatus => e
      status = e.response.status
      { success: false, status: status, error: "HTTP #{status}" }
    rescue Excon::Error::Timeout, Excon::Error::Socket => e
      { success: false, error: e.message }
    end

    def self.payload(url)
      {
        host: Discourse.current_hostname,
        key: SiteSetting.indexnow_api_key,
        keyLocation: "#{Discourse.base_url}/#{SiteSetting.indexnow_api_key}.txt",
        urlList: [url],
      }
    end
  end
end
