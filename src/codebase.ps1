# codebase.ps1 - Deep codebase intelligence: project type detection, map building, file routing

function Detect-ProjectType {
    $hasPackageJson  = Test-Path (Join-Path $cbPath 'package.json')
    $hasRequirements = Test-Path (Join-Path $cbPath 'requirements.txt')
    $hasPomXml       = Test-Path (Join-Path $cbPath 'pom.xml')
    $hasCargoToml    = Test-Path (Join-Path $cbPath 'Cargo.toml')
    $hasGoMod        = Test-Path (Join-Path $cbPath 'go.mod')
    $hasViteConfig   = (Test-Path (Join-Path $cbPath 'vite.config.ts')) -or (Test-Path (Join-Path $cbPath 'vite.config.js'))
    $hasNextConfig   = (Test-Path (Join-Path $cbPath 'next.config.js')) -or (Test-Path (Join-Path $cbPath 'next.config.ts'))
    $hasManagePy     = Test-Path (Join-Path $cbPath 'manage.py')

    $type = 'unknown'

    if ($hasPackageJson) {
        $pkg = Get-Content (Join-Path $cbPath 'package.json') -Raw -EA SilentlyContinue | ConvertFrom-Json -EA SilentlyContinue
        $deps = @()
        if ($pkg -and $pkg.dependencies)    { $deps += $pkg.dependencies.PSObject.Properties.Name }
        if ($pkg -and $pkg.devDependencies) { $deps += $pkg.devDependencies.PSObject.Properties.Name }

        if ($hasViteConfig)                    { $type = 'vite-react' }
        elseif ($hasNextConfig)                { $type = 'nextjs' }
        elseif ($deps -contains 'react')       { $type = 'react' }
        elseif ($deps -contains 'express')     { $type = 'express' }
        elseif ($deps -contains 'vue')         { $type = 'vue' }
        elseif ($deps -contains '@angular/core') { $type = 'angular' }
        elseif ($deps -contains 'svelte')      { $type = 'svelte' }
        else                                   { $type = 'nodejs' }

        # Detect full-stack: frontend framework + server code present
        $hasBackendDir = Test-Path (Join-Path $cbPath 'backend')
        $hasServerFile = (Test-Path (Join-Path $cbPath 'server.js')) -or (Test-Path (Join-Path $cbPath 'server.ts')) -or (Test-Path (Join-Path $cbPath 'src/server.js'))
        if (($hasBackendDir -or $hasServerFile) -and $type -match 'vite|react|vue|next|angular|svelte') {
            $type = "fullstack-$type"
        }
    }
    elseif ($hasRequirements) {
        if ($hasManagePy) { $type = 'django' }
        else {
            $reqs = Get-Content (Join-Path $cbPath 'requirements.txt') -Raw -EA SilentlyContinue
            if ($reqs -match 'fastapi') { $type = 'fastapi' }
            elseif ($reqs -match 'flask') { $type = 'flask' }
            else { $type = 'python' }
        }
    }
    elseif ($hasPomXml)    { $type = 'java-maven' }
    elseif ($hasCargoToml) { $type = 'rust' }
    elseif ($hasGoMod)     { $type = 'golang' }

    return $type
}

function Get-BackendFolder {
    param([string]$ProjectType)
    if ($ProjectType -notmatch 'vite|react|vue|nextjs|angular|svelte') { return '' }
    # Check existing backend folder names in priority order
    foreach ($candidate in @('backend', 'server', 'api', 'express')) {
        if (Test-Path (Join-Path $cbPath $candidate)) { return $candidate }
    }
    # Default: use 'backend' folder to keep Express code separate from Vite's src/
    return 'backend'
}

