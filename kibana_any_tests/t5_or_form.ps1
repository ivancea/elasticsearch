. "$PSScriptRoot\es.ps1"
. "$PSScriptRoot\t4_profile.ps1" | Out-Null

p 'OR form single, a' 'FROM kibana_any_test | WHERE ?host IS NULL OR host == ?host | KEEP id' '[{"host": "a"}]'
t 'OR form single, a (rows)' 'FROM kibana_any_test | WHERE ?host IS NULL OR host == ?host | SORT id | KEEP id, host' '[{"host": "a"}]'
t 'OR form single, Any (rows)' 'FROM kibana_any_test | WHERE ?host IS NULL OR host == ?host | SORT id | KEEP id, host' '[{"host": null}]'

$q = 'FROM kibana_any_test | WHERE (?host IS NULL AND NOT ?host_blank) OR (?host_blank AND host IS NULL) OR MV_INTERSECTS(?host, host) | SORT id | KEEP id, host'
t 'OR form + blank flag, [a] + blank' $q '[{"host": ["a"]}, {"host_blank": true}]'
t 'OR form + blank flag, Any' $q '[{"host": null}, {"host_blank": false}]'
t 'OR form + blank flag, blank only' $q '[{"host": null}, {"host_blank": true}]'
