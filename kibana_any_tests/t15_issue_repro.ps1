# Minimal reproducer for the one-element list bug (CIDR_MATCH pushdown, STARTS_WITH), on the cloud cluster.
. "$PSScriptRoot\es.ps1"
$idx = 'esql_one_element_list'
es DELETE "/$idx" | Out-Null
es PUT "/$idx" '{"mappings":{"properties":{"ip":{"type":"ip"},"host":{"type":"keyword"}}}}' | Out-Null
es POST "/$idx/_doc?refresh=true" '{"ip":"192.168.1.1","host":"web-01"}' | Out-Null
"version: " + ((es GET '/' | ConvertFrom-Json).version.number)
function q([string]$query) {
  $r = es POST '/_query' (@{ query = $query } | ConvertTo-Json -Compress)
  if ($r -like 'HTTP*') { return "$query`n  -> $r" }
  $j = $r | ConvertFrom-Json
  $reason = $j._clusters.details.'(local)'.failures | ForEach-Object { $_.reason.reason } | Select-Object -First 1
  "$query`n  -> $($j.values | ForEach-Object { $_ -join ',' }) is_partial=$($j.is_partial)" + $(if ($reason) { " reason: $reason" } else { '' })
}
q "FROM $idx | WHERE CIDR_MATCH(ip, `"192.168.0.0/16`") | STATS c = COUNT(*)"
q "FROM $idx | WHERE CIDR_MATCH(ip, [`"192.168.0.0/16`"]) | STATS c = COUNT(*)"
q "FROM $idx | EVAL m = CIDR_MATCH(ip, [`"192.168.0.0/16`"]) | KEEP m"
q "FROM $idx | WHERE STARTS_WITH(host, `"web`") | STATS c = COUNT(*)"
q "FROM $idx | WHERE STARTS_WITH(host, [`"web`"]) | STATS c = COUNT(*)"
q "FROM $idx | EVAL m = STARTS_WITH(host, [`"web`"]) | KEEP m"
q "FROM $idx | WHERE host == [`"web-01`"] | STATS c = COUNT(*)"
