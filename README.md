# Src2LDAP (Source to LDAP)

Src2LDAP is a Ruby based utility that takes source data serialized in
JSON and synchronizes to an LDAP backend. LDAP is a excellent platform by
which to serve read intensive data in a scalable and highly available
manner. LDAP does not natively enforce referential integrity or track
changes on the data it holds. In a situation where these things are
needed one must employ a SOT (Source of Truth) external to LDAP and to
use a tool (such that this) to safely synchronize the data.

Src2LDAP was originally built to sync UNIX naming data (passwd, group,
services, automount) but is designed in such a way that pretty much any
data that can be mapped to a valid LDAP schema can be synchronized.

Src2LDAP only syncs entire maps at this time.

Src2LDAP does not require the source data to have field names that match
that of the LDAP schema. A translation mechanism performs the mappings.

There is complexity in regards to mapping structured data into a format
that is LDAP compatible. There are mapping and schema files that need to
be maintained by the user. The format and utility of those files is
documented in the doc directory

# Usage

`src2ldap --config=/etc/src2ldap/config.json --run`

Every option in the config file has command line option of the same
name. Array arguments are specified as comma delimited strings.

When using the CLI you must supply the --run argument to perform all
actions. This program can potentially modify production data that
affects large number of hosts so we do not want it to be easy to trigger
unintended changes.


`/etc/src2ldap/config.json`

```json
{
  "ldap_hosts"    : [ "host1", "host2", ... ],
  "ldap_port"     : 636,
  "ldap_user"     : "cn=someDN",
  "ldap_pass"     : "somePass",
  "ldap_creds"    : "/etc/src2ldap/ldap_creds.json",
  "start_tls"     : false,
  "tls_noverify"  : false,
  "endpoint_user" : "someUser",
  "endpoint_pass" : "somePass",
  "endpoint_creds": "/etc/src2ldap/endpoint_creds.json",
  "map_config"    : "/etc/src2ldap/maps.json",
  "maps"          : [ "map1", "map2", ...  ],
  "log_dir"       : "/var/log/src2ldap"
  "exact"         : false,
  "noop"          : false,
  "force_tty"     : false,
  "debug"         : false
}
```

**`ldap_hosts`**

The list of ldap servers to connect to for synchronization. These
servers will be tried in order and the first one that can be connected
to successfully with be used.

**`ldap_port`**

If not specified then 389 used when start_tls is in effect else 636.

**`ldap_user`**

The LDAP DN to connect with.

**`ldap_pass`**

The LDAP password to connect with.

**`ldap_creds`**

If you want to keep the config world readable but protect the ldap
username and password you can use a credential files rather than set
them on the command line or in the main config file.

`/etc/src2ldap/ldap_creds.json`

```json
{
  "user": "cn=someDN",
  "pass": "somePass"
}

```

**`start_tls`**

Connect to LDAP server using the start_tls protocol.

**`tls_noverify`**

DO NOT validate the LDAP server x509 certificate.

**`endpoint_user`**

If any src map data is retrieved from an http(s) endpoint and basic
authentication is required then use this username.

**`endpoint_pass`**

If any src maps data is retrieved from an http(s) and basic
authentication is required then use this password.

**`endpoint_creds`**

If you want to keep the config world readable but protect the endpoint
username and password you can use a credential files rather than set
them on the command line or in the main config file.

`/etc/src2ldap/endpoint_creds.json`

```json
{
  "user": "someUser",
  "pass": "somePass"
}
```

**`map_config`**

Path to the file in JSON format that describes for each map that will be
synchronized the following:

- Location of the source data.
- The base DN of the LDAP data.
- Fields mappings between src and LDAP data.
- Schema of LDAP data for CRUD operations.

This file is fully documented in `doc/map_config.md`

**`maps`**

The name(s) of maps that you wish to synchronize. The special token
`@all` will synchronize all maps.

**`log_dir`**

The location to write runtime logs to. The name of the log file will
always be src2ldap_YmdHMS.log

**`exact`**

If the LDAP data has objectClasses or attributes that are not defined in
our local schema files, then delete these during synchronization. AKA
make LDAP look exactly like source.

This should be used with caution and is really only necessary if either
(a) you are truly a retentive control freak or (b) extraneous LDAP
data affects things in a negative way.

See `doc/exact.md` for a example of this feature.

**`noop`**

Do NOT make any changes to LDAP. Only show what would have been changed
if an active run was performed.

**`force_tty`**

If you are running interactively and attempt to pipe the output of the
command to some filter, stdout gets suppressed due to tty discovery
failure. Use this to force output to stdout (and the filter) for this
use case.

**`debug`**

Set the log level to debug.

<!--  LocalWords:  LDAP config CLI json ldap cn someDN somePass creds
 -->
<!--  LocalWords:  tls noverify someUser dir noop DN src http YmdHMS
 -->
<!--  LocalWords:  objectClasses AKA stdout
 -->
