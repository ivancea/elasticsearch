# Creates the "7. ES|QL controls: Any - failing shapes" dashboard: query shapes from Slack control threads that error
# or give misleading results with the "__ANY__" auto-removal prototype (branch investigations/kibana-any).
# Controls send "__ANY__" when empty (send_any_value), except the one marked as sending null.
param([string]$Kibana = 'http://localhost:5601', [string]$Id = $null)

$from = 'FROM any_demo'
function lines([string[]]$parts) { ($parts | Where-Object { $_ }) -join "`n" }

function control([int]$x, [int]$w, [hashtable]$config, [bool]$sendAny = $true) {
  if ($sendAny) { $config.send_any_value = $true }
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
function section([string]$title, [int]$y, [object[]]$panels) {
  [ordered]@{ title = $title; collapsed = $false; grid = @{ y = $y }; panels = $panels }
}
$count = '| STATS docs = COUNT(*)'

$staged = section '1. Fails: parameter staged in EVAL (Any gives an error)' 0 @(
  (control 0 20 ([ordered]@{ title = 'Hosts (one comma-joined value per region)'; control_type = 'VALUES_FROM_QUERY'
      esql_query = 'FROM any_demo | WHERE region IS NOT NULL | STATS ids = MV_CONCAT(MV_SORT(VALUES(host)), ",") BY region | KEEP ids'
      variable_name = 'fq_ids'; variable_type = 'values'; single_select = $true; selected_options = @() })),
  (control 20 16 ([ordered]@{ title = 'Host (label to key)'; control_type = 'VALUES_FROM_QUERY'; esql_query = 'FROM any_demo | STATS BY host'
      variable_name = 'fq_host'; variable_type = 'values'; single_select = $true; selected_options = @() })),
  (metric 0 2 16 'EVAL ids = SPLIT(?fq_ids, ",") | WHERE MV_CONTAINS(ids, host)' (lines $from, '| EVAL ids = SPLIT(?fq_ids, ",")', '| WHERE MV_CONTAINS(ids, host)', $count) 'docs'),
  (metric 16 2 16 'Inline (works): WHERE MV_CONTAINS(SPLIT(?fq_ids, ","), host)' (lines $from, '| WHERE MV_CONTAINS(SPLIT(?fq_ids, ","), host)', $count) 'docs'),
  (metric 32 2 16 'EVAL key = ?fq_host | WHERE host == key' (lines $from, '| EVAL key = ?fq_host', '| WHERE host == key', $count) 'docs')
)

$misleading = section '2. Misleading: boolean parent inside CASE or under NOT' 10 @(
  (control 0 16 ([ordered]@{ title = 'OS'; control_type = 'VALUES_FROM_QUERY'; esql_query = 'FROM any_demo | STATS BY os'
      variable_name = 'fq_os'; variable_type = 'values'; single_select = $true; selected_options = @() })),
  (metric 0 2 16 'CASE(?fq_os == "linux", bytes > 5000, true): Any acts as linux' (lines $from, '| WHERE CASE(?fq_os == "linux", bytes > 5000, true)', $count) 'docs'),
  (metric 16 2 16 'NOT MV_INTERSECTS(?fq_os, os): Any gives 0' (lines $from, '| WHERE NOT MV_INTERSECTS(?fq_os, os)', $count) 'docs'),
  (metric 32 2 16 'Reference (no params): all docs / bytes > 5000' (lines $from, '| STATS docs = COUNT(*), big = COUNT(*) WHERE bytes > 5000') 'docs' 'big')
)

$rum = section '3. OTel RUM shape: null gives 0 rows, Any gives every doc with the field' 20 @(
  (control 0 20 ([ordered]@{ title = 'OS (sends null when empty)'; control_type = 'VALUES_FROM_QUERY'; esql_query = 'FROM any_demo | STATS BY os'
      variable_name = 'fq_os_null'; variable_type = 'values'; single_select = $true; selected_options = @() }) $false),
  (metric 0 2 24 'null: os IS NOT NULL AND MV_CONTAINS(?fq_os_null, os)' (lines $from, '| WHERE os IS NOT NULL AND MV_CONTAINS(?fq_os_null, os)', $count) 'docs'),
  (metric 24 2 24 'Any (OS control of section 2): os IS NOT NULL AND MV_CONTAINS(?fq_os, os)' (lines $from, '| WHERE os IS NOT NULL AND MV_CONTAINS(?fq_os, os)', $count) 'docs')
)

$settings = section '4. Errors with Any: params that are settings, not filters' 30 @(
  (control 0 12 ([ordered]@{ title = 'Function'; control_type = 'STATIC_VALUES'; available_options = @('avg', 'min', 'max')
      variable_name = 'fq_func'; variable_type = 'functions'; single_select = $true; selected_options = @() })),
  (control 12 12 ([ordered]@{ title = 'Interval'; control_type = 'STATIC_VALUES'; available_options = @('1 hour', '1 day')
      variable_name = 'fq_interval'; variable_type = 'time_literal'; single_select = $true; selected_options = @() })),
  (control 24 12 ([ordered]@{ title = 'Sort by'; control_type = 'STATIC_VALUES'; available_options = @('bytes', 'latency_ms')
      variable_name = 'fq_sort'; variable_type = 'fields'; single_select = $true; selected_options = @() })),
  (metric 0 2 12 '??fq_func(bytes)::double' (lines $from, '| STATS v = ??fq_func(bytes)::double') 'v'),
  (table 12 2 18 10 'BUCKET(@timestamp, ?fq_interval)' (lines $from, '| STATS docs = COUNT(*) BY b = BUCKET(@timestamp, ?fq_interval)', '| SORT b') @('b') 'docs'),
  (table 30 2 18 10 'SORT ??fq_sort DESC' (lines $from, '| SORT ??fq_sort DESC', '| KEEP host, bytes', '| LIMIT 10') @('host') 'bytes')
)

$version = section '5. Kibana: version "1.0" is sent as a number' 44 @(
  (control 0 16 ([ordered]@{ title = 'Version'; control_type = 'STATIC_VALUES'; available_options = @('1.0', '1.1', '2.0')
      variable_name = 'fq_version'; variable_type = 'values'; single_select = $true; selected_options = @() })),
  (table 0 2 24 8 'version == ?fq_version' (lines 'ROW version = ["1.0", "1.1", "2.0"]', '| MV_EXPAND version', '| WHERE version == ?fq_version', '| STATS rows = COUNT(*) BY version') @('version') 'rows'),
  (table 24 2 24 8 'version == TO_STRING(?fq_version)' (lines 'ROW version = ["1.0", "1.1", "2.0"]', '| MV_EXPAND version', '| WHERE version == TO_STRING(?fq_version)', '| STATS rows = COUNT(*) BY version') @('version') 'rows')
)

$dashboard = [ordered]@{
  title       = '7. ES|QL controls: Any - failing shapes'
  description = 'Query shapes from Slack control threads that error or mislead with "__ANY__" auto-removal. Empty controls send "__ANY__", except "OS (sends null when empty)".'
  time_range  = [ordered]@{ from = 'now-7d'; to = 'now' }
  panels      = @($staged, $misleading, $rum, $settings, $version)
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
