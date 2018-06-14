require_relative 'encryption_request'

module HAP
  module Request
    include EncryptionRequest

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
            debug(req + TLV.read(data).to_s)
          end
        else
          debug(req)
        end
      end

      if data
        req << data.to_s
      end

      if encryption_ready?
        encrypt(req).each do |r|
          @socket.write(r)
        end
      else
        @socket.write(req)
      end

      read()
    end

    def read()
      init_parser()

      while(!@complete)
        d = @socket.recv(1042)
        if encryption_ready?
          d = decrypt(d)
        end
        receive_data(d)
      end
      return @body
    end
  end
end
