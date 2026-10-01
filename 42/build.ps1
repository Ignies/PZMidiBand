# build.ps1 - Compile PZMidiBridge.java into a JAR placed at 42/java/PZMidiBridge.jar.
#
# Requires: a JDK on PATH (`javac`, `jar`). The game ships a JRE only, so the
# user must install JDK 17+ themselves (Adoptium / Microsoft Build of OpenJDK).
#
# This script generates a tiny stub of the @me.zed_0xff.zombie_buddy.Exposer.LuaClass
# annotation so we can compile WITHOUT the ZombieBuddy jar present. The stub is
# kept out of the final jar; at runtime the real annotation supplied by the
# installed ZombieBuddy mod is used.

param(
    [string]$Root = (Split-Path -Parent $PSCommandPath)  # 42/ folder
)

$ErrorActionPreference = 'Stop'

$srcDir   = Join-Path $Root 'java\src'
$stubDir  = Join-Path $Root 'java\stub-src'
$stubOut  = Join-Path $Root 'java\stub-build'
$outDir   = Join-Path $Root 'java\build'
$jarOut   = Join-Path $Root 'java\PZMidiBridge.jar'

if (-not (Test-Path $srcDir)) { throw "Source dir not found: $srcDir" }

foreach ($d in @($stubDir, $stubOut, $outDir)) {
    if (Test-Path $d) { Remove-Item $d -Recurse -Force }
    New-Item -ItemType Directory -Path $d -Force | Out-Null
}

# Generate stub annotation source (compile-time only, never packaged)
$stubPkgDir = Join-Path $stubDir 'me\zed_0xff\zombie_buddy'
New-Item -ItemType Directory -Path $stubPkgDir -Force | Out-Null
@'
package me.zed_0xff.zombie_buddy;

import java.lang.annotation.ElementType;
import java.lang.annotation.Retention;
import java.lang.annotation.RetentionPolicy;
import java.lang.annotation.Target;

/** Compile-time stub - the real annotation ships with the ZombieBuddy mod. */
public final class Exposer {
    private Exposer() {}
    @Retention(RetentionPolicy.RUNTIME)
    @Target(ElementType.TYPE)
    public @interface LuaClass {}
}
'@ | ForEach-Object {
    [System.IO.File]::WriteAllText((Join-Path $stubPkgDir 'Exposer.java'), $_, [System.Text.UTF8Encoding]::new($false))
}

Write-Host "Compiling stub..."
& javac -d $stubOut (Join-Path $stubPkgDir 'Exposer.java')
if ($LASTEXITCODE -ne 0) { throw "stub compile failed" }

Write-Host "Compiling mod sources..."
$javaFiles = Get-ChildItem -Recurse -Path $srcDir -Filter *.java | ForEach-Object { $_.FullName }
if (-not $javaFiles) { throw "No .java files under $srcDir" }
& javac --release 17 -cp $stubOut -d $outDir $javaFiles
if ($LASTEXITCODE -ne 0) { throw "javac failed" }

Write-Host "Packaging JAR..."
if (Test-Path $jarOut) { Remove-Item $jarOut -Force }
Push-Location $outDir
try {
    $entries = Get-ChildItem -Recurse -File | ForEach-Object { $_.FullName.Substring($outDir.Length + 1) }
    & jar cf $jarOut $entries
    if ($LASTEXITCODE -ne 0) { throw "jar failed" }
} finally { Pop-Location }

Remove-Item $outDir, $stubOut, $stubDir -Recurse -Force
Write-Host "OK -> $jarOut"
