require_relative 'encryption_request'

module HAP
  module Request
    include EncryptionRequest

    def init_request()
      @req_queue = EM::Queue.new
      @res_queue = EM::Queue.new

      response_work = nil

      request_work = Proc.new do |req|
        if encryption_ready?
          encrypt(req).each do |r|
            if @socket.nil?
              send_data(r)
            else
              @socket.write(r)
            end
          end
        else
          if @socket.nil?
            send_data(req)
          else
            @socket.write(req)
          end
        end

        init_parser()

        @res_queue.pop(&response_work)
      end

      response_work = Proc.new do |res|
        @req_queue.pop(&request_work)
      end

      @req_queue.pop(&request_work)
    end

    def get(url)
      request("GET", url)
    end

    def post(url, type, data)
      request("POST", url, type, data)
    end

    def put(url, type, data)
      request("PUT", url, type, data)
    end

    private

    def request(method, url, type=nil, data=nil)
      req = method + " " + url + " HTTP/1.1\r\n"
      req << "Host: homekit\r\n"

      if type
        req << "Content-Type: " + type + "\r\n"
      end
      if data
        req << "Content-Length: " + data.length.to_s + "\r\n"
      end
      req << "\r\n"

      if log_debug?
        if data
          if data[0] == '{'
            debug(req + data.to_s)
          else
            debug(req + RubyHome::HAP::TLV.read(data).to_s)
          end
        else
          debug(req)
        end
      end

      if data
        req << data.to_s
      end

      @req_queue.push(req)
    end
  end
end
