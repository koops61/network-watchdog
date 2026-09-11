Add-Type -AssemblyName System.Drawing

$SourceJpg = "C:\Users\Fanny\.gemini\antigravity-ide\brain\e79b0635-35a0-4984-8b60-2959993f37d4\network_app_icon_1789138919146.jpg"
$DestIco = "e:\IA-KANIS\outil-web\outil-reseau\src-app\app.ico"
$DestRootIco = "e:\IA-KANIS\outil-web\outil-reseau\app.ico"
$DestPng = "e:\IA-KANIS\outil-web\outil-reseau\src-app\ui\icon.png"
$DestRootPng = "e:\IA-KANIS\outil-web\outil-reseau\ui\icon.png"

$OriginalBmp = [System.Drawing.Bitmap]::FromFile($SourceJpg)

# Sauvegarder en PNG haute résolution pour l'interface UI
$OriginalBmp.Save($DestPng, [System.Drawing.Imaging.ImageFormat]::Png)
if (Test-Path "e:\IA-KANIS\outil-web\outil-reseau\ui") {
    $OriginalBmp.Save($DestRootPng, [System.Drawing.Imaging.ImageFormat]::Png)
}

# Tailles standard pour un icône Windows de haute fidélité
$Sizes = @(256, 128, 64, 48, 32, 16)
$PngStreams = [System.Collections.Generic.List[byte[]]]::new()

foreach ($s in $Sizes) {
    $ResizedBmp = New-Object System.Drawing.Bitmap($s, $s)
    $Graphics = [System.Drawing.Graphics]::FromImage($ResizedBmp)
    $Graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $Graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
    $Graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $Graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality

    $Graphics.DrawImage($OriginalBmp, 0, 0, $s, $s)
    $Graphics.Dispose()

    $Ms = New-Object System.IO.MemoryStream
    $ResizedBmp.Save($Ms, [System.Drawing.Imaging.ImageFormat]::Png)
    $PngStreams.Add($Ms.ToArray())
    $Ms.Dispose()
    $ResizedBmp.Dispose()
}

$OriginalBmp.Dispose()

# Écriture du fichier ICO standard avec conteneurs PNG
$FileStream = [System.IO.File]::Create($DestIco)
$BinaryWriter = New-Object System.IO.BinaryWriter($FileStream)

# Entête ICONDIR (6 octets)
$BinaryWriter.Write([uint16]0)                # Reserved
$BinaryWriter.Write([uint16]1)                # Type 1 = ICO
$BinaryWriter.Write([uint16]$Sizes.Count)     # Nombre d'images

# Calcul des offsets
$CurrentOffset = 6 + ($Sizes.Count * 16)

# Écriture des ICONDIRENTRY (16 octets chacun)
for ($i = 0; $i -lt $Sizes.Count; $i++) {
    $size = $Sizes[$i]
    $data = $PngStreams[$i]

    $w = if ($size -ge 256) { [byte]0 } else { [byte]$size }
    $h = if ($size -ge 256) { [byte]0 } else { [byte]$size }

    $BinaryWriter.Write([byte]$w)             # Width
    $BinaryWriter.Write([byte]$h)             # Height
    $BinaryWriter.Write([byte]0)              # Color count
    $BinaryWriter.Write([byte]0)              # Reserved
    $BinaryWriter.Write([uint16]1)            # Planes
    $BinaryWriter.Write([uint16]32)           # Bit count
    $BinaryWriter.Write([uint32]$data.Length) # Image bytes count
    $BinaryWriter.Write([uint32]$CurrentOffset) # Offset

    $CurrentOffset += $data.Length
}

# Écriture des données d'image PNG
for ($i = 0; $i -lt $Sizes.Count; $i++) {
    $BinaryWriter.Write($PngStreams[$i])
}

$BinaryWriter.Flush()
$BinaryWriter.Close()
$FileStream.Close()

# Copier aussi à la racine
Copy-Item -Path $DestIco -Destination $DestRootIco -Force

Write-Host "Icône généré avec succès : $DestIco et $DestRootIco" -ForegroundColor Green
