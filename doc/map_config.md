This is an example of the map_config object.

```json
{
  "_default": {
    "schema": "/etc/src2ldap/rfc2307.json",
    "max_changes": 32
  },
  "users": {
    "ldap"    : "user",
    "file"    : "/var/lib/src2ldap/files/users.json",
    "endpoint": "https://data.acmewidgets.name/users",
    "base"    : "ou=people,dc=acmewidgets,dc=name",
    "mappings": {
      "name"   : "uid",
      "uid"    : "uidNumber",
      "gid"    : "gidNumber",
      "gecos"  : "gecos",
      "homedir": "homeDirectory",
      "shell"  : "loginShell"
    },
    "mappings_create": {
      "name": "cn"
    }
  },
  "services": {
    "ldap"    : "services",
    "file"    : "/var/lib/src2ldap/files/services.json",
    "endpoint": "https://data.acmewidgets.name/services",
    "base"    : "ou=services,dc=acmewidgets,dc=name",
    "mappings": {
      "name"       : "cn",
      "port"       : "ipServicePort",
      "protocols"  : "ipServiceProtocol",
      "description": "description"
    },
    "mappings_append": {
      "aliases"  : "cn"
    }
  },
  "automountMap": {
    "ldap": "automountMap",
    "file": "/var/lib/src2ldap/files/automount.json",
    "key" : "automountMap",
    "base": "ou=automount,dc=dc1,dc=acmewidgets,dc=name",
    "mappings": {
      "name": "automountMapName"
    }
  },
  "automount": {
    "ldap"    : "automount",
    "file"    : "/var/lib/src2ldap/files/automount.json",
    "endpoint": "https://data.acmewidgets.name/automount",
    "key"     : "automount",
    "base"    : "ou=automount,dc=dc1,dc=acmewidgets,dc=name",
    "inc"     : [ "automountMap" ],
    "mappings": {
      "name": "automountKey",
      "map" : "automountMapName",
      "info": "automountInformation"
    },
    "mappings_exclude": [
      "automountMapName"
    ]
  }
```

--------------------------------

The JSON file pointed to in the `map_config` options play a major role
in defining values that are needed in synchonizing source to LDAP data.

The keys of this JSON hash represent the maps to be synchronized.

The special key `_default` represents settings that apply to all maps
but which can be overriden in the individual map config if needed.

--------------------------------

```json
{
  "schema": "file.json"
}
```

Every map needs to have a schema definition that is used during
synchronization. The schema files are discussed in `doc/schema.md`

Looking at the JSON above our schema file would at a minimun need to
contain definitions for the `users`, `services`, `automountMap`, and
`automount`.

--------------------------------

```json
{
  "max_changes": #
}

```

The maximum number of changes that are allowed for a single map for a
single run. Set to -1 to disable this safety check.

--------------------------------

```json
{
  "ldap": "key"
}
```

The key within the schema hash that correlates to this map.

--------------------------------

```json
{
  "file"    : "file.json"
  "endpoint": "http(s)://path"
}
```

Where to read the source data from. Source must be in JSON format.

Only one of file or endpoint can be specified for a single map.

Only basic authentication is supported for http(s) endpoints. Username
and Password for basic auth are set in the main configuration.

--------------------------------

```json
{
  "key": "value"
}
```

Allows for the source data of the map to exist not at the top level of
the JSON structure but under some key at the top level.

--------------------------------

```json
{
  "base": "dn"
}

```

The base DN for reading and writing LDAP data for a map.

--------------------------------

```json
{
  "inc": [ "map1", "map2", ... ]
}
```

Allow for cases where maps rely on other maps for required LDAP
structure/entries. These "included" maps are always processed before the
main map.

--------------------------------

```json
{
  "mappings": {
    "src0"   : "ldap0",
    "src1"   : "ldap1",
    "src2"   : "ldap2",
    "src3"   : "ldap3",
  }
}
```

The `mappings` stanza is the 1:1 translation between the names of the
source fields and the names of the LDAP attributes.

--------------------------------

```json
{
  "mappings_create": {
    "src0": "ldap0"
    "src1": "ldap1"
  }
}
```

The `mappings_create` stanza allows for the creation of additional LDAP
attributes from an already used source field.

For example the `posixAccount` ldap schema requires both a `uid` and
`cn` attribute. If one wanted to set those both the `name` key in the
source data you use `mappings_create` to assign the additional LDAP
attribute to an already used source key.

--------------------------------

```json
{
  "mappings_append": {
    "src1": "ldap1"
  }
}
```

The `mappings_append` stanza allows you to take a source key and append it
to an already existing LDAP attribute.

For example the services LDAP schema represents aliases as simply
additional `cn` attributes with the canonical service name being
repreented by the `cn` listed in the `dn`. This capability allows us to
have a source key such as `aliases` and append that to an already
existing attribute such as `cn`

--------------------------------

```json
{
  "mappings_exclude": [
    "ldap0"
  ]
}
```

`mappings_exclude` allows for the case when an LDAP attribute is used
only in the definition of an entries `DN` but does not have that
attribute in the body of the entry.

It is possible that one eeds to know the value of a field to construct
the `DN` but that LDAP schema will not allow this as a body
attribute. Thus you need to exclude this mapping from the list of
attributes in the body even though it is used for the entry `DN`
