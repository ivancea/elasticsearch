# Creates the "ES|QL controls: Any" demo dashboard through the Kibana Dashboards API.
param([string]$Kibana = 'http://localhost:5601', [string]$Id = $null)

# Filter block shared by every panel.
#  - ?os, ?region: single-select, "Any" when cleared (option D). MV_INTERSECTS rather than `==` so that
#    multi-valued documents match on any value, like classic controls.
#  - ?tags: multi-select with "Any", plus ?tags_blank (include docs without tags), i.e. option D+ with a flag.
#    COALESCE keeps the helper control safe if it is cleared too.
$filters = @'
FROM any_demo
// Filter start
| WHERE ?os IS NULL OR MV_INTERSECTS(?os, os)
| WHERE ?region IS NULL OR MV_INTERSECTS(?region, region)
| WHERE (?tags IS NULL AND COALESCE(?tags_blank, "false") != "true")
     OR (COALESCE(?tags_blank, "false") == "true" AND tags IS NULL)
     OR MV_INTERSECTS(?tags, tags)
// Filter end
'@.Trim()

# One command per line: pass each command of the tail as a separate argument.
function q([string[]]$tail) { return (@($filters) + $tail) -join "`n" }

$dashboard = [ordered]@{
  title       = '(Old) ES|QL controls: Any'
  description = 'Demo of "Any" in ES|QL controls (elasticsearch#136735): clear a control to stop filtering.'
  time_range  = [ordered]@{ from = 'now-7d'; to = 'now' }
  pinned_panels = @(
    [ordered]@{ type = 'esql_control'; width = 'medium'; grow = $false; config = [ordered]@{
        title = 'OS'; control_type = 'VALUES_FROM_QUERY'; esql_query = 'FROM any_demo | STATS BY os'
        variable_name = 'os'; variable_type = 'values'; single_select = $true; selected_options = @() } },
    [ordered]@{ type = 'esql_control'; width = 'medium'; grow = $false; config = [ordered]@{
        title = 'Region'; control_type = 'VALUES_FROM_QUERY'; esql_query = 'FROM any_demo | STATS BY region'
        variable_name = 'region'; variable_type = 'values'; single_select = $true; selected_options = @() } },
    [ordered]@{ type = 'esql_control'; width = 'medium'; grow = $false; config = [ordered]@{
        title = 'Tags'; control_type = 'VALUES_FROM_QUERY'; esql_query = 'FROM any_demo | MV_EXPAND tags | STATS BY tags'
        variable_name = 'tags'; variable_type = 'multi_values'; single_select = $false; selected_options = @() } },
    [ordered]@{ type = 'esql_control'; width = 'small'; grow = $false; config = [ordered]@{
        title = 'Docs without tags'; control_type = 'STATIC_VALUES'; available_options = @('false', 'true')
        variable_name = 'tags_blank'; variable_type = 'values'; single_select = $true; selected_options = @('false') } }
  )
  panels = @(
    [ordered]@{ grid = @{ x = 0; y = 0; w = 12; h = 6 }; type = 'vis'; config = [ordered]@{
        type = 'metric'; title = 'Matching documents'
        data_source = @{ type = 'esql'; query = (q '| STATS docs = COUNT(*)') }
        metrics = @(@{ type = 'primary'; column = 'docs' }) } },
    [ordered]@{ grid = @{ x = 12; y = 0; w = 12; h = 6 }; type = 'vis'; config = [ordered]@{
        type = 'metric'; title = 'Matching documents without OS / region / tags'
        data_source = @{ type = 'esql'; query = (q '| STATS no_os = COUNT(*) WHERE os IS NULL, no_region = COUNT(*) WHERE region IS NULL, no_tags = COUNT(*) WHERE tags IS NULL') }
        metrics = @(
          @{ type = 'primary'; column = 'no_tags' },
          @{ type = 'secondary'; column = 'no_os' }
        ) } },
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
