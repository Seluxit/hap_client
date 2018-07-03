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
      @values = {}
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

    def subscribe_to_all()
      @values.each do |service|
        service.each do |val|
          if val[:perms].include?("ev")
            subscribe(val[:aid], val[:iid])
          end
        end
      end
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
          data = parse_accessories(data)
        end

        if @callback
          t = @callback
          @callback = nil
          t.call(data)
        end
      end
    end

    def parse_accessories(data)
      data = JSON.parse(data, :symbolize_names=>true)

      services = data[:accessories][0][:services]

      services.each do |service|
        @values[service[:type]] = {}

        parse_characteristics(service)
      end

      return data
    end

    def parse_characteristics(service)
      service[:characteristics].each do |char|
        val = char[:value]

        @values[service[:type]][char[:type]] = {
          :aid => char[:aid],
          :iid => char[:iid],
          :perms => char[:perms},
          :value => val
        }

        if service[:type] == "3E"
          case char[:type]
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
end
