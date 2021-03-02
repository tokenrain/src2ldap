#!ruby

require 'json'
require 'logging'
require 'net/https'
require 'net/ldap'

class Src2LDAP
  KEYS_REQ = [:ldap_hosts, :ldap_user, :ldap_pass, :map_config, :maps].freeze
  LDAP_PORT = 389
  LDAPS_PORT = 636

  def init_logging(log_dir, debug, force_tty)
    time = Time.now.strftime('%Y%m%d%H%M%S')
    log = Logging.logger['src2ldap']

    if log_dir && log_dir != ''
      log.add_appenders(
        Logging.appenders.file(
          "#{log_dir}/src2ldap_#{time}.log",
          :layout => Logging.layouts.pattern(:pattern => '[%d] %5l: %m\n')
        )
      )
    end

    if $stdout.isatty || force_tty
      log.add_appenders(
        Logging.appenders.stdout(
          'stdout',
           :layout => Logging.layouts.pattern(:pattern => '[%d] %5l: %m\n')
        )
      )
    end
    # :debug < :info < :warn < :error < :fatal
    log.level = debug ? :debug : :info

    log
  end

  # merge passed in config with config file and deal with credentials
  # that may live in their own files
  def rationalize_config(config)
    @log.debug "#{__method__} called by #{caller_locations(1, 1)[0].label}"
    # new hash of the elements in the config file (if specified)
    config_file = Hash.new
    if config[:file]
      begin
        config_file = JSON.parse(File.read(config[:file]))
      rescue Exception => e # rubocop:disable Lint/RescueException
        log.error "Can not parse #{config[:file]}, #{e.message}"
        exit 1
      end
      config_file = Hash[config_file.map { |k, v| [k.to_sym, v] }]
    end

    # add elements from the config file if not already defined
    config_file.keys.each do |k|
      if !config.key?(k)
        config[k] = config_file[k]
      end
    end

    # default ldap port based on :start_tls
    if !config.key?(:ldap_port)
      config[:ldap_port] = config[:start_tls] ? LDAP_PORT : LDAPS_PORT
    end

    # ldap user and pass can come from a separate file
    if config[:ldap_creds]
      begin
        ldap_creds = JSON.parse(File.read(config[:ldap_creds]))
      rescue Exception => e # rubocop:disable Lint/RescueException
        log.error "Can not parse #{config[:ldap_creds]}, #{e.message}"
        exit 1
      end
      if !ldap_creds['user'] || !!ldap_creds['pass']
        log.error "#{config[:ldap_creds]} is invalid (missing user|pass)"
        exit 1
      end
      config[:ldap_user] = ldap_creds['user']
      config[:ldap_pass] = ldap_creds['pass']
      config.delete(:ldap_creds)
    end

    # endpoint user and pass can come from a separate file
    if config[:endpoint_creds]
      begin
        endpoint_creds = JSON.parse(File.read(config[:endpoint_creds]))
      rescue Exception => e # rubocop:disable Lint/RescueException
        log.error "Can not parse #{config[:endpoint_creds]}, #{e.message}"
        exit 1
      end
      if !endpoint_creds['user'] || !endpoint_creds['pass']
        log.error "#{config[:endpoint_creds]} is invalid (missing user|pass)"
        exit 1
      end
      config[:endpoint_user] = endpoint_creds['user']
      config[:endpoint_pass] = endpoint_creds['pass']
      config.delete(:endpoint_creds)
    end

    config
  end

  # ensure required config elements have been provided
  def validate_config!(config)
    @log.debug "#{__method__} called by #{caller_locations(1, 1)[0].label}"
    missing = Array.new
    KEYS_REQ.each do |k|
      if !config.key?(k)
        missing << k
      end
    end
    if !missing.empty?
      @log.error "Missing config elements: #{missing.join(',')}"
      exit 1
    end
  end

  # since we only support password auth, tls|start_tls is required
  def init_ldap
    @log.debug "#{__method__} called by #{caller_locations(1, 1)[0].label}"
    if @config[:tls_noverify]
      tls_options = { :verify_mode => OpenSSL::SSL::VERIFY_NONE }
    else
      tls_options = OpenSSL::SSL::SSLContext::DEFAULT_PARAMS
    end

    encryption = {
      :method => (@config[:start_tls] ? :start_tls : :simple_tls),
      :tls_options => tls_options,
    }

    ldap = Net::LDAP.new(:hosts => @config[:ldap_hosts].map { |h| [ h, @config[:ldap_port] ] },
                         :auth => {
                           :method => :simple,
                           :username => @config[:ldap_user],
                           :password => @config[:ldap_pass],
                         },
                         :encryption => encryption)

    if !ldap.bind
      @log.error "LDAP authentication failed, #{ldap.get_operation_result.message}"
      exit 1
    end

    ldap
  end

  def initialize(config = {})
    @log = init_logging(config[:log_dir], config[:debug], config[:force_tty])
    config = rationalize_config(config)
    validate_config!(config)
    @config = config
    @ldap = init_ldap()
    @errors = 0
  end

  # return two arrays. The 1st contains all elements in a and not in
  # b. The second contains all elements in b and not in a
  def compare_arrays(a, b)
    @log.debug "#{__method__} called by #{caller_locations(1, 1)[0].label}"
    a ||= []
    b ||= []

    if a.sort == b.sort
      return [], []
    end

    in_a = Array.new
    in_b = Array.new

    a.each do |k|
      if !b.include?(k)
        in_a << k
      end
    end

    b.each do |k|
      if !a.include?(k)
        in_b << k
      end
    end

    [ in_a, in_b ]
  end


  # take an entry that exists in both src and ldap and compare the
  # attributes of those entries. Return the ldap operations that are
  # needed for sync.
  def compare_attr(is_array, attr, src, ldap)
    @log.debug "#{__method__} called by #{caller_locations(1, 1)[0].label}"
    ops = Array.new
    if is_array
      a, b = compare_arrays(src, ldap)
      if !a.empty?
        ops << [ :add, attr, a ]
      end
      if !b.empty?
        ops << [ :delete, attr, b ]
      end
    elsif src != ldap
      ops << [ :add, attr, src ]
      ops << [ :delete, attr, ldap ]
    end
    ops
  end

  def compare_entry(schema, src, ldap)
    @log.debug "#{__method__} called by #{caller_locations(1, 1)[0].label}"
    ops = Array.new

    # add any objectClasses in src but not in ldap. We will only remove
    # objectClasses in ldap that are not in src if :exact was specified
    # as a an option.
    a, b = compare_arrays(src[:objectClass], ldap[:objectClass])
    a.each do |oc|
      ops << [ :add, :objectClass, oc ]
    end

    # we know that each src and ldap entry have these must attributes so
    # we can skip the check to see if they exist in the attr list
    schema['must'].each do |attr_ns|
      attr = attr_ns.sub(/^@/, '')
      is_array = !(attr == attr_ns)
      attr = attr.to_sym
      attr_ops = compare_attr(is_array, attr, src[attr], ldap[attr])
      ops.concat(attr_ops) if !attr_ops.empty?
    end

    schema['may'].each do |attr_ns|
      attr = attr_ns.sub(/^@/, '')
      is_array = !(attr == attr_ns)
      attr = attr.to_sym
      if src.key?(attr) && !ldap.key?(attr)
        ops << [ :add, attr, src[attr] ]
      elsif ldap.key?(attr) && !src.key?(attr)
        ops << [ :delete, attr, nil ]
      else
        attr_ops = compare_attr(is_array, attr, src[attr], ldap[attr])
        ops.concat(attr_ops) if !attr_ops.empty?
      end
    end

    # We know the the total set of possible attribute are a combination
    # of must and may that we have specified in our schema. If we want
    # we can make the ldap look exactly like the src by deleting
    # attributes and objectClasses that exist outside of what we know in
    # our schema.
    if @config[:exact]
      possible_attrs = { :objectClass => true }
      schema['must'].concat(schema['may']).each do |attr_ns|
        attr = attr_ns.sub(/^@/, '')
        attr = attr.to_sym
        possible_attrs[attr] = true
      end

      ldap.keys.select { |k| !possible_attrs.key?(k) }. each do |attr|
        ops << [ :delete, attr, nil ]
      end

      b.each do |oc|
        ops << [ :delete, :objectClass, oc ]
      end
    end
    ops
  end

  def compare_data(schema, src, ldap)
    @log.debug "#{__method__} called by #{caller_locations(1, 1)[0].label}"
    adds = Array.new
    modifies = Array.new
    deletes = Array.new

    # add entries that are in src but not ldap
    src.each do |dn, data|
      if !ldap[dn]
        adds << { dn => data }
      end
    end

    # modifies
    src.each do |dn, src_data|
      next if !ldap[dn]
      ldap_data = ldap[dn]
      diff = compare_entry(schema, src_data, ldap_data)
      if !diff.empty?
        modifies << { dn => diff }
      end
    end

    # delete entries that are in ldap but not in src
    ldap.each do |dn, data|
      if !src[dn]
        deletes << { dn => data }
      end
    end

    [ adds, modifies, deletes ]
  end

  # ldap always returns every attribute as array values. We are choosing
  # to override that to make comparison simpler and to make updates for
  # scalar values a single operation. This will most likely come back to
  # bite me in the ass.
  def attr_is_array(map, schema, attr)
    @log.debug "#{__method__} called by #{caller_locations(1, 1)[0].label}"
    @memo ||= Hash.new
    @memo[map] ||= Hash.new
    @memo[map].key?(:objectClass) || @memo[map][:objectClass] = true

    if @memo[map].key?(attr)
      return @memo[map][attr]
    end

    if schema['must'].include?("@#{attr}") || schema['may'].include?("@#{attr}")
      @memo[map][attr] = true
    else
      @memo[map][attr] = false
    end
    @memo[map][attr]
  end

  # ruby net-ldap downcases all attribute names from their native
  # camelCase. This makes comparison and updates more complex so we
  # convert what we know back to camelCase.
  def attr_map(schema)
    @log.debug "#{__method__} called by #{caller_locations(1, 1)[0].label}"
    attrs_camel = [ 'objectClass' ]
    attrs_camel.concat(schema['must'].map { |s| s.sub(/^@/, '') })
    attrs_camel.concat(schema['may'].map { |s| s.sub(/^@/, '') })
    Hash[attrs_camel.map { |s| [s.downcase.to_sym, s.to_sym ] }]
  end

  # get the LDAP data and transform into a canonical format for
  # comparison This is a hash keyed by dn and containing all the
  # elements of the entry. Non array elements are converted into scalar
  # values.
  def ldap_get(map, schema)
    @log.debug "#{__method__} called by #{caller_locations(1, 1)[0].label}"
    res = @ldap.search(:base => map['base'],
                       :filter => Net::LDAP::Filter.eq(*schema['filter']))
    if !res
      raise "LDAP search failed, #{ldap.get_operation_result.message}"
    end

    attr_map = attr_map(schema)

    data = Hash.new
    res.each do |entry|
      dn = entry.dn
      entry_n = Hash.new
      entry.each do |attr, values|
        next if attr == :dn

        attr = attr_map[attr] if attr_map.key?(attr)
        if attr_is_array(map['ldap'], schema, attr)
          entry_n[attr] = values
        else
          entry_n[attr] = values.first
        end
      end
      data[dn] = entry_n
    end
    data
  end

  # take src JSON and transform into a canonical format for comparison
  # This is a hash keyed by dn and containing all the elements of the
  # entry. All elements are converted to strings as this is all LDAP
  # stores.
  def transform_src(map, schema, src)
    @log.debug "#{__method__} called by #{caller_locations(1, 1)[0].label}"
    data = Hash.new
    src.each do |elem|
      new_e = Hash.new
      new_e[:objectClass] = schema['objectClass']

      elem.each do |k, v|
        next if map.key?('mappings_append') && map['mappings_append'].key?(k)

        if !map['mappings'][k]
          raise "Invalid mapping for #{map['ldap']}, missing transform for #{k}"
        end

        if !v.is_a?(Array)
          new_e[map['mappings'][k].to_sym] = v.to_s
        else
          next if v.empty?
          new_e[map['mappings'][k].to_sym] = v.map { |s| s.to_s }
        end
      end

      if map.key?('mappings_create')
        map['mappings_create'].each do |k, v|
          new_e[v.to_sym] = elem[k].to_s
        end
      end

      if map.key?('mappings_append')
        map['mappings_append'].each do |k, v|
          if new_e[v.to_sym].is_a?(Array)
            new_e[v.to_sym].concat(elem[k].map { |s| s.to_s })
          else
            new_e[v.to_sym] = [new_e[v.to_sym]].concat(elem[k].map { |s| s.to_s })
          end
        end
      end

      if schema['dn'].is_a?(Array)
        rest = schema['dn'].dup
        first = rest.shift
        if new_e[first.to_sym].is_a?(Array)
          dn_pre_pre = "#{first}=#{new_e[first.to_sym].first}"
          dn_pre = rest.map { |d| "#{d}=#{new_e[d.to_sym]}" }.join(',')
          dn = "#{dn_pre_pre},#{dn_pre},#{map['base']}"
        else
          dn_pre = schema['dn'].map { |d| "#{d}=#{new_e[d.to_sym]}" }.join(',')
          dn = "#{dn_pre},#{map['base']}"
        end
      elsif new_e[schema['dn'].to_sym].is_a?(Array)
        dn = "#{schema['dn']}=#{new_e[schema['dn'].to_sym].first},#{map['base']}"
      else
        dn = "#{schema['dn']}=#{new_e[schema['dn'].to_sym]},#{map['base']}"
      end

      if map.key?('mappings_exclude')
        map['mappings_exclude'].each do |m|
          new_e.delete(m.to_sym)
        end
      end
      data[dn] = new_e
    end
    data
  end

  # src map data comes from a JSON file
  def do_file_map(map)
    @log.debug "#{__method__} called by #{caller_locations(1, 1)[0].label}"
    schema = JSON.parse(File.read(map['schema']))
    if !schema[map['ldap']]
      raise "Unknown ldap type #{map['ldap']} for schema #{map['schema']}"
    end
    file_data = JSON.parse(File.read(map['file']))
    if map.key?('key')
      file_data = file_data[map['key']]
    end

    begin
      src_data = transform_src(map, schema[map['ldap']], file_data)
      ldap_data = ldap_get(map, schema[map['ldap']])
    rescue Exception => e # rubocop:disable Lint/RescueException
      raise e
    end

    compare_data(schema[map['ldap']], src_data, ldap_data)
  end

  # src map data comes from an http(s) endpoint
  def do_endpoint_map(map)
    @log.debug "#{__method__} called by #{caller_locations(1, 1)[0].label}"
    schema = JSON.parse(File.read(map['schema']))
    if !schema[map['ldap']]
      raise "Unknown ldap type #{map['ldap']} for schema #{map['schema']}"
    end

    begin
      uri = URI.parse(map['endpoint'])
      http = Net::HTTP.new(uri.host, uri.port)
      http.open_timeout = 5
      http.read_timeout = 10
      if map['endpoint'] =~ /https/
        http.use_ssl = true
        if @config[:tls_noverify]
          http.verify_mode = OpenSSL::SSL::VERIFY_NONE
        end
      end
      request = Net::HTTP::Get.new(uri.request_uri)

      if @config[:endpoint_user] && @config[:endpoint_pass]
        request.basic_auth(@config[:endpoint_user], @config[:endpoint_pass])
      end

      response = http.request(request)
      if response.code.to_i != 200
        raise "Could not get #{map['endpoint']}, #{response.message}"
      end
      endpoint_data = JSON.parse(response.body)
    rescue Net::ReadTimeout => e
      raise "Read timeout for #{map['endpoint']}"
    rescue Net::OpenTimeout => e
      raise "Open timeout for #{map['endpoint']}"
    rescue RuntimeError => e
      raise e
    end

    if map.key?('key')
      endpoint_data = endpoint_data[map['key']]
    end

    begin
      src_data = transform_src(map, schema[map['ldap']], endpoint_data)
      ldap_data = ldap_get(map, schema[map['ldap']])
    rescue Exception => e # rubocop:disable Lint/RescueException
      raise e
    end

    compare_data(schema[map['ldap']], src_data, ldap_data)
  end

  # Process adds, deletes, modifies for an individual map.
  def do_map(map)
    @log.debug "#{__method__} called by #{caller_locations(1, 1)[0].label}"

    adds, modifies, deletes = nil, nil, nil # rubocop:disable Style/ParallelAssignment

    if !map['file'] && !map['endpoint']
      @errors += 1
      @log.error "#{map['ldap']} does not have file or endpoint key, skipping"
      return
    else
      begin
        if map['file']
          adds, modifies, deletes = do_file_map(map)
        elsif map['endpoint']
          adds, modifies, deletes = do_endpoint_map(map)
        end
      rescue Exception => e # rubocop:disable Lint/RescueException
        @errors += 1
        @log.error "map #{map['ldap']} could not be processed, #{e.message}"
        return
      end
    end

    if @config[:noop]
      tag_pre = 'WOULD_'
    end

    if map.key?('max_changes') && map['max_changes'].to_i >= 0
      num_changes = adds.count() + modifies.count() + deletes.count()
      if num_changes > map['max_changes'].to_i
        @errors += 1
        @log.error "WILL NOT ACT ON map #{map['ldap']}, changes (#{num_changes}) > max changes (#{map['max_changes']})"

        # if we have too many changes and are in noop mode then we will
        # still display those changes.
        if @config[:noop]
          tag_pre = 'NOT_'
        else
          return
        end
      end
    end

    adds.each do |a|
      a.each do |dn, attrs|
        msg = JSON.generate(:dn => dn, :attributes => attrs)
        if @config[:noop]
          @log.info "#{tag_pre}ADD: #{msg}"
          next
        end
        if @ldap.add(:dn => dn, :attributes => attrs)
          @log.info "ADD: #{msg}"
        else
          @errors += 1
          @log.error "ADD: #{msg} -- #{@ldap.get_operation_result.message}"
        end
      end
    end

    modifies.each do |m|
      m.each do |dn, ops|
        msg = JSON.generate(:dn => dn, :operations => ops)

        if @config[:noop]
          @log.info "#{tag_pre}MODIFY: #{msg}"
          next
        end
        if @ldap.modify(:dn => dn, :operations => ops)
          @log.info "MODIFY: #{msg}"
        else
          @errors += 1
          @log.error "MODIFY: #{msg} -- #{@ldap.get_operation_result.message}"
        end
      end
    end

    deletes.each do |a|
      a.each do |dn, attrs|
        msg = JSON.generate(:dn => dn, :attributes => attrs)
        if @config[:noop]
          @log.info "#{tag_pre}DELETE: #{msg}"
          next
        end
        if @ldap.delete(:dn => dn)
          @log.info "DELETE: #{msg}"
        else
          @errors += 1
          @log.error "DELETE: #{msg} -- #{@ldap.get_operation_result.message}"
        end
      end
    end
  end

  # take the _default key out of the map_config and apply those values
  # if not already defined.
  def rationalize_map_config(config)
    @log.debug "#{__method__} called by #{caller_locations(1, 1)[0].label}"
    if config['_default']
      defaults = config['_default']
      config.delete('_default')
      config.keys.each do |c|
        defaults.keys.each do |d|
          if !config[c].key?(d)
            config[c][d] = defaults[d]
          end
        end
      end
    end
    config
  end

  # once we have initialized or instance, process the requested maps
  def run
    @log.debug "#{__method__} called by #{caller_locations(1, 1)[0].label}"
    map_config = JSON.parse(File.read(@config[:map_config]))
    map_config = rationalize_map_config(map_config)

    # Get maps that are in play
    maps = Array.new
    map_config.keys.each do |map|
      if @config[:maps].include?('@all')
        maps << map
        next
      end

      next if !@config[:maps].include?(map)

      if map_config[map].key?('inc')
        map_config[map]['inc'].each do |i|
          maps << i if !maps.include?(i)
        end
      end
      maps << map if !maps.include?(map)
    end

    # Process maps that are in play
    maps.each do |map|
      do_map(map_config[map])
    end
    @errors
  end
end
