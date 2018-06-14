require 'rubygems'
require 'socket'
require_relative 'lib/client'

puts "Started"
server = TCPServer.new("0.0.0.0", 4242)
loop do
  Thread.start(server.accept) do |client|
    begin
      device = HAP::Client.new(client)
      device.info("Client connected")

      device.get_accessories()
      device.info("Connected")

      password = '111-11-111'

      loop do
        begin
          device.pair_setup(password)
          device.pair_verify()
          break
        rescue PairingError => e
          device.fatal("Failed to pair device: #{e}")
        end
      end

      device.get_accessories()
      device.set_value(1, 10, 0)
      sleep 3
      device.set_value(1, 10, 1)
    rescue Exception => e
      p e
      p e.backtrace
    end
  end
end
