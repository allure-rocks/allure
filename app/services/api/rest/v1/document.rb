# frozen_string_literal: true

module Api
  module Rest
    module V1
      # The served OpenAPI document (docs/dev/API.md): docs/openapi/v1.yaml with
      # the instance's server URL and the application version filled in at
      # request time, so the file never hardcodes a host.
      module Document
        PATH = Rails.root.join("docs/openapi/v1.yaml")
        BASE_PATH = "/api/rest/v1"

        module_function

        def source
          mtime = File.mtime(PATH)
          @source = nil unless @source_mtime == mtime
          @source_mtime = mtime
          @source ||= YAML.safe_load_file(PATH, aliases: true).freeze
        end

        def served(base_url: Allure::Federation.config.base_url, version: Allure::VERSION)
          document = source.deep_dup
          document["info"] = document.fetch("info").merge("version" => version)
          document["servers"] = [ { "url" => "#{base_url}#{BASE_PATH}", "description" => Allure::Federation.config.domain } ]
          document
        end

        def etag = Digest::SHA256.hexdigest([ File.mtime(PATH).to_f, Allure::VERSION, Allure::Federation.config.base_url ].join(":"))
      end
    end
  end
end
