# 同步三个仓库：当前目录（框架主仓库）、demo 项目、assets 资源仓库
$root = $PSScriptRoot
$repos = @(
    $root,
    (Join-Path $root 'projects\demo'),
    (Join-Path $root 'vendor\assets')
)

$failed = @()
foreach ($repo in $repos) {
    Write-Host "==== 同步 $repo ====" -ForegroundColor Cyan
    if (-not (Test-Path (Join-Path $repo '.git'))) {
        Write-Host "跳过：不是 git 仓库" -ForegroundColor Yellow
        $failed += $repo
        continue
    }

    git -C $repo pull
    if ($LASTEXITCODE -ne 0) {
        Write-Host "失败：$repo" -ForegroundColor Red
        $failed += $repo
    }
    else {
        Write-Host "完成：$repo" -ForegroundColor Green
    }
}

if ($failed.Count -gt 0) {
    Write-Host "`n以下仓库同步失败：`n$($failed -join "`n")" -ForegroundColor Red
    exit 1
}

Write-Host "`n全部同步完成" -ForegroundColor Green
