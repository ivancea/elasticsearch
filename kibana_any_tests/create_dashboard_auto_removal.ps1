# Creates the "6. ES|QL controls: Any - auto-removal" dashboard. Every control has send_any_value, so an empty
# selection sends "__ANY__" and ES|QL (branch investigations/kibana-any) replaces the nearest boolean condition using
# it with true, or drops it as a BY key. Filters are written without any "?x IS NULL" guard.
param([string]$Kibana = 'http://localhost:5601', [string]$Id = $null)

$from = 'FROM any_demo'
function marked([string]$name, [string]$body) { "// $name start`n$body`n// $name end" }
function lines([string[]]$parts) { ($parts | Where-Object { $_ }) -join "`n" }

function control([int]$x, [int]$w, [hashtable]$config) {
  $config.send_any_value = $true
  [ordered]@{ grid = @{ x = $x; y = 0; w = $w; h = 2 }; type = 'esql_control'; config = $config }
}
function metric([int]$x, [int]$y, [int]$w, [string]$title, [string]$query, [string]$primary, [string]$secondary = $null) {
  $metrics = @(@{ type = 'primary'; column = $primary })
  if ($secondary) { $metrics += @{ type = 'secondary'; column = $secondary } }
  [ordered]@{ grid = @{ x = $x; y = $y; w = $w; h = 6 }; type = 'vis'; config = [ordered]@{
      type = 'metric'; title = $title; data_source = @{ type = 'esql'; query = $query }; metrics = $metrics } }
}
function table([int]$x, [int]$y, [int]$w, [int]$h, [string]$title, [string]$query, [string[]]$rows, [string]$metricColumn) {
  [ordered]@{ grid = @{ x = $x; y = $y; w = $w; h = $h }; type = 'vis'; config = [ordered]@{
      type = 'data_table'; title = $title; data_source = @{ type = 'esql'; query = $query }
      metrics = @(@{ column = $metricColumn }); rows = @($rows | ForEach-Object { @{ column = $_ } }) } }
}
function bars([int]$x, [int]$y, [int]$w, [int]$h, [string]$title, [string]$query, [string]$breakdown) {
  [ordered]@{ grid = @{ x = $x; y = $y; w = $w; h = $h }; type = 'vis'; config = [ordered]@{
      type = 'xy'; title = $title
      layers = @([ordered]@{ type = 'bar_stacked'; data_source = @{ type = 'esql'; query = $query }
          x = @{ column = 'bucket' }; y = @(@{ column = 'docs' }); breakdown_by = @{ column = $breakdown } }) } }
}
function section([string]$title, [int]$y, [object[]]$panels) {
  [ordered]@{ title = $title; collapsed = $false; grid = @{ y = $y }; panels = $panels }
}

$byOs = lines '| EVAL os = COALESCE(os, "(no os)")', '| STATS docs = COUNT(*) BY os', '| SORT docs DESC'
$tagSets = lines '| EVAL tag_set = COALESCE(MV_CONCAT(MV_SORT(tags), ", "), "(no tags)")', '| STATS docs = COUNT(*) BY tag_set', '| SORT docs DESC'

$svFilter = marked 'Filter' '| WHERE MV_INTERSECTS(?ar_os, os)'
$eqFilter = marked 'Filter' '| WHERE os == ?ar_os'
$single = section '1. Single value (os): MV_INTERSECTS and ==' 0 @(
  (control 0 16 ([ordered]@{ title = 'Single value · OS'; control_type = 'VALUES_FROM_QUERY'; esql_query = 'FROM any_demo | STATS BY os'
      variable_name = 'ar_os'; variable_type = 'values'; single_select = $true; selected_options = @() })),
  (metric 0 2 12 'MV_INTERSECTS(?ar_os, os)' (lines $from, $svFilter, '| STATS docs = COUNT(*), no_os = COUNT(*) WHERE os IS NULL') 'docs' 'no_os'),
  (metric 12 2 12 'os == ?ar_os' (lines $from, $eqFilter, '| STATS docs = COUNT(*), no_os = COUNT(*) WHERE os IS NULL') 'docs' 'no_os'),
  (table 24 2 24 8 'Documents by OS' (lines $from, $svFilter, $byOs) @('os') 'docs')
)

