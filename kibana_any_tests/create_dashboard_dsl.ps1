# Creates "4. DSL controls: include, exclude, exists" on a Kibana that already has the any_demo data view.
# Stock options-list controls. Include is the default, Exclude negates the selection, Exists means the field
# is present. There is no "(No value)" option that can be combined with real values.
param([string]$Kibana = 'http://localhost:5601', [string]$Id = $null, [string]$DataViewId)

function control([string]$title, [string]$field, [bool]$single) {
  [ordered]@{
    type = 'options_list_control'; width = 'medium'; grow = $false
    config = [ordered]@{
      title = $title
      data_view_id = $DataViewId
      field_name = $field
      exclude = $false
      exists_selected = $false
      selected_options = @()
      single_select = $single
    }
  }
}
function table([int]$x, [int]$y, [int]$w, [int]$h, [string]$title, [string]$field) {
  [ordered]@{ grid = @{ x = $x; y = $y; w = $w; h = $h }; type = 'vis'; config = [ordered]@{
      type = 'data_table'; title = $title
      data_source = @{ type = 'data_view_spec'; index_pattern = 'any_demo'; time_field = '@timestamp' }
      metrics = @(@{ operation = 'count' })
      rows = @(@{ operation = 'terms'; fields = @($field); limit = 20 }) } }
}

$dashboard = [ordered]@{
  title = '4. DSL controls: include, exclude, exists'
  description = 'Stock 9.5.1 options-list controls on any_demo. Include and Exclude are in each control. Exists means the field is present and cannot be combined with values. There is no (No value) option; missing documents are only Exclude + Exists.'
  time_range = [ordered]@{ from = 'now-7d'; to = 'now' }
  pinned_panels = @(
    (control 'OS' 'os' $false),
    (control 'Region' 'region' $false),
    (control 'Tags' 'tags' $false),
    (control 'Status' 'status' $false)
  )
  panels = @(
    [ordered]@{ grid = @{ x = 0; y = 0; w = 12; h = 6 }; type = 'vis'; config = [ordered]@{
        type = 'metric'; title = 'Matching documents'
        data_source = @{ type = 'data_view_spec'; index_pattern = 'any_demo'; time_field = '@timestamp' }
        metrics = @(@{ type = 'primary'; operation = 'count' }) } },
    (table 12 0 36 10 'Documents by OS' 'os'),
    (table 0 10 16 12 'Documents by region' 'region'),
    (table 16 10 16 12 'Documents by tags' 'tags'),
    (table 32 10 16 12 'Documents by status' 'status')
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
    $newId = ($r.Content | ConvertFrom-Json).id
    "Created dashboard id=$newId"
  }
} catch {
  "HTTP error: " + $(if ($_.ErrorDetails) { $_.ErrorDetails.Message } else { $_.Exception.Message })
}
