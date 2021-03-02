Gem::Specification.new do |s|
  s.name           = 'src2ldap'
  s.version        = '0.1.0'
  s.date           = '2020-10-23'
  s.summary        = 'Src2LDAP'
  s.description    = 'Syncronize source data to LDAP'
  s.authors        = ['Mark Selby']
  s.email          = 'mselby@tokenrain.net'
  s.files          = [ 'bin/src2ldap',
                       'lib/src2ldap.rb',
                       'man/src2ldap.1' ]
  s.extensions     = [ 'man/extconf.rb' ]
  s.homepage       = 'https://github.com/tokenrain/src2ldap'
  s.license        = 'Apache-2.0'
  s.add_dependency 'json', '~> 2.3'
  s.add_dependency 'ruby-getoptions', '~> 0.1'
  s.add_dependency 'logging', '~> 2.3'
  s.add_dependency 'net-ldap', '~> 0.16'
end
