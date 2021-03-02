Our schema of a group object:

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

LDAP representation of a group object:

```
dn: cn=dilbert,ou=group,dc=acmewidgets,dc=name
objectClass: top
objectClass: groupOfNames
objectClass: posixGroup
objectClass: friendlyCountry
gidNumber: 2048
cn: dilbert
memberUid: dogbert
memberUid: catbert
co: elbonia
```

--------------------------------

For the above definitions we see that the LDAP entry has and additional
objectClass `friendlyCountry` and attribute `co` outside what is in
out local Schema definition.

If `--exact` is NOT specified then this objectClass and attribute are
ignored during the synchronization process.

If `--exact` is specified then objectClass and attribute will deleted
during the synchnization process to make the LDAP entry look exactly
like the source entry.
