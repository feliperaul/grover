# frozen_string_literal: true

class Grover
  #
  # Rack middleware for catching PDF requests and returning the upstream HTML as a PDF
  #
  # Much of this code was sourced from the PDFKit project
  # @see https://github.com/pdfkit/pdfkit
  #
  class Middleware # rubocop:disable Metrics/ClassLength
    def initialize(app, *args)
      @app = app
      @pdf_request = false
      @png_request = false
      @jpeg_request = false

      @root_url =
        args.last.is_a?(Hash) && args.last.key?(:root_url) ? args.last[:root_url] : Grover.configuration.root_url
    end

    def call(env)
      dup._call(env)
    end

    def _call(env) # rubocop:disable Metrics/MethodLength
      @request = Rack::Request.new(env)
      identify_request_type

      if grover_request?
        check_file_uri_configuration
        configure_env_for_grover_request(env)
      end
      status, headers, response = @app.call(env)
      response = update_response response, headers if grover_request? && html_content?(headers)

      [status, headers, response]
    ensure
      restore_env_from_grover_request(env) if grover_request?
    end

    private

    PDF_REGEX = /\.pdf$/i
    PNG_REGEX = /\.png$/i
    JPEG_REGEX = /\.jpe?g$/i

    attr_reader :pdf_request, :png_request, :jpeg_request

    def check_file_uri_configuration
      return unless Grover.configuration.allow_file_uris

      # The combination of middleware and allowing file URLs is exceptionally
      # unsafe as it can lead to data exfiltration from the host system.
      raise UnsafeConfigurationError, 'using `allow_file_uris` configuration with middleware is exceptionally unsafe'
    end

    def identify_request_type
      @pdf_request = Grover.configuration.use_pdf_middleware && path_matches?(PDF_REGEX)
      @png_request = Grover.configuration.use_png_middleware && path_matches?(PNG_REGEX)
      @jpeg_request = Grover.configuration.use_jpeg_middleware && path_matches?(JPEG_REGEX)
    end

    def path_matches?(regex)
      !@request.path.match(regex).nil?
    end

    def grover_request?
      (pdf_request || png_request || jpeg_request) && !ignore_path? && !ignore_request?
    end

    def ignore_path?
      ignore_path = Grover.configuration.ignore_path
      case ignore_path
      when String then @request.path.start_with? ignore_path
      when Regexp then !ignore_path.match(@request.path).nil?
      when Proc then ignore_path.call @request.path
      end
    end

    def ignore_request?
      ignore_request = Grover.configuration.ignore_request
      return false unless ignore_request.is_a?(Proc)

      ignore_request.call @request
    end

    def html_content?(headers)
      headers[lower_case_headers? ? 'content-type' : 'Content-Type'] =~ %r{text/html|application/xhtml\+xml}
    end

    def update_response(response, headers)
      body, content_type = convert_response response
      response.close if response.respond_to? :close
      assign_headers headers, body, content_type
      [body]
    end

    def convert_response(response)
      grover = create_grover_for_response(response)

      if pdf_request
        [convert_to_pdf(grover), 'application/pdf']
      elsif png_request
        [grover.to_png, 'image/png']
      elsif jpeg_request
        [grover.to_jpeg, 'image/jpeg']
      end
    end

    def convert_to_pdf(grover)
      if grover.show_front_cover? || grover.show_back_cover?
        add_cover_content grover
      else
        grover.to_pdf
      end
    end

    def create_grover_for_response(response) # rubocop:disable Metrics/AbcSize
      body = response.respond_to?(:body) ? response.body : response.join
      body = body.join if body.is_a?(Array)
      body = HTMLPreprocessor.process body, root_url, protocol

      options = { display_url: request_url }
      cookies = Rack::Utils.parse_cookies(env).map do |name, value|
        { name: name, value: Rack::Utils.escape(value), domain: env['HTTP_HOST'] }
      end
      options[:cookies] = cookies if cookies.any?

      Grover.new(body, **options)
    end

    def add_cover_content(grover)
      load_combine_pdf
      pdf = CombinePDF.parse grover.to_pdf
      pdf >> fetch_cover_pdf(grover.front_cover_path) if grover.show_front_cover?
      pdf << fetch_cover_pdf(grover.back_cover_path) if grover.show_back_cover?
      pdf.to_pdf
    end

    def load_combine_pdf
      require 'combine_pdf'
    rescue ::LoadError
      raise Grover::Error, 'Please add/install the "combine_pdf" gem to use the front/back cover page feature'
    end

    def fetch_cover_pdf(path)
      temp_env = env.deep_dup
      scrub_env! temp_env
      temp_env['PATH_INFO'], temp_env['QUERY_STRING'] = path.split '?'
      _, _, response = @app.call(temp_env)
      response.close if response.respond_to? :close
      grover = create_grover_for_response response
      CombinePDF.parse grover.to_pdf
    end

    def assign_headers(headers, body, content_type)
      # Do not cache results
      headers.delete(lower_case_headers? ? 'etag' : 'ETag')
      headers.delete(lower_case_headers? ? 'cache-control' : 'Cache-Control')

      headers[lower_case_headers? ? 'content-length' : 'Content-Length'] =
        (body.respond_to?(:bytesize) ? body.bytesize : body.size).to_s
      headers[lower_case_headers? ? 'content-type' : 'Content-Type'] = content_type
    end

    def configure_env_for_grover_request(env)
      # Save the env params we're overriding so we can restore them after the response is fetched
      @pre_request_env_params = env.slice('PATH_INFO', 'REQUEST_URI', 'HTTP_ACCEPT')

      # Override path/URI so any downstream middleware/app doesn't try actioning the request as PDF
      env['PATH_INFO'] = path_without_extension
      env['REQUEST_URI'] = @request.url
      env['HTTP_ACCEPT'] = concat(env['HTTP_ACCEPT'], Rack::Mime.mime_type('.html'))
      env['Rack-Middleware-Grover'] = 'true'
    end

    def restore_env_from_grover_request(env)
      return unless @pre_request_env_params.is_a? Hash

      # Restore the path/URI so any upstream middleware doesn't get confused
      env.merge! @pre_request_env_params
      env['REQUEST_URI'] = @request.url unless @pre_request_env_params.key? 'REQUEST_URI'
    end

    def concat(accepts, type)
      (accepts || '').split(',').unshift(type).compact.join(',')
    end

    def root_url
      @root_url ||= "#{env['rack.url_scheme']}://#{env['HTTP_HOST']}/"
    end

    def protocol
      env['rack.url_scheme']
    end

    def path_without_extension
      @request.path.sub(request_regex, '').sub(@request.script_name, '')
    end

    def request_regex
      if pdf_request
        PDF_REGEX
      elsif png_request
        PNG_REGEX
      elsif jpeg_request
        JPEG_REGEX
      end
    end

    def request_url
      "#{root_url.sub(%r{/\z}, '')}#{path_without_extension}"
    end

    def env
      @request.env
    end

    def scrub_env!(env)
      # Reset the env to remove any cached values from the original request
      env.delete_if { |k, _| k =~ /^(action_dispatch|rack)\.request/ }
      env.delete_if { |k, _| k =~ /^action_dispatch\.rescue/ }
      env['rack.input'] = StringIO.new
      env.delete 'CONTENT_LENGTH'
      env.delete 'RAW_POST_DATA'
    end

    def lower_case_headers?
      return @lower_case_headers if defined? @lower_case_headers

      @lower_case_headers = Gem::Version.new(Rack.release) >= Gem::Version.new('3')
    end
  end
end
