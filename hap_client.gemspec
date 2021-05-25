lib = File.expand_path('../lib/', __FILE__)
$:.unshift lib unless $:.include?(lib)

require 'hap_client/version'

Gem::Specification.new do |s|
  s.name        = 'hap_client'
  s.version     = HapClient::VERSION
  s.date        = '2018-06-15'
  s.summary     = "HAP client"
  s.required_ruby_version = '>= 2.5.1'
  s.description = "Ruby Gem for Apple Homekit Client"
  s.authors     = ["Andreas Bomholtz"]
  s.email       = 'andreas@seluxit.com'
  s.files       = `git ls-files -z`.split("\x0").reject do |f|
    f.match(%r{^(test|spec|features)/})
  end
  s.homepage    = 'http://github.com/Seluxit/hap_client'
  s.license     = 'MIT'

  s.add_dependency "eventmachine", '~> 1.2'
  s.add_dependency "http_parser.rb", '~> 0.6'
  s.add_dependency "json", '~> 2.1'
  s.add_dependency 'ruby_home', '0.1.2'
  s.add_dependency "ruby_home-srp", '1.2.1'

  s.add_development_dependency "bundler", ">= 2.2.10"
  s.add_development_dependency 'rake', '~> 12.3'
  s.add_development_dependency 'rspec', '~> 3.0'
end
