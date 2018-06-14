require 'json'

require_relative 'log'
require_relative 'parser'
require_relative 'request'
require_relative 'pairing'

module HAP
  class Client
    include Log
    include Parser
    include Request
    include Pairing

    def initialize(socket)
      @socket = socket
      @name = "Unknown Client"
      init_log()
    end

    def set_value(aid, iid, value)
      info("Set Value #{aid}:#{iid} to #{value}")
      data = {
        "characteristics" => [{
                                "aid" => aid,
                                "iid" => iid,
                                "value" => value
                              }]
      }

      res = put("/characteristics", "application/hap+json", JSON.generate(data))
      if res != ""
        warn(res)
      end
    end

    def get_accessories()
      info("Get Accessories")
      data = get("/")
      parse_accessories(data)
    end

    def to_s
        @name
    end

    private

    def parse_accessories(data)
      data = JSON.parse(data)

      services = data["accessories"][0]["services"]

      services.each do |service|
        case service["type"]
        when "3E"
          parse_characteristics(service)
        when "43"

        when "deadbeef-dead-abba-beef-123400000000"

        else
          warn("Unknown Service Type: " + service["type"])
        end
      end
    end

    def parse_characteristics(service)
      service["characteristics"].each do |char|
        val = char["value"]
        case char["type"]
        when "20"
          @manufacturer = val
        when "21"
          @model = val
        when "23"
          @name = val
        when "30"
          @serial = val
        when "52"
          @version = val
        end
      end
    end
  end
end
