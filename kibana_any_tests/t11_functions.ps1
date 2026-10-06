# Compares the prototype functions (IN_SELECTION, IN_RANGE_SELECTION, FIELD_OR, OPTIONAL) with the hand-written
# templates they replace, on local any_demo, with the params Kibana sends.
$es = 'http://localhost:9200'
function esql([string]$query, [object[]]$params, [switch]$Rows) {
  $body = @{ query = $query; params = $params } | ConvertTo-Json -Depth 10 -Compress
  try {
    $r = Invoke-WebRequest -Method POST -Uri "$es/_query" -ContentType 'application/json' -Body ([Text.Encoding]::UTF8.GetBytes($body)) -UseBasicParsing
    $j = $r.Content | ConvertFrom-Json
    if ($Rows) { (($j.columns | ForEach-Object { $_.name }) -join ',') + ' | ' + (($j.values | ForEach-Object { $_ -join ':' }) -join '; ') } else { $j.values[0][0] }
  } catch { "ERROR: " + $(if ($_.ErrorDetails) { ($_.ErrorDetails.Message | ConvertFrom-Json).error.reason } else { $_.Exception.Message }) }
}
function check([string]$name, [string]$fn, [string]$template, [object[]]$params) {
  $a = esql "FROM any_demo | WHERE $fn | STATS c = COUNT(*)" $params
  $b = esql "FROM any_demo | WHERE $template | STATS c = COUNT(*)" $params
  "{0,-44} fn={1,-6} template={2,-6} {3}" -f $name, $a, $b, $(if ("$a" -eq "$b" -and "$a" -notlike 'ERROR*') { 'OK' } else { 'MISMATCH' })
}

$sv = 'IN_SELECTION(os, ?x)'; $svT = '?x IS NULL OR MV_INTERSECTS(?x, os)'
check 'single: Any' $sv $svT @(@{ x = $null })
check 'single: linux' $sv $svT @(@{ x = 'linux' })
check 'multi: [prod, beta]' 'IN_SELECTION(tags, ?x)' '?x IS NULL OR MV_INTERSECTS(?x, tags)' @(@{ x = @('prod', 'beta') })
check 'long with integer param: [404]' 'IN_SELECTION(status, ?x)' '?x IS NULL OR MV_INTERSECTS(TO_LONG(?x), status)' @(@{ x = @(404) })

$fl = 'IN_SELECTION(tags, ?x, {"include_nulls": ?b})'
$flT = '?x IS NULL OR MV_INTERSECTS(?x, tags) OR (COALESCE(?b, "false") == "true" AND tags IS NULL)'
check 'flag: Any + "true"' $fl $flT @(@{ x = $null }, @{ b = 'true' })
check 'flag: prod + "true"' $fl $flT @(@{ x = @('prod') }, @{ b = 'true' })
check 'flag: prod + "false"' $fl $flT @(@{ x = @('prod') }, @{ b = 'false' })

$nl = 'IN_SELECTION(tags, ?x, {"null_value": "__NULL__"})'
$nlT = '?x IS NULL OR MV_INTERSECTS(?x, tags) OR (tags IS NULL AND MV_CONTAINS(?x, "__NULL__"))'
check 'sentinel: [prod, __NULL__]' $nl $nlT @(@{ x = @('prod', '__NULL__') })
check 'sentinel: [__NULL__]' $nl $nlT @(@{ x = @('__NULL__') })

$nv = 'IN_SELECTION(secure, ?x, {"nulls": ?x__nulls})'
$nvT = '(?x IS NULL AND NOT ?x__nulls) OR MV_INTERSECTS(TO_BOOLEAN(?x), secure) OR (?x__nulls AND secure IS NULL)'
check 'companion bool: Any' $nv $nvT @(@{ x = $null }, @{ x__nulls = $false })
check 'companion bool: (No value) only' $nv $nvT @(@{ x = $null }, @{ x__nulls = $true })
check 'companion bool: ["true"] + (No value)' $nv $nvT @(@{ x = @('true') }, @{ x__nulls = $true })
check 'companion int: [1, 2] + (No value)' 'IN_SELECTION(priority, ?x, {"nulls": ?x__nulls})' `
  '(?x IS NULL AND NOT ?x__nulls) OR MV_INTERSECTS(?x, priority) OR (?x__nulls AND priority IS NULL)' @(@{ x = @(1, 2) }, @{ x__nulls = $true })

$rg = 'IN_RANGE_SELECTION(status, ?lo, ?hi)'
check 'range: Any' $rg 'true' @(@{ lo = $null }, @{ hi = $null })
check 'range: 400-499' $rg 'status >= 400 AND status <= 499' @(@{ lo = 400 }, @{ hi = 499 })
check 'range: >= 500' $rg 'status >= 500' @(@{ lo = 500 }, @{ hi = $null })
check 'range: <= 299' $rg 'status <= 299' @(@{ lo = $null }, @{ hi = 299 })

"--- FIELD_OR / OPTIONAL"
"FIELD_OR set:    " + (esql 'FROM any_demo | STATS c = COUNT(*) BY g = FIELD_OR(??f, "all") | SORT g | LIMIT 3' @(@{ f = 'os' }) -Rows)
"FIELD_OR unset:  " + (esql 'FROM any_demo | STATS c = COUNT(*) BY g = FIELD_OR(??f, "all")' @(@{ f = $null }) -Rows)
"OPTIONAL set:    " + (esql 'FROM any_demo | STATS c = COUNT(*) BY OPTIONAL(??f) | SORT os | LIMIT 3' @(@{ f = 'os' }) -Rows)
"OPTIONAL unset:  " + (esql 'FROM any_demo | STATS c = COUNT(*) BY OPTIONAL(??f)' @(@{ f = $null }) -Rows)
"OPTIONAL + key:  " + (esql 'FROM any_demo | STATS c = COUNT(*) BY region, OPTIONAL(??f) | SORT region | LIMIT 2' @(@{ f = $null }) -Rows)
"??f unset alone: " + (esql 'FROM any_demo | STATS c = COUNT(*) BY ??f' @(@{ f = $null }) -Rows)
