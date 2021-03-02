```json
{
    "group": {
        "objectClass": [
            "top",
            "groupOfNames",
            "posixGroup"
        ],
        "filter": [ "objectClass", "posixGroup" ],
        "dn": "cn",
        "must": [
            "cn",
            "gidNumber"
        ],
        "may": [
            "userPassword",
            "@memberUid",
            "description"
        ]
    }
}
```

There is indeed an argument that can be made that having to write local
schema in the above format is somewhat redundant due the inherint schema
that exists in all LDAP implementations. We enforce this to provide
explicit boundaries between scalar and array attributes which are hard
to distinguish between in LDAP. Your views may vary on the need/utility
of this.

This really only applies to the `must` and `may` sections of the schema
as the other keys are essential to the basic operation of this utility.

--------------------------------

```json
{
    "group": {
        "objectClass": [
            "top",
            "groupOfNames",
            "posixGroup"
        ],
        "filter": [ "objectClass", "posixGroup" ],
        "dn": "cn"
    }
}
```

The above keys `objectClass`, `filter`, and `dn` are essential in being
able to read and write vaild LDAP when using src2ldap.

When creating or comparing entries between src and LDAP we are likely
need to know the minimum set of objectClasses that define the attribute
set that we have in use

When querying LDAP we need to know of the filter that will provide us
with a dataset to compare against.

When performing create, update, or delete operations on LDAP it is
required to know the canonical key for the DN ofeach entry.

--------------------------------

```json
{
    "group": {
        "must": [
            "cn",
            "gidNumber"
        ],
        "may": [
            "userPassword",
            "@memberUid",
            "description"
        ]
    }
}
```

This list of required and optional LDAP atrributes for an LDAP
entry. Attributes prefixed with a `@` are deemed array based attributes
and that is used to aid comparison between source and LDAP data.
