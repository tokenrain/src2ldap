#!ruby

makefile = "make:\n" \
           "\t%s\n" \
           "install:\n" \
           "\t%s\n" \
           "clean:\n" \
           "\t%s\n"

if RUBY_PLATFORM =~ /linux/
  make = 'gzip src2ldap.1'
  install = 'cp -r src2ldap.1.gz /usr/local/share/man/man1/'
  clean = 'sudo rm -f /usr/local/share/man/man1/src2ldap.1.gz'

  if Process.euid == 0
    File.write('Makefile', makefile % [make, install, clean])
  else
    File.write('Makefile', makefile % [':', ':', ':']) # dummy makefile
  end
end
