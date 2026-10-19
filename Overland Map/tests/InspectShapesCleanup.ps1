param(
    [string]$ManagedDirectory = 'D:\SteamLibrary\steamapps\common\Draw Steel Codex\Codex_Data\Managed',
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'
# Reflection-only loading reads installed code without executing engine methods.
$resolver = [ResolveEventHandler]{ param($sender, $eventArgs)
    $candidate = Join-Path $ManagedDirectory ($eventArgs.Name.Split(',')[0] + '.dll')
    if (Test-Path -LiteralPath $candidate) {
        return [Reflection.Assembly]::ReflectionOnlyLoadFrom($candidate)
    }
    return [Reflection.Assembly]::ReflectionOnlyLoad($eventArgs.Name)
}
[AppDomain]::CurrentDomain.add_ReflectionOnlyAssemblyResolve($resolver)
try {
    $opcodes = @{}
    foreach ($field in [Reflection.Emit.OpCodes].GetFields([Reflection.BindingFlags]'Public,Static')) {
        $opcode = $field.GetValue($null)
        $opcodes[[int]$opcode.Value -band 65535] = $opcode
    }
    $flags = [Reflection.BindingFlags]'Public,NonPublic,Instance,Static,DeclaredOnly'
    $wanted = @{
        'LuaSheetShapes' = '^(AddPath|Remove|\.ctor)$'
        'SheetShapes' = '^(Init|OnDestroy|RemoveDrawShape|AddDrawShape|DrawShapes|\.ctor)$'
        'SheetShapes+DrawPath' = '.*'
        'SheetShapes+DrawShape' = '.*'
        'ShapesRenderer' = '^(Init|OnDestroy|Update|\.ctor)$'
        'Shapes.DisposableMesh' = '.*'
        'Shapes.ShapesMeshPool' = '.*'
        'Shapes.PointPath`1' = 'Dispose|Finalize|\.ctor'
        'Shapes.PolylinePath' = 'Mesh|Dispose|Release|Reference|\.ctor'
        'Shapes.DrawCommand' = 'Dispose|Clear|Cleanup|Mesh|\.ctor'
        'Shapes.Draw' = 'Polyline_Internal'
        'LuaInterface' = '^(DumpRenderTextures|DebugUserDataReport|get_debugPropertyOutput)$'
    }
    $report = [ordered]@{
        scope = 'Selected ownership methods, not an exhaustive assembly call graph'
        assemblies = @(); types = @(); references = @(); unresolved = @()
    }
    foreach ($name in @('Assembly-CSharp', 'ShapesRuntime')) {
        $path = Join-Path $ManagedDirectory ($name + '.dll')
        $assembly = [Reflection.Assembly]::ReflectionOnlyLoadFrom($path)
        $report.assemblies += [ordered]@{
            path = $path
            sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash
            moduleId = $assembly.ManifestModule.ModuleVersionId.ToString()
        }
        foreach ($typeName in ($wanted.Keys | Sort-Object)) {
            $type = $assembly.GetType($typeName, $false)
            if ($null -eq $type) { continue }
            $record = [ordered]@{ name = $type.FullName; base = $type.BaseType.FullName; fields = @(); methods = @() }
            foreach ($field in $type.GetFields($flags)) {
                try { $record.fields += $field.ToString() }
                catch { $report.unresolved += [ordered]@{ field = $type.FullName + '::' + $field.Name; error = $_.Exception.Message } }
            }
            $methods = @($type.GetMethods($flags)) + @($type.GetConstructors($flags))
            foreach ($method in $methods) {
                if ($method.Name -notmatch $wanted[$type.FullName]) { continue }
                $caller = $type.FullName + '::' + $method.Name + ' #' + $method.MetadataToken.ToString('x8')
                try { $body = $method.GetMethodBody() }
                catch {
                    $report.unresolved += [ordered]@{ caller = $caller; error = $_.Exception.Message }
                    continue
                }
                if ($null -eq $body) { continue }
                $genericArguments = @()
                if ($method -is [Reflection.MethodInfo]) { $genericArguments = $method.GetGenericArguments() }
                $instructions = [Collections.Generic.List[string]]::new()
                $bytes = $body.GetILAsByteArray()
                $at = 0
                while ($at -lt $bytes.Length) {
                    $offset = $at
                    $value = [int]$bytes[$at++]
                    if ($value -eq 254) { $value = 65024 + $bytes[$at++] }
                    $opcode = $opcodes[$value]
                    $operand = ''
                    $size = 0
                    switch ($opcode.OperandType.ToString()) {
                        'InlineNone' { }
                        'ShortInlineI' { $size = 1; $operand = [sbyte]([int]$bytes[$at] - 256 * [int]($bytes[$at] -gt 127)) }
                        'ShortInlineVar' { $size = 1; $operand = $bytes[$at] }
                        'ShortInlineBrTarget' { $size = 1; $operand = $at + 1 + [int]$bytes[$at] - 256 * [int]($bytes[$at] -gt 127) }
                        'InlineVar' { $size = 2; $operand = [BitConverter]::ToUInt16($bytes, $at) }
                        'InlineI8' { $size = 8; $operand = [BitConverter]::ToInt64($bytes, $at) }
                        'InlineR' { $size = 8; $operand = [BitConverter]::ToDouble($bytes, $at) }
                        'ShortInlineR' { $size = 4; $operand = [BitConverter]::ToSingle($bytes, $at) }
                        'InlineSwitch' { $size = 4 + 4 * [BitConverter]::ToInt32($bytes, $at); $operand = 'switch targets omitted' }
                        default {
                            $size = 4
                            $token = [BitConverter]::ToInt32($bytes, $at)
                            if ($opcode.OperandType.ToString() -in @('InlineMethod', 'InlineField', 'InlineType', 'InlineTok')) {
                                try {
                                    $member = $method.Module.ResolveMember($token, $type.GetGenericArguments(), $genericArguments)
                                    $operand = $member.ToString()
                                    if ($member.DeclaringType) { $operand = $member.DeclaringType.FullName + '::' + $operand }
                                    if ($operand -match 'Shapes\.(DisposableMesh|PolylinePath)|SheetShapes.*DrawPath|SheetShapes::.*(RemoveDrawShape|OnDestroy)') {
                                        $report.references += [ordered]@{ caller = $caller; offset = $offset; opcode = $opcode.Name; target = $operand }
                                    }
                                } catch {
                                    $report.unresolved += [ordered]@{ caller = $caller; offset = $offset; token = $token; error = $_.Exception.Message }
                                    $operand = 'unresolved: ' + $token
                                }
                            } elseif ($opcode.OperandType.ToString() -eq 'InlineString') {
                                $operand = $method.Module.ResolveString($token)
                            } elseif ($opcode.OperandType.ToString() -eq 'InlineBrTarget') {
                                $operand = $at + 4 + $token
                            } else { $operand = $token }
                        }
                    }
                    $instructions.Add(('{0:x4} {1} {2}' -f $offset, $opcode.Name, $operand))
                    $at += $size
                }
                $record.methods += [ordered]@{ signature = $method.ToString(); il = $instructions.ToArray() }
            }
            $report.types += $record
        }
    }
    $json = $report | ConvertTo-Json -Depth 10
    if ($OutputPath) { [IO.File]::WriteAllText($OutputPath, $json, [Text.UTF8Encoding]::new($false)) }
    else { $json }
} finally {
    [AppDomain]::CurrentDomain.remove_ReflectionOnlyAssemblyResolve($resolver)
}
