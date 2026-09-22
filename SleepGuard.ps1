Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# --- Win32: 実行状態制御 ---
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class PowerMgmt {
    [FlagsAttribute]
    public enum EXECUTION_STATE : uint {
        ES_AWAYMODE_REQUIRED = 0x00000040,
        ES_CONTINUOUS = 0x80000000,
        ES_DISPLAY_REQUIRED = 0x00000002,
        ES_SYSTEM_REQUIRED = 0x00000001
    }
    [DllImport("kernel32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    public static extern EXECUTION_STATE SetThreadExecutionState(EXECUTION_STATE esFlags);
}
"@

# --- アイコン取得（exe版は埋め込みアイコン、ps1版は同フォルダのicoを使用） ---
function Get-AppIcon {
    $root = $PSScriptRoot
    if (-not $root) {
        try { $root = Split-Path -Parent ([System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName) } catch {}
    }
    if ($root) {
        $icoPath = Join-Path $root "sleepguard.ico"
        if (Test-Path $icoPath) {
            try { return New-Object System.Drawing.Icon($icoPath) } catch {}
        }
    }
    try {
        $exe = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
        if ($exe -notmatch 'powershell(_ise)?\.exe$') {
            return [System.Drawing.Icon]::ExtractAssociatedIcon($exe)
        }
    } catch {}
    return [System.Drawing.SystemIcons]::Information
}
$script:appIcon = Get-AppIcon

function Set-SleepPrevent {
    param([bool]$Enable, [bool]$KeepDisplayOn = $true)
    if ($Enable) {
        $flags = [PowerMgmt+EXECUTION_STATE]::ES_CONTINUOUS -bor [PowerMgmt+EXECUTION_STATE]::ES_SYSTEM_REQUIRED
        if ($KeepDisplayOn) { $flags = $flags -bor [PowerMgmt+EXECUTION_STATE]::ES_DISPLAY_REQUIRED }
        [PowerMgmt]::SetThreadExecutionState($flags) | Out-Null
    } else {
        [PowerMgmt]::SetThreadExecutionState([PowerMgmt+EXECUTION_STATE]::ES_CONTINUOUS) | Out-Null
    }
}

# --- 時間選択ダイアログ ---
function Show-DurationDialog {
    $form = New-Object System.Windows.Forms.Form
    $form.Text = "スリープ防止"
    $form.Size = New-Object System.Drawing.Size(320, 356)
    $form.StartPosition = "CenterScreen"
    $form.FormBorderStyle = "FixedDialog"
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.Topmost = $true
    $form.Icon = $script:appIcon

    $label = New-Object System.Windows.Forms.Label
    $label.Text = "何時間スリープを防止しますか？"
    $label.Location = New-Object System.Drawing.Point(20, 20)
    $label.Size = New-Object System.Drawing.Size(270, 20)
    $form.Controls.Add($label)

    $options = @(
        "30分",
        "1時間",
        "2時間",
        "4時間",
        "9時間（最長）",
        "カスタム（分単位で指定）"
    )
    $radios = @()
    $y = 50
    foreach ($opt in $options) {
        $rb = New-Object System.Windows.Forms.RadioButton
        $rb.Text = $opt
        $rb.Location = New-Object System.Drawing.Point(30, $y)
        $rb.Size = New-Object System.Drawing.Size(250, 22)
        $form.Controls.Add($rb)
        $radios += $rb
        $y += 26
    }
    $radios[1].Checked = $true  # デフォルト: 1時間

    $customBox = New-Object System.Windows.Forms.TextBox
    $customBox.Location = New-Object System.Drawing.Point(55, $y)
    $customBox.Size = New-Object System.Drawing.Size(80, 22)
    $customBox.Enabled = $false
    $form.Controls.Add($customBox)
    $customLabel = New-Object System.Windows.Forms.Label
    $customLabel.Text = "分"
    $labelY = $y + 3
    $customLabel.Location = New-Object System.Drawing.Point(140, $labelY)
    $customLabel.Size = New-Object System.Drawing.Size(30, 20)
    $form.Controls.Add($customLabel)

    foreach ($rb in $radios) {
        $rb.Add_CheckedChanged({
            $customBox.Enabled = $radios[5].Checked
        })
    }

    $displayCheck = New-Object System.Windows.Forms.CheckBox
    $chkY = $y + 34
    $displayCheck.Location = New-Object System.Drawing.Point(30, $chkY)
    $displayCheck.Size = New-Object System.Drawing.Size(260, 22)
    $displayCheck.Text = "ディスプレイも消さない"
    $displayCheck.Checked = $true
    $form.Controls.Add($displayCheck)

    $okButton = New-Object System.Windows.Forms.Button
    $okButton.Text = "開始"
    $btnY = $y + 70
    $okButton.Location = New-Object System.Drawing.Point(110, $btnY)
    $okButton.Size = New-Object System.Drawing.Size(90, 30)
    $okButton.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $form.Controls.Add($okButton)
    $form.AcceptButton = $okButton

    $result = $form.ShowDialog()
    if ($result -ne [System.Windows.Forms.DialogResult]::OK) { return $null }

    $minutesMap = @{0=30; 1=60; 2=120; 3=240; 4=540}
    $mins = $null
    for ($i=0; $i -lt 5; $i++) {
        if ($radios[$i].Checked) { $mins = $minutesMap[$i]; break }
    }
    if ($null -eq $mins) {
        if ($radios[5].Checked) {
            $val = 0
            if ([int]::TryParse($customBox.Text, [ref]$val) -and $val -gt 0) {
                if ($val -gt 540) { $val = 540 }  # 最長9時間に制限
                $mins = $val
            } else {
                [System.Windows.Forms.MessageBox]::Show("有効な分数を入力してください（1～540分）", "エラー") | Out-Null
                return $null
            }
        } else {
            $mins = 60
        }
    }
    return [pscustomobject]@{ Minutes = $mins; KeepDisplayOn = $displayCheck.Checked }
}

$choice = Show-DurationDialog
if (-not $choice) { exit }
$minutes = $choice.Minutes
$script:keepDisplayOn = $choice.KeepDisplayOn

$endTime = (Get-Date).AddMinutes($minutes)

# --- スリープ防止 ON ---
Set-SleepPrevent -Enable $true -KeepDisplayOn $script:keepDisplayOn

# --- タスクトレイアイコン ---
$notifyIcon = New-Object System.Windows.Forms.NotifyIcon
$notifyIcon.Icon = try {
    New-Object System.Drawing.Icon($script:appIcon, [System.Windows.Forms.SystemInformation]::SmallIconSize)
} catch { $script:appIcon }
$notifyIcon.Visible = $true
$notifyIcon.Text = "スリープ防止: 終了 $($endTime.ToString('HH:mm')) まで"

$contextMenu = New-Object System.Windows.Forms.ContextMenuStrip
$statusItem = New-Object System.Windows.Forms.ToolStripMenuItem
$statusItem.Text = "終了予定: $($endTime.ToString('HH:mm'))"
$statusItem.Enabled = $false
$contextMenu.Items.Add($statusItem) | Out-Null
$contextMenu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator)) | Out-Null
$displayItem = New-Object System.Windows.Forms.ToolStripMenuItem
$displayItem.Text = "ディスプレイも消さない"
$displayItem.CheckOnClick = $true
$displayItem.Checked = $script:keepDisplayOn
$contextMenu.Items.Add($displayItem) | Out-Null
$stopItem = New-Object System.Windows.Forms.ToolStripMenuItem
$stopItem.Text = "今すぐ解除して終了"
$contextMenu.Items.Add($stopItem) | Out-Null
$notifyIcon.ContextMenuStrip = $contextMenu

$dispText = if ($script:keepDisplayOn) { "スリープ＋画面オフを防止" } else { "スリープのみ防止（画面は消えます）" }
$notifyIcon.ShowBalloonTip(4000, "スリープ防止を開始しました", "$minutes 分間（$($endTime.ToString('HH:mm')) まで）$dispText します。`nタスクトレイのアイコンから途中解除もできます。", [System.Windows.Forms.ToolTipIcon]::Info)

$script:shouldExit = $false

$displayItem.Add_CheckedChanged({
    $script:keepDisplayOn = $displayItem.Checked
    Set-SleepPrevent -Enable $true -KeepDisplayOn $script:keepDisplayOn
})

$stopItem.Add_Click({
    $script:shouldExit = $true
})

$notifyIcon.Add_DoubleClick({
    $script:shouldExit = $true
})

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 15000  # 15秒ごとにチェック & 実行状態を再アサート
$timer.Add_Tick({
    Set-SleepPrevent -Enable $true -KeepDisplayOn $script:keepDisplayOn
    if ((Get-Date) -ge $endTime) {
        $script:shouldExit = $true
    }
    $remain = New-TimeSpan -Start (Get-Date) -End $endTime
    if ($remain.TotalSeconds -gt 0) {
        $notifyIcon.Text = "スリープ防止中: あと $([int]$remain.TotalMinutes) 分"
    }
    if ($script:shouldExit) {
        [System.Windows.Forms.Application]::Exit()
    }
})
$timer.Start()

[System.Windows.Forms.Application]::Run()

# --- 終了処理: スリープ防止を解除 ---
Set-SleepPrevent -Enable $false
$notifyIcon.Visible = $false
$notifyIcon.Dispose()
