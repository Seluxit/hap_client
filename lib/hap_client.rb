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
      @ids = {}

      @manufacturer = ""
      @model = ""
      @name = ""
      @serial = ""
      @version = ""

      init_request()
      init_log()
    end

    def set_value(aid, iid, value)
      info("Set Value #{aid}:#{iid} to #{value}")
      data = {
        "characteristics" => [{
                                "aid" => aid.to_i,
                                "iid" => iid.to_i,
                                "value" => value.to_i
                              }]
      }

      put("/characteristics", "application/hap+json", JSON.generate(data))
    end

    def subscribe(&block)
      events = []
      @values.each do |service|
        service[1].each do |val|
          value = val[1]
          if value[:perms].include?("ev")
            info("Subscribe to #{value[:aid]}:#{value[:iid]}")
            events.push({
                          :aid => value[:aid],
                          :iid => value[:iid],
                          :ev => true
                        })
          end
        end
      end

      data = {
        :characteristics => events
      }

      put("/characteristics", "application/hap+json", JSON.generate(data))

      if block_given?
        @callback = block
      end
    end

    def get_accessories(&block)
      info("Get Accessories")
      get("/")

      if block_given?
        @callback = block
      end
    end

    def get_value(aid, iid)
      begin
        return @values[aid][iid][:value]
      rescue
        return ""
      end
    end

    def get_type(aid, iid)
      begin
        return @ids[aid][iid]
      rescue
        return ""
      end
    end

    def get_id(service_id, characteristic_id)
      @services.each do |service|
        if service[:type] == service_id
          service[:characteristics].each do |char|
            if char[:type] == characteristic_id
              return char
            end
          end
        end
      end
      return nil
    end

    def to_s
      @name
    end

    private

    def parse_message(data)
      @res_queue.push(1)

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
      begin
        data = JSON.parse(data, :symbolize_names=>true)
      rescue JSON::ParserError => e
        error(e.inspect)
        error(data)
        return nil
      end

      if data[:accessories]
        @services = data[:accessories][0][:services]

        @services.each do |service|
          @values[service[:type]] = {}
          @ids[service[:iid]] = {}

          parse_characteristics(service)
        end
      elsif data[:characteristics]
        parse_event(data)
        init_parser
      end

      return data
    end

    def parse_event(data)
      val = data[:characteristics]
      val.each do |value|
        on_event(value[:aid], value[:iid], value[:value])
      end
    end

    def parse_characteristics(service)
      service[:characteristics].each do |char|
        val = char[:value]

        @values[service[:type]][char[:type]] = {
          :aid => char[:aid],
          :iid => char[:iid],
          :perms => char[:perms],
          :value => val
        }
        @ids[char[:aid]][char[:iid]] = {
          :service => service[:type],
          :characteristic => char[:type]
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
