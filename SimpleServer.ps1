$Folder = "public"
$Port = 8080

$Listener = New-Object System.Net.HttpListener
$Listener.Prefixes.Add("http://localhost:$Port/")
$Listener.Start()

Write-Host "Server started at http://localhost:$Port/"
Write-Host "Press Ctrl+C to stop the server"

try {
    while ($Listener.IsListening) {
        $Context = $Listener.GetContext()
        $Request = $Context.Request
        $Response = $Context.Response

        $RequestUrl = $Request.Url.LocalPath
        $PhysicalPath = Join-Path $PWD $Folder

        if ($RequestUrl -eq "/") {
            $RequestUrl = "/index.html"
        }

        $FilePath = Join-Path $PhysicalPath $RequestUrl.TrimStart("/")

        Write-Host "Requested: $RequestUrl"

        if (Test-Path $FilePath -PathType Leaf) {
            $Content = Get-Content $FilePath -Raw -Encoding Byte
            $Response.ContentType = switch ($FilePath.Split(".")[-1]) {
                "html" { "text/html" }
                "css"  { "text/css" }
                "js"   { "application/javascript" }
                "json" { "application/json" }
                "png"  { "image/png" }
                "jpg"  { "image/jpeg" }
                "jpeg" { "image/jpeg" }
                "svg"  { "image/svg+xml" }
                default { "application/octet-stream" }
            }
            $Response.ContentLength64 = $Content.Length
            $Response.OutputStream.Write($Content, 0, $Content.Length)
        } else {
            $Response.StatusCode = 404
            $NotFoundMessage = "404 - File not found: $RequestUrl"
            $Response.ContentType = "text/plain"
            $Response.ContentLength64 = $NotFoundMessage.Length
            $Response.OutputStream.Write([System.Text.Encoding]::ASCII.GetBytes($NotFoundMessage), 0, $NotFoundMessage.Length)
        }

        $Response.OutputStream.Close()
    }
} finally {
    $Listener.Stop()
} 