function Build-CodebaseMap {
    # -- INCREMENTAL SCANNING (CACHE) --
    $cacheDir = Get-AgentMemoryDir
    if (-not (Test-Path $cacheDir)) { New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null }
    $cacheFile = Join-Path $cacheDir 'codebasemap-cache.json'
    
    $hashInput = $script:fileListText
    # Also hash timestamps of key files to detect modifications
    $keyFiles = @('package.json', 'vite.config.ts', 'next.config.js') + 
                ($script:relFiles | Where-Object { $_ -match 'App\.(tsx|jsx|ts|js)$|[Rr]outer\.(tsx|jsx|ts|js)$|\.(tsx|jsx)$|[Rr]outes?[/\\]|[Cc]ontrollers?[/\\]|api[/\\]' })
    foreach ($f in $keyFiles) {
        $abs = Join-Path $cbPath $f
        if (Test-Path $abs) { $hashInput += "$($f):" + (Get-Item $abs).LastWriteTime.Ticks }
    }
    
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($hashInput)
    $hashAlgorithm = [System.Security.Cryptography.SHA256]::Create()
    $currentHash = [System.BitConverter]::ToString($hashAlgorithm.ComputeHash($bytes)).Replace('-','')

    if (Test-Path $cacheFile) {
        $cached = Get-Content $cacheFile -Raw -EA SilentlyContinue | ConvertFrom-Json -EA SilentlyContinue
        if ($cached -and $cached.hash -eq $currentHash) {
            return $cached.map
        }
    }
    $map = @{
        project_type         = Detect-ProjectType
        has_backend          = $false
        backend_folder       = ''
        entry_point          = ''
        router               = ''
        css_framework        = ''
        state_management     = ''
        test_framework       = ''
        build_cmd            = ''
        existing_routes      = @()
        existing_components  = @()
        existing_api_endpoints = @()
        installed_packages   = @()
        last_updated         = (Get-Date -Format 'yyyy-MM-dd')
    }

    $map.backend_folder = Get-BackendFolder -ProjectType $map.project_type
    $map.has_backend    = ($map.backend_folder -ne '')

    # Read package.json
    $pkgPath = Join-Path $cbPath 'package.json'
    if (Test-Path $pkgPath) {
        try {
            $pkg  = Get-Content $pkgPath -Raw | ConvertFrom-Json
            $deps = @()
            if ($pkg.dependencies)    { $deps += $pkg.dependencies.PSObject.Properties.Name }
            if ($pkg.devDependencies) { $deps += $pkg.devDependencies.PSObject.Properties.Name }
            $map.installed_packages = $deps

            if ($deps -contains 'tailwindcss')      { $map.css_framework    = 'tailwindcss' }
            elseif ($deps -contains 'styled-components') { $map.css_framework = 'styled-components' }
            if ($deps -contains 'react-router-dom') { $map.router           = 'react-router-dom' }
            elseif ($deps -contains 'react-router') { $map.router           = 'react-router' }
            if ($deps -contains 'zustand')          { $map.state_management = 'zustand' }
            elseif ($deps -contains 'redux')        { $map.state_management = 'redux' }
            if ($deps -contains 'jest')             { $map.test_framework   = 'jest' }
            elseif ($deps -contains 'vitest')       { $map.test_framework   = 'vitest' }
            elseif ($deps -contains 'mocha')        { $map.test_framework   = 'mocha' }

            if ($pkg.scripts -and $pkg.scripts.build) { $map.build_cmd = 'npm run build' }
        } catch {}
    }

    # Entry point detection
    foreach ($ep in @('src/main.tsx','src/index.tsx','src/main.ts','src/index.ts','src/index.js','src/main.js','index.js','app.py','main.py','manage.py')) {
        if (Test-Path (Join-Path $cbPath $ep)) { $map.entry_point = $ep; break }
    }

    # Extract existing React routes from App.tsx / router files
    $routerFiles = $script:relFiles | Where-Object { $_ -match 'App\.(tsx|jsx|ts|js)$|[Rr]outer\.(tsx|jsx|ts|js)$' }
    foreach ($rf in $routerFiles | Select-Object -First 2) {
        $abs = Join-Path $cbPath $rf
        if (Test-Path $abs) {
            $content = Get-Content $abs -Raw -EA SilentlyContinue
            $ms = [regex]::Matches($content, 'path=["\x27]([^"\x27]+)["\x27]')
            foreach ($m in $ms) { $map.existing_routes += $m.Groups[1].Value }
        }
    }

    # Extract React component names
    $compFiles = $script:relFiles | Where-Object { $_ -match '\.(tsx|jsx)$' -and $_ -notmatch 'test|spec' }
    foreach ($cf in $compFiles | Select-Object -First 20) {
        $name = [IO.Path]::GetFileNameWithoutExtension($cf)
        if ($name -cmatch '^[A-Z]') { $map.existing_components += $name }
    }

    # Extract existing API endpoints from route files
    $apiFiles = $script:relFiles | Where-Object { $_ -match '[Rr]outes?[/\\]|[Cc]ontrollers?[/\\]|api[/\\]' }
    foreach ($af in $apiFiles | Select-Object -First 5) {
        $abs = Join-Path $cbPath $af
        if (Test-Path $abs) {
            $content = Get-Content $abs -Raw -EA SilentlyContinue
            $ms = [regex]::Matches($content, '\.(get|post|put|delete|patch)\s*\(\s*["\x27]([^"\x27]+)["\x27]')
            foreach ($m in $ms) { $map.existing_api_endpoints += "$($m.Groups[1].Value.ToUpper()) $($m.Groups[2].Value)" }
        }
    }

    $map.existing_routes        = @($map.existing_routes        | Select-Object -Unique)
    $map.existing_components    = @($map.existing_components    | Select-Object -Unique)
    $map.existing_api_endpoints = @($map.existing_api_endpoints | Select-Object -Unique)

    # Save to cache
    @{ hash = $currentHash; map = $map } | ConvertTo-Json -Depth 5 -EA SilentlyContinue | Set-Content $cacheFile -Encoding UTF8

    return $map
}

