require 'json'

require_relative 'hap_client/log'
require_relative 'hap_client/parser'
require_relative 'hap_client/request'
require_relative 'hap_client/pairing'

module HAP
  module Client
    include Log
    include Parser
    include Request
    include Pairing

    def initialize
      @name = "Unknown Client"
      @mode = :init
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

      put("/characteristics", "application/hap+json", JSON.generate(data))
    end

    def subscribe(aid, iid)
      info("Subscribe to #{aid} #{iid}")
      data = {
        "characteristics" => [{
                                "aid" => aid,
                                "iid" => iid,
                                "ev" => "true"
                              }]
      }

      put("/characteristics", "application/hap+json", JSON.generate(data))
    end

    def get_accessories(&block)
      info("Get Accessories")
      get("/")

      if block_given?
        @callback = block
      end
    end

    def to_s
        @name
    end

    private

    def parse_message(data)
      case @mode
      when :pair_setup
        pair_setup_parse(data)
      when :pair_verify
        pair_verify_parse(data)
      else
        if !data.nil? and data != ""
          puts data
          data = parse_accessories(data)
        end
      end

      if @callback
        t = @callback
        @callback = nil
        t.call(data)
      end
    end

    def parse_accessories(data)
      data = JSON.parse(data)

      services = data["accessories"][0]["services"]

      services.each do |service|
        if service["type"] == "3E"
          parse_characteristics(service)
        end
      end

      return data
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
