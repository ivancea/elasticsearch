. "$PSScriptRoot\es.ps1"
$base = 'FROM kibana_any_test | SORT id | KEEP id, host'

# D, single-select
$q = "FROM kibana_any_test | WHERE CASE(?host IS NULL, true, host == ?host) | SORT id | KEEP id, host"
t 'D single, Any' $q '[{"host": null}]'
t 'D single, a' $q '[{"host": "a"}]'

# D, multi-select
$q = "FROM kibana_any_test | WHERE CASE(?host IS NULL, true, host IS NOT NULL AND MV_CONTAINS(?host, host)) | SORT id | KEEP id, host"
t 'D multi, Any' $q '[{"host": null}]'
t 'D multi, [a]' $q '[{"host": ["a"]}]'
t 'D multi, [a,b]' $q '[{"host": ["a", "b"]}]'

# MV_CONTAINS raw semantics
t 'MV_CONTAINS(?host, host) no guard, [a]' "FROM kibana_any_test | EVAL m = MV_CONTAINS(?host, host) | SORT id | KEEP id, host, m" '[{"host": ["a"]}]'
t 'MV_CONTAINS(null, host)' "FROM kibana_any_test | EVAL m = MV_CONTAINS(?host, host) | SORT id | KEEP id, host, m" '[{"host": null}]'

# Is there an any-match function?
t 'MV_INTERSECTS exists?' "FROM kibana_any_test | EVAL m = MV_INTERSECTS(?host, host) | SORT id | KEEP id, host, m" '[{"host": ["a"]}]'

# IN with a list param (expansion PR not merged)
t 'IN list param' "FROM kibana_any_test | WHERE host IN (?host) | SORT id | KEEP id, host" '[{"host": ["a", "b"]}]'

# Request parser limits
t 'empty list param' $base.Replace('SORT', 'WHERE MV_CONTAINS(?host, host) | SORT') '[{"host": []}]'
t 'null entry in list' $base.Replace('SORT', 'WHERE MV_CONTAINS(?host, host) | SORT') '[{"host": ["a", null]}]'
t 'mixed types in list' $base.Replace('SORT', 'WHERE MV_CONTAINS(?n, n) | SORT') '[{"n": [1, "__blank__"]}]'
t 'absent param' $base.Replace('SORT', 'WHERE ?host IS NULL | SORT') '[]'
t 'structured param (for H)' $base.Replace('SORT', 'WHERE ?f IS NULL | SORT') '[{"f": {"values": ["a"], "blank": true}}]'

# Inlined text form for alerting
t 'inlined null text' "FROM kibana_any_test | WHERE CASE(null IS NULL, true, host IS NOT NULL AND MV_CONTAINS(null, host)) | SORT id | KEEP id, host"
