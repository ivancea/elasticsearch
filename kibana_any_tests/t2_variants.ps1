. "$PSScriptRoot\es.ps1"

# Empty list is now treated as null: D should give Any
$q = "FROM kibana_any_test | WHERE CASE(?host IS NULL, true, MV_INTERSECTS(?host, host)) | SORT id | KEEP id, host"
t 'D with MV_INTERSECTS, []' $q '[{"host": []}]'
t 'D with MV_INTERSECTS, [a]' $q '[{"host": ["a"]}]'
t 'D single-select empty string (current Kibana)' "FROM kibana_any_test | WHERE CASE(?host IS NULL, true, host == ?host) | SORT id | KEEP id, host" '[{"host": ""}]'

# D+ boolean flag for blank
$q = "FROM kibana_any_test | WHERE CASE(?host IS NULL AND NOT ?host_blank, true, (?host_blank AND host IS NULL) OR MV_INTERSECTS(?host, host)) | SORT id | KEEP id, host"
t 'D+ Any' $q '[{"host": null}, {"host_blank": false}]'
t 'D+ [a] + blank' $q '[{"host": ["a"]}, {"host_blank": true}]'
t 'D+ blank only' $q '[{"host": null}, {"host_blank": true}]'
t 'D+ [a] only' $q '[{"host": ["a"]}, {"host_blank": false}]'

# D+ sentinel (strings only)
$q = "FROM kibana_any_test | WHERE CASE(?host IS NULL, true, (MV_CONTAINS(?host, `"__blank__`") AND host IS NULL) OR MV_INTERSECTS(?host, host)) | SORT id | KEEP id, host"
t 'Sentinel [a, __blank__]' $q '[{"host": ["a", "__blank__"]}]'

# Exclude (keeps blanks, like DSL must_not) and Exists
$q = "FROM kibana_any_test | WHERE CASE(?host IS NULL, true, host IS NULL OR NOT MV_INTERSECTS(?host, host)) | SORT id | KEEP id, host"
t 'Exclude [a]' $q '[{"host": ["a"]}]'
t 'Exists' "FROM kibana_any_test | WHERE host IS NOT NULL | SORT id | KEEP id, host"

# Other field types
t 'MV_INTERSECTS integer [1]' "FROM kibana_any_test | WHERE MV_INTERSECTS(?n, n) | SORT id | KEEP id, n" '[{"n": [1]}]'
t 'MV_INTERSECTS boolean [true]' "FROM kibana_any_test | WHERE MV_INTERSECTS(?f, flag) | SORT id | KEEP id, flag" '[{"f": [true]}]'
t 'MV_INTERSECTS ip, string param' "FROM kibana_any_test | WHERE MV_INTERSECTS(?ip, ip) | SORT id | KEEP id, ip" '[{"ip": ["10.0.0.1"]}]'
t 'MV_INTERSECTS ip, TO_IP(param)' "FROM kibana_any_test | WHERE MV_INTERSECTS(TO_IP(?ip), ip) | SORT id | KEEP id, ip" '[{"ip": ["10.0.0.1"]}]'

# Grouping by a constant (option G) in plain STATS
t 'STATS BY g = null' "FROM kibana_any_test | STATS c = COUNT(*) BY g = null"
t 'STATS BY g = "all"' "FROM kibana_any_test | STATS c = COUNT(*) BY g = `"all`""
t 'STATS BY g = null, host' "FROM kibana_any_test | STATS c = COUNT(*) BY g = null, host | SORT host"
t 'STATS BY g = CASE(?f IS NULL, null, host)' "FROM kibana_any_test | STATS c = COUNT(*) BY g = CASE(?f IS NULL, null, host) | SORT g" '[{"f": null}]'

# ??field with null, ?field identifier with null
t '??field null' "FROM kibana_any_test | STATS c = COUNT(*) BY ??f" '[{"f": null}]'
t '?field identifier null' "FROM kibana_any_test | STATS c = COUNT(*) BY ?f" '[{"f": {"identifier": null}}]'
t '??field value' "FROM kibana_any_test | STATS c = COUNT(*) BY ??f | SORT host" '[{"f": "host"}]'
