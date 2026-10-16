# Creates "5. Native DSL controls": stock options-list controls (Kibana's own "Any" placeholder and Include/Exclude
# toggle) over regular data-view (DSL) Lens panels on any_demo.
param([string]$Kibana = 'http://localhost:5601', [string]$Id = $null, [string]$DataViewId)

$source = [ordered]@{ type = 'data_view_reference'; ref_id = $DataViewId }
function control([string]$title, [string]$field, [bool]$single) {
  [ordered]@{ type = 'options_list_control'; width = 'medium'; grow = $false; config = [ordered]@{
      title = $title; data_view_id = $DataViewId; field_name = $field
      exclude = $false; exists_selected = $false; selected_options = @(); single_select = $single } }
}
function termsTable([int]$x, [int]$y, [int]$w, [int]$h, [string]$title, [string]$field) {
  [ordered]@{ grid = @{ x = $x; y = $y; w = $w; h = $h }; type = 'vis'; config = [ordered]@{
      type = 'data_table'; title = $title; data_source = $source
      metrics = @(@{ operation = 'count' })
      rows = @(@{ operation = 'terms'; fields = @($field); limit = 20 }) } }
}

$dashboard = [ordered]@{
  title = '5. Native DSL controls'
  description = 'Stock options-list controls (Any placeholder, Include/Exclude, Exists) over data-view Lens panels.'
  time_range = [ordered]@{ from = 'now-7d'; to = 'now' }
  pinned_panels = @(
    (control 'OS' 'os' $true),
    (control 'Region' 'region' $false),
    (control 'Tags' 'tags' $false)
  )
  panels = @(
    [ordered]@{ grid = @{ x = 0; y = 0; w = 12; h = 6 }; type = 'vis'; config = [ordered]@{
        type = 'metric'; title = 'Matching documents'; data_source = $source
        metrics = @(@{ type = 'primary'; operation = 'count' }) } },
    (termsTable 12 0 12 12 'Documents by OS' 'os'),
    (termsTable 24 0 12 12 'Documents by region' 'region'),
    (termsTable 36 0 12 12 'Documents by tags' 'tags')
  )
}

$body = $dashboard | ConvertTo-Json -Depth 30
$headers = @{ 'kbn-xsrf' = 'true'; 'elastic-api-version' = '2023-10-31' }
if ($env:ES_CLOUD_API_KEY -and $Kibana -notmatch 'localhost|127\.0\.0\.1') {
  $headers['Authorization'] = "ApiKey $($env:ES_CLOUD_API_KEY)"
}
try {
  if ($Id) {
    Invoke-WebRequest -Method PUT -Uri "$Kibana/api/dashboards/$Id" -Headers $headers -ContentType 'application/json' `
      -Body ([Text.Encoding]::UTF8.GetBytes($body)) -UseBasicParsing | Out-Null
    "Updated dashboard id=$Id"
  } else {
    $r = Invoke-WebRequest -Method POST -Uri "$Kibana/api/dashboards" -Headers $headers -ContentType 'application/json' `
      -Body ([Text.Encoding]::UTF8.GetBytes($body)) -UseBasicParsing
    "Created dashboard id=$(($r.Content | ConvertFrom-Json).id)"
  }
} catch {
  "HTTP error: " + $(if ($_.ErrorDetails) { $_.ErrorDetails.Message } else { $_.Exception.Message })
}
