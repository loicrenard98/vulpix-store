<#
.SYNOPSIS
    Vérifie les projets de la boutique Vulpix et génère catalog.json.

    Mode normal (après acceptation, sur la branche main) :
        pwsh tools/build-catalog.ps1                     -> réécrit catalog.json

    Mode vérification (pour chaque proposition / pull request) :
        pwsh tools/build-catalog.ps1 -Validate -Root ./pr -BaseRoot ./base `
             -PrAuthor alice -Owner bob -ChangedFiles @('projects/x/manifest.json', ...)

    Ce script lit seulement des fichiers (JSON, zip, png) : il n'exécute jamais le code des projets.
#>
param(
    [string]$Root = (Split-Path $PSScriptRoot -Parent),
    [switch]$Validate,
    [string]$BaseRoot = '',
    [string]$PrAuthor = '',
    [string]$Owner = '',
    [string[]]$ChangedFiles = @()
)

$ErrorActionPreference = 'Stop'
$MaxPackage = 10MB
$MaxIcon = 512KB
$IdPattern = '^[a-z0-9](?:[a-z0-9-]{0,48}[a-z0-9])?$'
$Types = @('Empty', 'Script', 'Interface', 'Blocks')

$errors = [System.Collections.Generic.List[string]]::new()
function Fail([string]$message) { $script:errors.Add($message) }

function Read-Manifest([string]$path) {
    try { return Get-Content $path -Raw -Encoding utf8 | ConvertFrom-Json }
    catch { return $null }
}

function Parse-Version([string]$text) {
    if ($text -match '^(\d+)\.(\d+)\.(\d+)$') { return [version]"$($Matches[1]).$($Matches[2]).$($Matches[3])" }
    return $null
}

# ----- Vérification de chaque projet -------------------------------------------
$entries = @()
$projectsDir = Join-Path $Root 'projects'

if (Test-Path $projectsDir) {
    foreach ($dir in Get-ChildItem $projectsDir -Directory | Sort-Object Name) {
        $id = $dir.Name
        $manifestPath = Join-Path $dir.FullName 'manifest.json'

        if (-not (Test-Path $manifestPath)) { Fail "$id : manifest.json manquant"; continue }
        $m = Read-Manifest $manifestPath
        if (-not $m) { Fail "$id : manifest.json n'est pas un JSON valide"; continue }

        if ($id -notmatch $IdPattern) { Fail "$id : nom de dossier invalide (minuscules, chiffres et tirets)" }
        if ($m.id -ne $id) { Fail "$id : « id » doit être identique au nom du dossier" }
        if (-not $m.name -or $m.name.Length -lt 3 -or $m.name.Length -gt 60) { Fail "$id : « name » doit faire 3 à 60 caractères" }
        if (-not $m.description -or $m.description.Length -lt 20) { Fail "$id : « description » doit faire au moins 20 caractères" }
        if (-not $m.author) { Fail "$id : « author » manquant" }
        if ($Types -notcontains $m.type) { Fail "$id : « type » doit être $($Types -join ', ')" }
        if (-not (Parse-Version $m.version)) { Fail "$id : « version » doit être au format 1.2.3" }

        # 🔒 Projets payants pas encore ouverts.
        if ([decimal]$m.price -ne 0) { Fail "$id : les projets payants ne sont pas encore acceptés (price doit valoir 0)" }

        # Archive du projet
        $expectedPrefix = "projects/$id/"
        if (-not $m.package -or -not $m.package.StartsWith($expectedPrefix) -or -not $m.package.EndsWith('.zip')) {
            Fail "$id : « package » doit être un .zip dans $expectedPrefix"
        }
        else {
            $zipPath = Join-Path $Root $m.package
            if (-not (Test-Path $zipPath)) { Fail "$id : archive $($m.package) introuvable" }
            else {
                $zip = Get-Item $zipPath
                if ($zip.Length -gt $MaxPackage) { Fail "$id : archive trop lourde (10 Mo maximum)" }
                if ([long]$m.size -ne $zip.Length) { Fail "$id : « size » ne correspond pas à l'archive" }
                $hash = (Get-FileHash $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
                if ("$($m.sha256)".ToLowerInvariant() -ne $hash) { Fail "$id : « sha256 » ne correspond pas à l'archive" }

                # L'archive doit contenir un projet Vulpix.
                try {
                    Add-Type -AssemblyName System.IO.Compression.FileSystem
                    $archive = [IO.Compression.ZipFile]::OpenRead($zipPath)
                    $names = $archive.Entries | ForEach-Object FullName
                    $archive.Dispose()
                    if (-not ($names | Where-Object { $_ -like '*.vulpix' })) { Fail "$id : l'archive ne contient pas de fichier .vulpix" }
                    if ($names | Where-Object { $_ -match '(^|/)\.\.(/|$)' -or $_.StartsWith('/') }) { Fail "$id : l'archive contient des chemins interdits" }
                }
                catch { Fail "$id : archive illisible" }
            }
        }

        # Icône (facultative)
        if ($m.iconFile) {
            if ($m.iconFile -ne "projects/$id/icon.png") { Fail "$id : « iconFile » doit être projects/$id/icon.png" }
            elseif (-not (Test-Path (Join-Path $Root $m.iconFile))) { Fail "$id : icône introuvable" }
            elseif ((Get-Item (Join-Path $Root $m.iconFile)).Length -gt $MaxIcon) { Fail "$id : icône trop lourde (512 Ko maximum)" }
        }

        $entries += $m
    }
}

# ----- Règles propres aux propositions (pull requests) ------------------------------
if ($Validate -and $PrAuthor) {
    $isOwner = $Owner -and ($PrAuthor -ieq $Owner)

    foreach ($file in $ChangedFiles) {
        if (-not $file.StartsWith('projects/')) {
            if (-not $isOwner) { Fail "Seul le dossier projects/ peut être modifié par une proposition ($file)" }
            continue
        }

        $id = $file.Split('/')[1]
        $manifest = Join-Path $Root "projects/$id/manifest.json"
        $new = if (Test-Path $manifest) { Read-Manifest $manifest } else { $null }
        $oldPath = if ($BaseRoot) { Join-Path $BaseRoot "projects/$id/manifest.json" } else { '' }
        $old = if ($oldPath -and (Test-Path $oldPath)) { Read-Manifest $oldPath } else { $null }

        if ($isOwner) { continue } # le propriétaire de la boutique peut tout corriger

        # Un projet n'appartient qu'à son auteur.
        if ($old -and $old.author -ine $PrAuthor) { Fail "$id : ce projet appartient à $($old.author)" }
        if ($new -and $new.author -ine $PrAuthor) { Fail "$id : « author » doit être ton nom GitHub ($PrAuthor)" }

        # Une mise à jour augmente toujours le numéro de version.
        if ($old -and $new) {
            $oldVersion = Parse-Version $old.version
            $newVersion = Parse-Version $new.version
            if ($oldVersion -and $newVersion -and $newVersion -le $oldVersion -and $file -like '*/manifest.json') {
                Fail "$id : la version doit être supérieure à $($old.version)"
            }
        }
    }
}

# ----- Résultat ----------------------------------------------------------------
if ($errors.Count -gt 0) {
    Write-Host "❌ $($errors.Count) problème(s) :" -ForegroundColor Red
    $errors | Sort-Object -Unique | ForEach-Object { Write-Host "  - $_" }
    exit 1
}

Write-Host "✅ $($entries.Count) projet(s) valide(s)." -ForegroundColor Green

if (-not $Validate) {
    $catalog = [ordered]@{
        formatVersion = 1
        generated     = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
        projects      = @($entries | Sort-Object name)
    }
    $json = $catalog | ConvertTo-Json -Depth 8
    [IO.File]::WriteAllText((Join-Path $Root 'catalog.json'), $json + "`n", (New-Object Text.UTF8Encoding($false)))
    Write-Host "catalog.json mis à jour."
}
