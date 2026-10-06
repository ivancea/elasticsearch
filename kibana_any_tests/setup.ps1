. "$PSScriptRoot\es.ps1"
es DELETE '/kibana_any_test' | Out-Null
es PUT '/kibana_any_test' '{"mappings":{"dynamic":"strict","properties":{"id":{"type":"integer"},"host":{"type":"keyword"},"flag":{"type":"boolean"},"n":{"type":"integer"},"l":{"type":"long"},"ip":{"type":"ip"}}}}'
$bulk = (Get-Content "$PSScriptRoot\bulk.ndjson" -Raw) + "`n"
$r = es POST '/kibana_any_test/_bulk?refresh=true' $bulk 'application/x-ndjson'
if ($r -like 'HTTP*') { $r } else { "bulk errors: " + ($r | ConvertFrom-Json).errors }
(es POST '/_query' '{"query":"FROM kibana_any_test | KEEP id, host, flag, n, l, ip | LIMIT 0"}' | ConvertFrom-Json).columns | Format-Table name, type
esql 'FROM kibana_any_test | SORT id | KEEP id, host, flag, n, l, ip'
