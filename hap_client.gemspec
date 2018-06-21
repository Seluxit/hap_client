Gem::Specification.new do |s|
  s.name        = 'hap_client'
  s.version     = '0.0.1'
  s.date        = '2018-06-15'
  s.summary     = "HAP client"
  s.description = "Ruby Gem for Apple Homekit Client"
  s.authors     = ["Andreas Bomholtz"]
  s.email       = 'andreas@seluxit.com'
  s.files       = `git ls-files -z`.split("\x0").reject do |f|
    f.match(%r{^(test|spec|features)/})
  end
  s.homepage    = 'http://github.com/Seluxit/hap_client'
  s.license     = 'MIT'

  s.add_dependency "http_parser.rb"
  s.add_dependency "json"
  s.add_dependency 'ruby_home', '0.1.0'
  s.add_dependency "ruby_home-srp", '1.1.3'

  s.add_development_dependency 'bundler', '~> 1.16'
  s.add_development_dependency 'rake', '~> 12.3'
  s.add_development_dependency 'rspec', '~> 3.0'

end
