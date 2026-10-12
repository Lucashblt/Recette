$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add('http://localhost:8000/')
$listener.Start()
Write-Host 'Maison Mijotee : http://localhost:8000'

function Send-Response($context, $body, $contentType, $statusCode = 200) {
  $bytes = [System.Text.Encoding]::UTF8.GetBytes($body)
  $context.Response.StatusCode = $statusCode
  $context.Response.ContentType = $contentType
  $context.Response.ContentLength64 = $bytes.Length
  $context.Response.OutputStream.Write($bytes, 0, $bytes.Length)
  $context.Response.Close()
}

while ($listener.IsListening) {
  $context = $listener.GetContext()
  try {
    $path = $context.Request.Url.AbsolutePath
    if ($path -eq '/api/data' -and $context.Request.HttpMethod -eq 'GET') {
      try { $recipes = Get-Content (Join-Path $root 'recipes.json') -Raw -Encoding UTF8 | ConvertFrom-Json } catch { $recipes = @{ recipes = @() } }
      $ingredients = Get-Content (Join-Path $root 'ingredients.json') -Raw -Encoding UTF8 | ConvertFrom-Json
      $fridge = Get-Content (Join-Path $root 'fridge.json') -Raw -Encoding UTF8 | ConvertFrom-Json
      Send-Response $context ((@{ recipes = @($recipes.recipes); ingredients = $ingredients.categories; fridge = @($fridge.items) } | ConvertTo-Json -Depth 20)) 'application/json; charset=utf-8'
      continue
    }
    if ($path -eq '/api/data' -and $context.Request.HttpMethod -eq 'POST') {
      $reader = New-Object System.IO.StreamReader($context.Request.InputStream, [System.Text.Encoding]::UTF8)
      $payload = $reader.ReadToEnd() | ConvertFrom-Json
      if ($null -ne $payload.recipes) {
        @{ version = 1; description = 'Catalogue des recettes de Maison Mijotee.'; recipes = @($payload.recipes) } | ConvertTo-Json -Depth 20 | Set-Content (Join-Path $root 'recipes.json') -Encoding UTF8
      }
      if ($null -ne $payload.ingredients) {
        @{ categories = $payload.ingredients } | ConvertTo-Json -Depth 20 | Set-Content (Join-Path $root 'ingredients.json') -Encoding UTF8
      }
      if ($null -ne $payload.fridge) {
        @{ items = @($payload.fridge) } | ConvertTo-Json -Depth 20 | Set-Content (Join-Path $root 'fridge.json') -Encoding UTF8
      }
      Send-Response $context '{"ok":true}' 'application/json; charset=utf-8'
      continue
    }
    $relative = if ($path -eq '/') { 'index.html' } else { $path.TrimStart('/') }
    $file = Join-Path $root $relative
    if (Test-Path $file -PathType Leaf) {
      $extension = [IO.Path]::GetExtension($file).ToLowerInvariant()
      $types = @{ '.html'='text/html'; '.js'='text/javascript'; '.css'='text/css'; '.json'='application/json'; '.svg'='image/svg+xml' }
      $type = if ($types.ContainsKey($extension)) { $types[$extension] } else { 'application/octet-stream' }
      $bytes = [IO.File]::ReadAllBytes($file)
      $context.Response.ContentType = "$type; charset=utf-8"
      $context.Response.ContentLength64 = $bytes.Length
      $context.Response.OutputStream.Write($bytes, 0, $bytes.Length)
      $context.Response.Close()
    } else { Send-Response $context 'Not found' 'text/plain' 404 }
  } catch {
    Send-Response $context $_.Exception.Message 'text/plain' 500
  }
}
