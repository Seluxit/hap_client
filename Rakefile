$LOAD_PATH.unshift File.expand_path("../lib", __FILE__)
require "hap_client/version"

task :build do
  system "gem build hap_client.gemspec"
end

task :release => :build do
  system "gem push hap_client-#{HapClient::VERSION}.gem"
  system "rm hap_client-#{HapClient::VERSION}.gem"
end
