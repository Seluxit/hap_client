require 'http/parser'

module HAP
  module Parser
    def init_parser
      @parser = Http::Parser.new(self)
    end

    def receive_data(data)
      if encryption_ready?
        data = decrypt(data)

        if data.start_with?("EVENT/")
          data.sub!("EVENT/","HTTP/")
        end
      end

      @parser << data
    end

    def on_message_begin
      @headers = nil
      @body = ''
    end

    def on_headers_complete(headers)
      @headers = headers
    end

    def on_body(chunk)
      @body << chunk
    end

    def on_message_complete
      parse_message(@body)
    end

  end
end