function Get-CodebaseContext {
    param($CodebaseMap)
    $m   = $CodebaseMap
    $ctx = "CODEBASE INTELLIGENCE:`n"
    $ctx += "  Project Type : $($m.project_type)`n"
    if ($m.entry_point)    { $ctx += "  Entry Point  : $($m.entry_point)`n" }
    if ($m.router)         { $ctx += "  Router       : $($m.router)`n" }
    if ($m.css_framework)  { $ctx += "  CSS          : $($m.css_framework)`n" }
    if ($m.state_management) { $ctx += "  State Mgmt   : $($m.state_management)`n" }
    if ($m.test_framework) { $ctx += "  Tests        : $($m.test_framework)`n" }
    if ($m.backend_folder) { $ctx += "  Backend Dir  : $($m.backend_folder)/ - ALL Express/server-side files MUST go here (not in src/)`n" }
    if ($m.existing_routes -and $m.existing_routes.Count -gt 0)      { $ctx += "  Routes       : $($m.existing_routes -join ', ')`n" }
    if ($m.existing_components -and $m.existing_components.Count -gt 0) { $ctx += "  Components   : $($m.existing_components -join ', ')`n" }
    if ($m.existing_api_endpoints -and $m.existing_api_endpoints.Count -gt 0) { $ctx += "  API Endpoints: $($m.existing_api_endpoints -join ', ')`n" }
    if ($m.installed_packages -and $m.installed_packages.Count -gt 0) { $ctx += "  Installed    : $($m.installed_packages -join ', ')`n" }
    $ctx += "`n"
    return $ctx
}

function Resolve-FileDestination {
    param([string]$FilePath, $CodebaseMap)
    # Returns the corrected file path based on project architecture
    $bf = $CodebaseMap.backend_folder
    $pt = $CodebaseMap.project_type

    # For Vite/React/Vue projects: server-side files MUST NOT be in src/
    if ($pt -match 'vite|react|vue|nextjs|angular' -and $bf) {
        $isServerFile = $FilePath -match '(?i)(server|express|mongoose|sequelize|prisma)\.(js|ts)$' -or
                        $FilePath -match '^src/(routes?|models?|controllers?|middleware|services?|database?)/'
        if ($isServerFile) {
            # Move from src/ to backend/
            $corrected = $FilePath -replace '^src/', "$bf/"
            if ($corrected -ne $FilePath) {
                Write-Host "  |    [ROUTE] $FilePath ? $corrected" -ForegroundColor DarkCyan
                return $corrected
            }
            # Not in src/ but also not in backend/ - put it in backend/
            if ($FilePath -notmatch "^$([regex]::Escape($bf))/") {
                $corrected = "$bf/$FilePath"
                Write-Host "  |    [ROUTE] $FilePath ? $corrected" -ForegroundColor DarkCyan
                return $corrected
            }
        }
    }
    return $FilePath
}