$mvFilter = marked 'Filter' '| WHERE MV_INTERSECTS(?ar_tags, tags)'
$multi = section '2. Multivalue (tags): MV_INTERSECTS' 12 @(
  (control 0 16 ([ordered]@{ title = 'Multivalue · Tags'; control_type = 'VALUES_FROM_QUERY'; esql_query = 'FROM any_demo | MV_EXPAND tags | STATS BY tags'
      variable_name = 'ar_tags'; variable_type = 'multi_values'; single_select = $false; selected_options = @() })),
  (metric 0 2 12 'MV_INTERSECTS(?ar_tags, tags)' (lines $from, $mvFilter, '| STATS docs = COUNT(*), no_tags = COUNT(*) WHERE tags IS NULL') 'docs' 'no_tags'),
  (table 12 2 36 10 'Documents by tag combination' (lines $from, $mvFilter, $tagSets) @('tag_set') 'docs')
)

$breakdown = section '3. STATS BY ??field: "Any" drops the key' 26 @(
  (control 0 16 ([ordered]@{ title = 'Breakdown · Group by'; control_type = 'STATIC_VALUES'; available_options = @('os', 'region', 'host')
      variable_name = 'ar_group'; variable_type = 'fields'; single_select = $true; selected_options = @() })),
  (bars 0 2 24 10 'Documents over time BY bucket, ??ar_group' (lines $from, '| STATS docs = COUNT(*) BY bucket = BUCKET(@timestamp, 30, ?_tstart, ?_tend), ??ar_group') '??ar_group'),
  (table 24 2 24 10 'Documents BY ??ar_group' (lines $from, '| STATS docs = COUNT(*) BY ??ar_group', '| SORT docs DESC') @('??ar_group') 'docs')
)

$fvFilter = marked 'Filter' '| WHERE ??ar_field == ?ar_value'
$fieldValue = section '4. ??field == ?value: either side "Any" removes the filter' 40 @(
  (control 0 16 ([ordered]@{ title = 'Field'; control_type = 'STATIC_VALUES'; available_options = @('os', 'region', 'host')
      variable_name = 'ar_field'; variable_type = 'fields'; single_select = $true; selected_options = @() })),
  (control 16 24 ([ordered]@{ title = 'Value'; control_type = 'STATIC_VALUES'
      available_options = @('linux', 'windows', 'macos', 'eu-west', 'us-east', 'ap-south', 'web-01', 'web-02', 'web-03', 'api-01', 'api-02')
      variable_name = 'ar_value'; variable_type = 'values'; single_select = $true; selected_options = @() })),
  (metric 0 2 12 '??ar_field == ?ar_value' (lines $from, $fvFilter, '| STATS docs = COUNT(*)') 'docs'),
  (table 12 2 36 10 'Documents by OS, region and host' (lines $from, $fvFilter,
      '| EVAL os = COALESCE(os, "(no os)"), region = COALESCE(region, "(no region)")', '| STATS docs = COUNT(*) BY os, region, host', '| SORT docs DESC') @('os', 'region', 'host') 'docs')
)

$dashboard = [ordered]@{
  title       = '6. ES|QL controls: Any - auto-removal'
  description = 'Controls send "__ANY__" when empty (send_any_value). ES|QL replaces the nearest boolean condition using it with true, and drops it as a BY key. No IS NULL guards.'
  time_range  = [ordered]@{ from = 'now-7d'; to = 'now' }
  panels      = @($single, $multi, $breakdown, $fieldValue)
}

$body = $dashboard | ConvertTo-Json -Depth 40
$headers = @{ 'kbn-xsrf' = 'true'; 'elastic-api-version' = '2023-10-31' }
try {
  if ($Id) {
    Invoke-WebRequest -Method PUT -Uri "$Kibana/api/dashboards/$Id" -Headers $headers -ContentType 'application/json' `
      -Body ([Text.Encoding]::UTF8.GetBytes($body)) -UseBasicParsing | Out-Null
    "Updated dashboard: $Kibana/app/dashboards#/view/$Id"
  } else {
    $r = Invoke-WebRequest -Method POST -Uri "$Kibana/api/dashboards" -Headers $headers -ContentType 'application/json' `
      -Body ([Text.Encoding]::UTF8.GetBytes($body)) -UseBasicParsing
    "Created dashboard: $Kibana/app/dashboards#/view/$(($r.Content | ConvertFrom-Json).id)"
  }
} catch {
  "HTTP error: " + $(if ($_.ErrorDetails) { $_.ErrorDetails.Message } else { $_.Exception.Message })
}
