# Creates the "3. ES|QL controls: Any + include/exclude" demo dashboard: OS, Region and Tags each offer "Any",
# "(No value)" (the "__NULL__" sentinel) and their own include/exclude mode, like the Exclude toggle of classic controls.
param([string]$Kibana = 'http://localhost:5601', [string]$Id = $null)

# Per filter: "Any" (?x null) OR (mode is include) == (match). <match> is never null when ?x is set, so
# include keeps matching documents and exclude keeps the rest. A cleared mode control acts as include.
function filter([string]$var, [string]$field) {
  @(
    "| WHERE ?$var IS NULL"
    "     OR (COALESCE(?${var}_mode, ""include"") == ""include"")"
    "        == (MV_INTERSECTS(?$var, $field) OR ($field IS NULL AND MV_CONTAINS(?$var, ""__NULL__"")))"
  ) -join "`n"
}
# One command per line; the control-driven filters are wrapped in "// Filter start" / "// Filter end".
$filters = @('FROM any_demo', '// Filter start', (filter 'ie_os' 'os'), (filter 'ie_region' 'region'), (filter 'ie_tags' 'tags'), '// Filter end') -join "`n"
function q([string[]]$tail) { return (@($filters) + $tail) -join "`n" }

function valuesControl([string]$title, [string]$var, [string]$query, [bool]$single) {
  [ordered]@{ type = 'esql_control'; width = 'medium'; grow = $false; config = [ordered]@{
      title = $title; control_type = 'VALUES_FROM_QUERY'; esql_query = $query; variable_name = $var
      variable_type = $(if ($single) { 'values' } else { 'multi_values' }); single_select = $single; selected_options = @() } }
}
function modeControl([string]$title, [string]$var) {
  [ordered]@{ type = 'esql_control'; width = 'small'; grow = $false; config = [ordered]@{
      title = $title; control_type = 'STATIC_VALUES'; available_options = @('include', 'exclude')
      variable_name = "${var}_mode"; variable_type = 'values'; single_select = $true; selected_options = @('include') } }
}

$dashboard = [ordered]@{
  title       = '3. ES|QL controls: Any + include/exclude'
  description = 'OS, Region and Tags with "Any", "(No value)" and a per-filter include/exclude mode (elasticsearch#136735).'
  time_range  = [ordered]@{ from = 'now-7d'; to = 'now' }
  pinned_panels = @(
    (valuesControl 'OS' 'ie_os' 'FROM any_demo | STATS BY os | EVAL os = COALESCE(os, "__NULL__")' $true),
    (modeControl 'OS mode' 'ie_os'),
    (valuesControl 'Region' 'ie_region' 'FROM any_demo | STATS BY region | EVAL region = COALESCE(region, "__NULL__")' $true),
    (modeControl 'Region mode' 'ie_region'),
    (valuesControl 'Tags' 'ie_tags' 'FROM any_demo | MV_EXPAND tags | STATS BY tags | EVAL tags = COALESCE(tags, "__NULL__")' $false),
    (modeControl 'Tags mode' 'ie_tags')
  )
  panels = @(
    [ordered]@{ grid = @{ x = 0; y = 0; w = 12; h = 6 }; type = 'vis'; config = [ordered]@{
        type = 'metric'; title = 'Matching documents'
        data_source = @{ type = 'esql'; query = (q '| STATS docs = COUNT(*)') }
        metrics = @(@{ type = 'primary'; column = 'docs' }) } },
    [ordered]@{ grid = @{ x = 12; y = 0; w = 12; h = 6 }; type = 'vis'; config = [ordered]@{
        type = 'metric'; title = 'Matching documents without tags / OS'
        data_source = @{ type = 'esql'; query = (q '| STATS no_os = COUNT(*) WHERE os IS NULL, no_tags = COUNT(*) WHERE tags IS NULL') }
        metrics = @(@{ type = 'primary'; column = 'no_tags' }, @{ type = 'secondary'; column = 'no_os' }) } },
    [ordered]@{ grid = @{ x = 24; y = 0; w = 24; h = 12 }; type = 'vis'; config = [ordered]@{
        type = 'data_table'; title = 'Documents by tags (multi-valued)'
        data_source = @{ type = 'esql'; query = (q '| EVAL tag_set = COALESCE(MV_CONCAT(MV_SORT(tags), ", "), "(no tags)")', '| STATS docs = COUNT(*) BY tag_set', '| SORT docs DESC') }
        metrics = @(@{ column = 'docs' }); rows = @(@{ column = 'tag_set' }) } },
    [ordered]@{ grid = @{ x = 0; y = 6; w = 24; h = 12 }; type = 'vis'; config = [ordered]@{
        type = 'data_table'; title = 'Documents by OS and region'
        data_source = @{ type = 'esql'; query = (q '| EVAL os = COALESCE(os, "(no os)"), region = COALESCE(region, "(no region)")', '| STATS docs = COUNT(*) BY os, region', '| SORT os, region') }
        metrics = @(@{ column = 'docs' }); rows = @(@{ column = 'os' }, @{ column = 'region' }) } },
    [ordered]@{ grid = @{ x = 0; y = 18; w = 48; h = 12 }; type = 'vis'; config = [ordered]@{
        type = 'xy'; title = 'Documents over time by host'
        layers = @([ordered]@{
            type = 'bar_stacked'
            data_source = @{ type = 'esql'; query = (q '| STATS docs = COUNT(*) BY bucket = BUCKET(@timestamp, 50, ?_tstart, ?_tend), host') }
            x = @{ column = 'bucket' }; y = @(@{ column = 'docs' }); breakdown_by = @{ column = 'host' } }) } }
  )
}

$body = $dashboard | ConvertTo-Json -Depth 30
$headers = @{ 'kbn-xsrf' = 'true'; 'elastic-api-version' = '2023-10-31' }
try {
  if ($Id) {
    Invoke-WebRequest -Method PUT -Uri "$Kibana/api/dashboards/$Id" -Headers $headers -ContentType 'application/json' `
      -Body ([Text.Encoding]::UTF8.GetBytes($body)) -UseBasicParsing | Out-Null
    "Updated dashboard: $Kibana/app/dashboards#/view/$Id"
  } else {
    $r = Invoke-WebRequest -Method POST -Uri "$Kibana/api/dashboards" -Headers $headers -ContentType 'application/json' `
      -Body ([Text.Encoding]::UTF8.GetBytes($body)) -UseBasicParsing
    $newId = ($r.Content | ConvertFrom-Json).id
    "Created dashboard: $Kibana/app/dashboards#/view/$newId"
  }
} catch {
  "HTTP error: " + $(if ($_.ErrorDetails) { $_.ErrorDetails.Message } else { $_.Exception.Message })
}
