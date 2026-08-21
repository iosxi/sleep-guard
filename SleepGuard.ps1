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
    $form.Size = New-Object System.Drawing.Size(320, 310)
    $form.StartPosition = "CenterScreen"
    $form.FormBorderStyle = "FixedDialog"
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.Topmost = $true

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

    $okButton = New-Object System.Windows.Forms.Button
    $okButton.Text = "開始"
    $btnY = $y + 35
    $okButton.Location = New-Object System.Drawing.Point(110, $btnY)
    $okButton.Size = New-Object System.Drawing.Size(90, 30)
    $okButton.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $form.Controls.Add($okButton)
    $form.AcceptButton = $okButton

    $result = $form.ShowDialog()
    if ($result -ne [System.Windows.Forms.DialogResult]::OK) { return $null }

    $minutesMap = @{0=30; 1=60; 2=120; 3=240; 4=540}
    for ($i=0; $i -lt 5; $i++) {
        if ($radios[$i].Checked) { return $minutesMap[$i] }
    }
    if ($radios[5].Checked) {
        $val = 0
        if ([int]::TryParse($customBox.Text, [ref]$val) -and $val -gt 0) {
            if ($val -gt 540) { $val = 540 }  # 最長9時間に制限
            return $val
        } else {
            [System.Windows.Forms.MessageBox]::Show("有効な分数を入力してください（1～540分）", "エラー") | Out-Null
            return $null
        }
    }
    return 60
}

$minutes = Show-DurationDialog
if (-not $minutes) { exit }

$endTime = (Get-Date).AddMinutes($minutes)

# --- スリープ防止 ON ---
Set-SleepPrevent -Enable $true -KeepDisplayOn $false

# --- タスクトレイアイコン ---
$notifyIcon = New-Object System.Windows.Forms.NotifyIcon
$notifyIcon.Icon = [System.Drawing.SystemIcons]::Information
$notifyIcon.Visible = $true
$notifyIcon.Text = "スリープ防止: 終了 $($endTime.ToString('HH:mm')) まで"

$contextMenu = New-Object System.Windows.Forms.ContextMenuStrip
$statusItem = New-Object System.Windows.Forms.ToolStripMenuItem
$statusItem.Text = "終了予定: $($endTime.ToString('HH:mm'))"
$statusItem.Enabled = $false
$contextMenu.Items.Add($statusItem) | Out-Null
$contextMenu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator)) | Out-Null
$stopItem = New-Object System.Windows.Forms.ToolStripMenuItem
$stopItem.Text = "今すぐ解除して終了"
$contextMenu.Items.Add($stopItem) | Out-Null
$notifyIcon.ContextMenuStrip = $contextMenu

$notifyIcon.ShowBalloonTip(4000, "スリープ防止を開始しました", "$minutes 分間（$($endTime.ToString('HH:mm')) まで）スリープを防止します。`nタスクトレイのアイコンから途中解除もできます。", [System.Windows.Forms.ToolTipIcon]::Info)

$script:shouldExit = $false

$stopItem.Add_Click({
    $script:shouldExit = $true
})

$notifyIcon.Add_DoubleClick({
    $script:shouldExit = $true
})

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 15000  # 15秒ごとにチェック & 実行状態を再アサート
$timer.Add_Tick({
    Set-SleepPrevent -Enable $true -KeepDisplayOn $false
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
