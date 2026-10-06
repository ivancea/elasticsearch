function es([string]$method, [string]$path, $body = $null, [string]$contentType = 'application/json') {
  $h = $env:ES_CLOUD_HOST.TrimEnd('/'); if ($h -notmatch '^https?://') { $h = "https://$h" }
  $headers = @{ Authorization = "ApiKey $($env:ES_CLOUD_API_KEY)"; 'Content-Type' = $contentType }
  $json = if ($body -is [string]) { $body } elseif ($body) { $body | ConvertTo-Json -Depth 20 -Compress } else { $null }
  try {
    [byte[]]$bytes = $null
    if ($json) { $bytes = [Text.Encoding]::UTF8.GetBytes($json) }
    $r = Invoke-WebRequest -Method $method -Uri "$h$path" -Headers $headers -Body $bytes -UseBasicParsing
    return $r.Content
  } catch {
    $resp = $_.Exception.Response
    $code = if ($resp) { [int]$resp.StatusCode } else { 0 }
    $detail = if ($_.ErrorDetails -and $_.ErrorDetails.Message) { $_.ErrorDetails.Message } else { $_.Exception.Message }
    return "HTTP ${code}: $detail"
  }
}

# Runs an ES|QL query. $params is a JSON string for the "params" array, e.g. '[{"host": null}]'.
function esql([string]$query, [string]$params = $null, [switch]$profile) {
  $b = '{"query":' + ($query | ConvertTo-Json -Compress)
  if ($params) { $b += ',"params":' + $params }
  if ($profile) { $b += ',"profile":true' }
  $b += '}'
  if ($profile) { return es POST '/_query' $b }
  return es POST '/_query?format=txt' $b
}

# Prints a labelled query result.
function t([string]$label, [string]$query, [string]$params = $null) {
  Write-Output "=== $label  params=$params"
  Write-Output (esql $query $params)
}
