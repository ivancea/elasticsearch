. "$PSScriptRoot\es.ps1"

# Prints the data-node operators (and any plan text) so we can see what was pushed to Lucene.
function p([string]$label, [string]$query, [string]$params = $null) {
  Write-Output "=== $label  params=$params"
  $raw = esql $query $params -profile
  if ($raw -like 'HTTP*') { Write-Output $raw; return }
  $r = $raw | ConvertFrom-Json
  foreach ($d in $r.profile.drivers) {
    if ($d.description -ne 'data') { continue }
    $ops = ($d.operators | ForEach-Object { $_.operator }) -join "`n    -> "
    Write-Output "  driver[$($d.description)]:`n    -> $ops"
  }
  if ($r.profile.plans) {
    foreach ($pl in $r.profile.plans) {
      if ($pl.description -eq 'data' -or $pl.description -like '*data*') { Write-Output "  plan[$($pl.description)]: $($pl.plan)" }
    }
  }
}

p 'reference: host == "a"' 'FROM kibana_any_test | WHERE host == "a" | KEEP id'
p 'D single, Any' 'FROM kibana_any_test | WHERE CASE(?host IS NULL, true, host == ?host) | KEEP id' '[{"host": null}]'
p 'D single, a' 'FROM kibana_any_test | WHERE CASE(?host IS NULL, true, host == ?host) | KEEP id' '[{"host": "a"}]'
p 'D MV_INTERSECTS, Any' 'FROM kibana_any_test | WHERE CASE(?host IS NULL, true, MV_INTERSECTS(?host, host)) | KEEP id' '[{"host": null}]'
p 'D MV_INTERSECTS, [a,b]' 'FROM kibana_any_test | WHERE CASE(?host IS NULL, true, MV_INTERSECTS(?host, host)) | KEEP id' '[{"host": ["a", "b"]}]'
p 'D MV_CONTAINS guarded, [a,b]' 'FROM kibana_any_test | WHERE CASE(?host IS NULL, true, host IS NOT NULL AND MV_CONTAINS(?host, host)) | KEEP id' '[{"host": ["a", "b"]}]'
p 'D+ flag, [a] + blank' 'FROM kibana_any_test | WHERE CASE(?host IS NULL AND NOT ?host_blank, true, (?host_blank AND host IS NULL) OR MV_INTERSECTS(?host, host)) | KEEP id' '[{"host": ["a"]}, {"host_blank": true}]'
p 'D+ flag, Any' 'FROM kibana_any_test | WHERE CASE(?host IS NULL AND NOT ?host_blank, true, (?host_blank AND host IS NULL) OR MV_INTERSECTS(?host, host)) | KEEP id' '[{"host": null}, {"host_blank": false}]'
p 'simple OR form, Any' 'FROM kibana_any_test | WHERE ?host IS NULL OR MV_INTERSECTS(?host, host) | KEEP id' '[{"host": null}]'
p 'simple OR form, [a]' 'FROM kibana_any_test | WHERE ?host IS NULL OR MV_INTERSECTS(?host, host) | KEEP id' '[{"host": ["a"]}]'
