#Requires AutoHotkey v2.0+
#SingleInstance Force

SendMode "Input"
SetWorkingDir A_ScriptDir

; ======================================================================
; Spam Key Configuration (v2 port of your v4.1 v1 script)
; ======================================================================

; -------------------------
; Constants
; -------------------------
MinKeys := 4
MaxKeys := 8

SpamHotkeyDefault := "XButton2"
SpamHotkey := SpamHotkeyDefault

DefaultConfigFile := A_ScriptDir "\SpamKeyConfig.ini"    ; global fallback/template
ConfigDir := A_ScriptDir "\Profiles"

KeyListURL := "https://www.autohotkey.com/docs/v1/KeyList.htm"

; --- Layout constants ---
GuiW := 590
MarginX := 8
MarginY := 8

KeysX := 10, KeysY := 10, KeysW := 305
SetBtnX := 25, KeyX := 75, DelayX := 170, OnX := 270
HeaderY := 35
RowsYStart := 55
RowH := 24

BottomPad := 6
ButtonsGap := 12
BtnH := 24

SettingsX := 325, SettingsY := 10, SettingsW := 250

; --- Tray/Window behavior ---
StartMinimized := 0     ; 1 = start hidden in tray, 0 = show GUI on start
GuiVisible := false     ; internal state

; -------------------------
; State
; -------------------------
KeyCount := MinKeys
Toggle := false

KeyEnabled := []
KeyName := []
KeyDelay := []

TimerFns := []      ; BoundFuncs for SetTimer
TimerActive := []   ; bool

CurrentConfigFile := ""
MainGui := 0

; GUI controls
GrpKeys := 0
GrpSettings := 0

CapBtn := []
EdKeyName := []
EdKeyDelay := []
CbKeyEnabled := []

BtnAddKey := 0
BtnRemoveKey := 0

LnkHotkeyLabel := 0
EdHotkey := 0
BtnPickHotkey := 0

EdCurrentProfile := 0
EdNewProfileName := 0

BtnSaveAs := 0
BtnLoad := 0
BtnSave := 0
BtnExit := 0

; -------------------------
; ; Globals for capture callback (simple and reliable) 
; -------------------------
__cap_done := false
__cap_key := ""
__cap_mods := ""

; -------------------------
; Init defaults
; -------------------------
InitDefaults()

if !DirExist(ConfigDir)
    DirCreate ConfigDir

; Tray icon
try TraySetIcon(A_ScriptDir "\Profiles\symbol.ico")

EnsureDefaultIni()
SelectStartupProfile()
LoadConfigFromIni()

BuildTrayMenu()
BuildGui()
BindSpamHotkey()

UpdateGuiFromVars()
UpdateWindowTitle()

if StartMinimized {
    GuiVisible := false
    MainGui.Show("Hide w" GuiW)
} else {
    ShowMainGui()
}

return

; ======================================================================
; Initialization helpers
; ======================================================================

InitDefaults() {
    global MinKeys, MaxKeys, KeyCount, KeyEnabled, KeyName, KeyDelay, TimerFns, TimerActive

    KeyCount := MinKeys

	KeyEnabled := [], KeyEnabled.Length := MaxKeys
	KeyName := [],    KeyName.Length := MaxKeys
	KeyDelay := [],   KeyDelay.Length := MaxKeys
	TimerFns := [],   TimerFns.Length := MaxKeys
	TimerActive := [],TimerActive.Length := MaxKeys

	Loop MaxKeys {
		i := A_Index
		KeyEnabled[i] := 0
		KeyName[i] := ""
		KeyDelay[i] := 1000
		TimerFns[i] := SpamTick.Bind(i)
		TimerActive[i] := false
	}

    ; Default keys (used if INI does not provide values)
    KeyName[1] := "1", KeyName[2] := "2", KeyName[3] := "3", KeyName[4] := "4"
    KeyDelay[1] := 1250, KeyDelay[2] := 6000, KeyDelay[3] := 1000, KeyDelay[4] := 1000
}

EnsureDefaultIni() {
    global DefaultConfigFile, SpamHotkeyDefault, MinKeys, MaxKeys, KeyEnabled, KeyName, KeyDelay

    if FileExist(DefaultConfigFile)
        return

    ; Minimal template values (do NOT enable keys by default)
    IniWrite(DefaultConfigFile, DefaultConfigFile, "App", "LastProfile")
    IniWrite(SpamHotkeyDefault, DefaultConfigFile, "Spam Key", "Hotkey")
    IniWrite(MinKeys, DefaultConfigFile, "Spam Key", "KeyCount")

    Loop MaxKeys {
        i := A_Index
        IniWrite(KeyEnabled[i], DefaultConfigFile, "Spam Key", "KeyEnabled" i)
        IniWrite(KeyName[i], DefaultConfigFile, "Spam Key", "KeyName" i)
        IniWrite(KeyDelay[i], DefaultConfigFile, "Spam Key", "KeyDelay" i)
    }
}

SelectStartupProfile() {
    global DefaultConfigFile, CurrentConfigFile
    lastProfile := IniRead(DefaultConfigFile, "App", "LastProfile", "")
    if (lastProfile != "" && FileExist(lastProfile))
        CurrentConfigFile := lastProfile
    else
        CurrentConfigFile := DefaultConfigFile
}

; ======================================================================
; Tray menu
; ======================================================================

BuildTrayMenu() {
    A_TrayMenu.Delete()
    A_TrayMenu.Add("Open", TrayOpen)
    A_TrayMenu.Add("Pause", TrayPause)
    A_TrayMenu.Add()
    A_TrayMenu.Add("Exit", TrayExit)

    A_TrayMenu.Default := "Open"
    A_TrayMenu.ClickCount := 1
}

TrayOpen(*) => ShowMainGui()

TrayPause(*) {
    Pause(-1) ; toggle pause state
    if A_IsPaused
        A_TrayMenu.Check("Pause")
    else
        A_TrayMenu.Uncheck("Pause")
}

TrayExit(*) => ExitApp()

; ======================================================================
; GUI
; ======================================================================

BuildGui() {
    global MainGui, GuiW, MarginX, MarginY
    global KeysX, KeysY, KeysW, SettingsX, SettingsY, SettingsW
    global HeaderY, RowsYStart, RowH, SetBtnX, KeyX, DelayX, OnX
    global BtnH, KeyListURL
    global GrpKeys, GrpSettings
    global CapBtn, EdKeyName, EdKeyDelay, CbKeyEnabled
    global BtnAddKey, BtnRemoveKey
    global LnkHotkeyLabel, EdHotkey, BtnPickHotkey
    global EdCurrentProfile, EdNewProfileName
    global BtnSaveAs, BtnLoad, BtnSave, BtnExit
    global MaxKeys

    ; Pre-allocate control arrays (v2 needs valid indices)
    CapBtn := [],       CapBtn.Length := MaxKeys
    EdKeyName := [],    EdKeyName.Length := MaxKeys
    EdKeyDelay := [],   EdKeyDelay.Length := MaxKeys
    CbKeyEnabled := [], CbKeyEnabled.Length := MaxKeys

    MainGui := Gui(, "Spam Key Configuration")
    MainGui.MarginX := MarginX
    MainGui.MarginY := MarginY
    MainGui.SetFont("s9", "Segoe UI")

    MainGui.OnEvent("Close", (*) => ExitApp())
    MainGui.OnEvent("Escape", (*) => ExitApp())
    MainGui.OnEvent("Size", GuiSize)

    ; ---- Keys group ----
    GrpKeys := MainGui.Add("GroupBox", "x" KeysX " y" KeysY " w" KeysW " h196", "Keys")
    MainGui.Add("Text", "x" KeyX " y" HeaderY " w75", "Key")
    MainGui.Add("Text", "x" DelayX " y" HeaderY " w95", "Interval (ms)")
    MainGui.Add("Text", "x" OnX " y" HeaderY " w28", "On")

    Loop MaxKeys {
        i := A_Index
        y := RowsYStart + (i - 1) * RowH
        y2 := y - 2

        CapBtn[i] := MainGui.Add("Button", "x" SetBtnX " y" y2 " w45 h22", "Set")
        CapBtn[i].OnEvent("Click", CaptureKey.Bind(i))  ; <<< FIX

        EdKeyName[i] := MainGui.Add("Edit", "x" KeyX " y" y2 " w80 ReadOnly -Tabstop")
        EdKeyDelay[i] := MainGui.Add("Edit", "x" DelayX " y" y2 " w80")
        CbKeyEnabled[i] := MainGui.Add("CheckBox", "x" OnX " y" y " w25")
    }

    BtnAddKey := MainGui.Add("Button", "x25 y205 w130 h" BtnH, "Add key")
    BtnAddKey.OnEvent("Click", (*) => AddKeyRow())

    BtnRemoveKey := MainGui.Add("Button", "x165 y205 w130 h" BtnH, "Remove key")
    BtnRemoveKey.OnEvent("Click", (*) => RemoveKeyRow())

    ; ---- Settings group ----
    GrpSettings := MainGui.Add("GroupBox", "x" SettingsX " y" SettingsY " w" SettingsW " h196", "Settings")

    LnkHotkeyLabel := MainGui.Add("Link", "x340 y35 w70", '<a href="' KeyListURL '">Hotkey:</a>')
    EdHotkey := MainGui.Add("Edit", "x410 y33 w105")

    BtnPickHotkey := MainGui.Add("Button", "x520 y33 w45 h22", "Pick...")
    BtnPickHotkey.OnEvent("Click", (*) => SetHotkeyCapture())

    MainGui.Add("Text", "x340 y65 w70", "Current:")
    EdCurrentProfile := MainGui.Add("Edit", "x410 y63 w155 ReadOnly -Tabstop")

    MainGui.Add("Text", "x340 y95 w70", "New name:")
    EdNewProfileName := MainGui.Add("Edit", "x410 y93 w155")

    BtnSaveAs := MainGui.Add("Button", "x340 y125 w225 h" BtnH, "Save As...")
    BtnSaveAs.OnEvent("Click", (*) => SaveProfileAs())

    BtnLoad := MainGui.Add("Button", "x340 y155 w225 h" BtnH, "Load...")
    BtnLoad.OnEvent("Click", (*) => LoadProfileFromDialog())

    BtnSave := MainGui.Add("Button", "x340 y185 w105 h" BtnH, "Save")
    BtnSave.OnEvent("Click", (*) => SaveCurrentProfile())

    BtnExit := MainGui.Add("Button", "x460 y185 w105 h" BtnH, "Exit")
    BtnExit.OnEvent("Click", (*) => ExitApp())
}

GuiSize(guiObj, minMax, width, height) {
    ; minMax = -1 => minimized
    if (minMax = -1)
        HideMainGui()
}

ShowMainGui() {
    global MainGui, GuiVisible, GuiW
    GuiVisible := true
    MainGui.Show("Restore w" GuiW)
    UpdateLayout()
    try WinActivate("ahk_id " MainGui.Hwnd)
}

HideMainGui() {
    global MainGui, GuiVisible
    GuiVisible := false
    MainGui.Hide()
}

; ======================================================================
; GUI update helpers
; ======================================================================

UpdateGuiFromVars() {
    global CurrentConfigFile, SpamHotkey, KeyCount, MinKeys, MaxKeys
    global KeyEnabled, KeyName, KeyDelay
    global EdCurrentProfile, EdHotkey, EdKeyName, EdKeyDelay, CbKeyEnabled
    global CapBtn, BtnAddKey, BtnRemoveKey

    SplitPath(CurrentConfigFile, &cfgName)

    EdCurrentProfile.Value := cfgName
    EdHotkey.Value := SpamHotkey

    Loop MaxKeys {
        i := A_Index
        CbKeyEnabled[i].Value := KeyEnabled[i] ? 1 : 0
        EdKeyName[i].Value := KeyName[i]
        EdKeyDelay[i].Value := KeyDelay[i]

        show := (i <= KeyCount)
        SetCtlVisible(CbKeyEnabled[i], show)
        SetCtlVisible(EdKeyName[i], show)
        SetCtlVisible(CapBtn[i], show)
        SetCtlVisible(EdKeyDelay[i], show)
    }

    BtnAddKey.Enabled := (KeyCount < MaxKeys)
    BtnRemoveKey.Enabled := (KeyCount > MinKeys)

    UpdateLayout()
}

UpdateLayout() {
    global MainGui, GuiVisible
    global KeysY, RowsYStart, RowH, ButtonsGap, BtnH, BottomPad
    global BtnAddKey, BtnRemoveKey
    global BtnSaveAs, BtnLoad, BtnSave, BtnExit
    global GrpKeys, GrpSettings

    yButtons := RowsYStart + KeyCount * RowH + ButtonsGap

    btnStep := BtnH + 4
    ySaveAs := yButtons - 2 * btnStep
    yLoad := yButtons - 1 * btnStep

    minSaveAsY := 120
    if (ySaveAs < minSaveAsY) {
        delta := minSaveAsY - ySaveAs
        ySaveAs += delta
        yLoad += delta
        yButtons += delta
    }

    MoveCtlY(BtnAddKey, yButtons)
    MoveCtlY(BtnRemoveKey, yButtons)

    MoveCtlY(BtnSaveAs, ySaveAs)
    MoveCtlY(BtnLoad, yLoad)
    MoveCtlY(BtnSave, yButtons)
    MoveCtlY(BtnExit, yButtons)

    groupH := (yButtons + BtnH + BottomPad) - KeysY

    minButtonsY := minSaveAsY + 2 * btnStep
    minGroupH := (minButtonsY + BtnH + BottomPad) - KeysY
    if (groupH < minGroupH)
        groupH := minGroupH

    ResizeCtlH(GrpKeys, groupH)
    ResizeCtlH(GrpSettings, groupH)

    winH := KeysY + groupH + 12

    if GuiVisible
        MainGui.Show("h" winH)
    else
        MainGui.Show("Hide h" winH)
}

UpdateWindowTitle() {
    global MainGui, CurrentConfigFile
    SplitPath(CurrentConfigFile, &cfgName)
    MainGui.Title := "Spam Key Configuration - " cfgName
}

MoveCtlY(ctrl, newY) {
    ctrl.GetPos(&x, &y, &w, &h)
    ctrl.Move(x, newY, w, h)
}

ResizeCtlH(ctrl, newH) {
    ctrl.GetPos(&x, &y, &w, &h)
    ctrl.Move(x, y, w, newH)
}

SetCtlVisible(ctrl, visible) {
    ctrl.Visible := !!visible
}

; ======================================================================
; Key row management
; ======================================================================

AddKeyRow() {
    global KeyCount, MaxKeys
    if (KeyCount >= MaxKeys)
        return
    KeyCount += 1
    UpdateGuiFromVars()
}

RemoveKeyRow() {
    global KeyCount, MinKeys, KeyEnabled, KeyName, KeyDelay
    if (KeyCount <= MinKeys)
        return

    idx := KeyCount
    KeyEnabled[idx] := 0
    KeyName[idx] := ""
    KeyDelay[idx] := 1000

    KeyCount -= 1
    UpdateGuiFromVars()
}

; ======================================================================
; Capture hotkey (GUI)
; ======================================================================

SetHotkeyCapture() {
    global SpamHotkey

    ; prevent toggling while capturing
    DisableSpamHotkey()

    hk := CaptureHotkeyHybrid_OnKeyDown(7000)

    ; restore
    EnableSpamHotkey()

    if (hk != "")
        EdHotkey.Value := hk
}

CaptureHotkeyHybrid_OnKeyDown(timeoutMs := 5000) {
    global __cap_done, __cap_key, __cap_mods

    __cap_done := false
    __cap_key := ""
    __cap_mods := ""

    mouseBtns := ["XButton2", "XButton1", "MButton", "RButton", "LButton"]

    ToolTip "Press a key or mouse button now..."

    ih := InputHook()
    ih.KeyOpt("{All}", "NS")     ; Notify + Suppress
    ih.OnKeyDown := __HK_OnKeyDown
    ih.Start()

    start := A_TickCount
    while (A_TickCount - start < timeoutMs) {

        for b in mouseBtns {
            if GetKeyState(b, "P") {
                ih.Stop()
                ToolTip
                return GetModsFromKeyState() b
            }
        }

        if (__cap_done) {
            ih.Stop()
            ToolTip
            return __cap_mods __cap_key
        }

        Sleep 10
    }

    ih.Stop()
    ToolTip
    return ""
}

__HK_OnKeyDown(ih, vk, sc) {
    global __cap_done, __cap_key, __cap_mods

    key := GetKeyName(Format("vk{:X}sc{:X}", vk, sc))

    ; ignore pure modifiers as final key
    if (key = "LShift" || key = "RShift" || key = "LControl" || key = "RControl" || key = "LAlt" || key = "RAlt" || key = "LWin" || key = "RWin")
        return

    __cap_mods := GetModsFromKeyState()
    __cap_key := key
    __cap_done := true
}

GetModsFromKeyState() {
    mods := ""
    if GetKeyState("Ctrl", "P")
        mods .= "^"
    if GetKeyState("Alt", "P")
        mods .= "!"
    if GetKeyState("Shift", "P")
        mods .= "+"
    if (GetKeyState("LWin", "P") || GetKeyState("RWin", "P"))
        mods .= "#"
    return mods
}

; ======================================================================
; Capture key (single key for spam rows)
; ======================================================================

CaptureKey(row, *) {
    global SpamHotkey

    DisableSpamHotkey()
    captured := CaptureSingleKey()
    EnableSpamHotkey()

    if (captured = "")
        return

    if (captured = "LShift" || captured = "RShift" || captured = "Shift"
     || captured = "LCtrl"  || captured = "RCtrl"  || captured = "Ctrl"
     || captured = "LAlt"   || captured = "RAlt"   || captured = "Alt"
     || captured = "LWin"   || captured = "RWin") {
        MsgBox "Modifier keys are not allowed. Please press a normal key.", "Error", "Icon!"
        return
    }

    if (GetKeyState("Ctrl", "P") || GetKeyState("Alt", "P") || GetKeyState("Shift", "P") || GetKeyState("LWin", "P") || GetKeyState("RWin", "P")) {
        MsgBox "Please press the key without holding Ctrl/Alt/Shift/Win.", "Error", "Icon!"
        return
    }

    SetRowKey(row, captured)
}

CaptureSingleKey() {
    ih := InputHook("L0")
    ih.KeyOpt("{All}", "ES")   ; EndKey + Suppress
    ih.Start()
    ih.Wait()
    return ih.EndKey
}

SetRowKey(row, key) {
    global KeyName, EdKeyName
    KeyName[row] := key
    EdKeyName[row].Value := key
}

; ======================================================================
; Button handlers (Save/Load)
; ======================================================================

SaveCurrentProfile() {
    global CurrentConfigFile, DefaultConfigFile, EdNewProfileName

    ReadGuiToVars()

    if (CurrentConfigFile = DefaultConfigFile) {
		MsgBox('The default config is a fallback template and cannot be overwritten. Use "Save As..." to create a profile.', 'Error', 'Icon!')
		return
    }

    err := ValidateAll()
    if (err != "") {
        MsgBox err, "Error", "Icon!"
        return
    }

    ApplyHotkeyIfChanged()

    SaveConfigToIni()
    RememberLastProfile(CurrentConfigFile, DefaultConfigFile)

    EdNewProfileName.Value := ""
    UpdateGuiFromVars()
    UpdateWindowTitle()
}

SaveProfileAs() {
    global ConfigDir, CurrentConfigFile, DefaultConfigFile, EdNewProfileName

    ReadGuiToVars()

    err := ValidateAll()
    if (err != "") {
        MsgBox err, "Error", "Icon!"
        return
    }

    name := Trim(EdNewProfileName.Value)
    if (name = "") {
        MsgBox "Please enter a new profile name.", "Error", "Icon!"
        return
    }

    if (SubStr(name, -4) = ".ini")
        name := SubStr(name, 1, -4)

    if !IsValidProfileName(name) {
        MsgBox('Invalid profile name.`nAvoid these characters: \ / : * ? " < > |', 'Error', 'Icon!')
        return
    }

    ApplyHotkeyIfChanged()

    newFile := ConfigDir "\" name ".ini"
    CurrentConfigFile := newFile

    SaveConfigToIni()
    RememberLastProfile(CurrentConfigFile, DefaultConfigFile)

    EdNewProfileName.Value := ""
    UpdateGuiFromVars()
    UpdateWindowTitle()
}

LoadProfileFromDialog() {
    global ConfigDir, CurrentConfigFile, DefaultConfigFile

    newConfig := FileSelect(3, ConfigDir, "Select profile", "INI Files (*.ini)")
    if (newConfig = "")
        return

    StopAllSpamTimers()
    DisableSpamHotkey()

    CurrentConfigFile := newConfig
    LoadConfigFromIni()

    EnableSpamHotkey()

    RememberLastProfile(CurrentConfigFile, DefaultConfigFile)
    UpdateGuiFromVars()
    UpdateWindowTitle()
}

ReadGuiToVars() {
    global KeyCount, MaxKeys, KeyEnabled, KeyName, KeyDelay
    global CbKeyEnabled, EdKeyName, EdKeyDelay
    global SpamHotkey, EdHotkey

    SpamHotkeyGui := Trim(EdHotkey.Value)
    if (SpamHotkeyGui != "")
        ; keep in GUI control only; ApplyHotkeyIfChanged() will validate and assign
        SpamHotkeyGui := SpamHotkeyGui

    Loop MaxKeys {
        i := A_Index
        KeyEnabled[i] := (CbKeyEnabled[i].Value ? 1 : 0)
        KeyName[i] := Trim(EdKeyName[i].Value)
        KeyDelay[i] := Trim(EdKeyDelay[i].Value)
    }
}

ApplyHotkeyIfChanged() {
    global SpamHotkey, EdHotkey

    newHK := Trim(EdHotkey.Value)
    if (newHK = "")
        return

    if (newHK != SpamHotkey) {
        if !IsValidHotkey(newHK) {
            MsgBox "Invalid hotkey.`nExamples: XButton2  |  ^!p  |  +F8", "Error", "Icon!"
            EdHotkey.Value := SpamHotkey
            return
        }

        StopAllSpamTimers()
        DisableSpamHotkey()

        SpamHotkey := newHK
        EnableSpamHotkey()
    }
}

; ======================================================================
; Config I/O
; ======================================================================

LoadConfigFromIni() {
    global CurrentConfigFile, SpamHotkeyDefault, SpamHotkey, MinKeys, MaxKeys, KeyCount
    global KeyEnabled, KeyName, KeyDelay

    if !FileExist(CurrentConfigFile)
        return

    tmpHK := IniRead(CurrentConfigFile, "Spam Key", "Hotkey", SpamHotkeyDefault)
    if (tmpHK = "" || !IsValidHotkey(tmpHK)) {
        SpamHotkey := SpamHotkeyDefault
        IniWrite(SpamHotkeyDefault, CurrentConfigFile, "Spam Key", "Hotkey")
    } else {
        SpamHotkey := tmpHK
    }

    tmpCount := IniRead(CurrentConfigFile, "Spam Key", "KeyCount", MinKeys)
    tmpCount := IntegerOr(tmpCount, MinKeys)
    if (tmpCount < MinKeys)
        tmpCount := MinKeys
    if (tmpCount > MaxKeys)
        tmpCount := MaxKeys
    KeyCount := tmpCount

	Loop MaxKeys {
		i := A_Index

		if (i > KeyCount) {
			KeyEnabled[i] := 0
			KeyName[i] := ""
			KeyDelay[i] := 1000
			continue
		}

		tmpEn := IniRead(CurrentConfigFile, "Spam Key", "KeyEnabled" i, "")
		if (tmpEn = "0" || tmpEn = "1")
			KeyEnabled[i] := Integer(tmpEn)

		tmpName := IniRead(CurrentConfigFile, "Spam Key", "KeyName" i, "")
		if (Trim(tmpName) != "")
			KeyName[i] := tmpName

		tmpDelay := IniRead(CurrentConfigFile, "Spam Key", "KeyDelay" i, "")
		if (RegExMatch(tmpDelay, "^\d+$") && Integer(tmpDelay) >= 1)
			KeyDelay[i] := Integer(tmpDelay)
	}
}

SaveConfigToIni() {
    global CurrentConfigFile, SpamHotkey, KeyCount, MaxKeys, KeyEnabled, KeyName, KeyDelay

    IniWrite(SpamHotkey, CurrentConfigFile, "Spam Key", "Hotkey")
    IniWrite(KeyCount, CurrentConfigFile, "Spam Key", "KeyCount")

    Loop MaxKeys {
        i := A_Index
        IniWrite(KeyEnabled[i], CurrentConfigFile, "Spam Key", "KeyEnabled" i)
        IniWrite(KeyName[i], CurrentConfigFile, "Spam Key", "KeyName" i)
        IniWrite(KeyDelay[i], CurrentConfigFile, "Spam Key", "KeyDelay" i)
    }
}

RememberLastProfile(profilePath, globalIniPath) {
    IniWrite(profilePath, globalIniPath, "App", "LastProfile")
}

IntegerOr(val, fallback) {
    if RegExMatch(val, "^-?\d+$")
        return Integer(val)
    return fallback
}

; ======================================================================
; Spam engine
; ======================================================================
HotkeyBindName(hk) {
    hk := Trim(hk)
    if (hk = "")
        return hk

    ; If user already typed ~, keep it.
    if (SubStr(hk, 1, 1) = "~")
        return hk

    ; Auto pass-through only for mouse-related hotkeys.
    if RegExMatch(hk, "i)(XButton1|XButton2|LButton|RButton|MButton|WheelUp|WheelDown|WheelLeft|WheelRight)")
        return "~" hk

    return hk
}

BindSpamHotkey() {
    global SpamHotkey
    try Hotkey(HotkeyBindName(SpamHotkey), ToggleSpam, "On")
}

DisableSpamHotkey() {
    global SpamHotkey
    try Hotkey(HotkeyBindName(SpamHotkey), "Off")
}

EnableSpamHotkey() {
    global SpamHotkey
    try Hotkey(HotkeyBindName(SpamHotkey), ToggleSpam, "On")
}

ToggleSpam(*) {
    global Toggle, KeyCount, KeyEnabled, KeyName, KeyDelay, TimerFns, TimerActive

    Toggle := !Toggle
    if Toggle {
        started := false
        Loop KeyCount {
            i := A_Index
            if (KeyEnabled[i] && Trim(KeyName[i]) != "") {
                SetTimer(TimerFns[i], Integer(KeyDelay[i]))
                TimerActive[i] := true
                started := true
            }
        }
        if !started {
            Toggle := false
            MsgBox "No enabled keys to spam.", "Info", "Iconi"
        }
    } else {
        StopAllSpamTimers()
    }
}

StopAllSpamTimers() {
    global Toggle, MaxKeys, TimerFns, TimerActive
    Toggle := false
    Loop MaxKeys {
        i := A_Index
        SetTimer(TimerFns[i], 0)
        TimerActive[i] := false
    }
}

SpamTick(i) {
    global KeyName
    k := KeyName[i]
    if (Trim(k) = "")
        return
    Send("{" k "}")
}

; ======================================================================
; Validation
; ======================================================================

ValidateAll() {
    err := ValidateDelays()
    if (err != "")
        return err

    err := ValidateKeys()
    if (err != "")
        return err

    hk := Trim(EdHotkey.Value)
    if (hk = "")
        return "Hotkey must not be empty."
    if !IsValidHotkey(hk)
        return "Invalid hotkey."

    return ""
}

ValidateDelays() {
    global KeyCount, KeyDelay
    Loop KeyCount {
        i := A_Index
        delay := Trim(KeyDelay[i])
        if (!RegExMatch(delay, "^\d+$") || Integer(delay) < 1)
            return "All intervals must be integers > 0 (check row " i ")."
    }
    return ""
}

ValidateKeys() {
    global KeyCount, KeyEnabled, KeyName

    Loop KeyCount {
        i := A_Index

        if !KeyEnabled[i]
            continue

        k := Trim(KeyName[i])
        if (k = "")
            return "Row " i " is enabled but has no key set (click 'Set')."

        j := i + 1
        while (j <= KeyCount) {
            if (KeyEnabled[j] && Trim(KeyName[j]) = k)
                return "Duplicate key '" k "' is enabled in multiple rows."
            j += 1
        }
    }
    return ""
}

IsValidProfileName(name) {
    name := Trim(name)
    if (name = "")
        return false
	if RegExMatch(name, '[\\/:*?"<>|]')
		return false
	if RegExMatch(name, '[ \.]+$')
		return false
    return true
}

IsValidHotkey(hk) {
    hk := Trim(hk)
    if (hk = "")
        return false
    if InStr(hk, " ")
        return false

    ; Create a variant that can never fire -> avoids modifying the real hotkey.
    HotIf (*) => false
    try {
        Hotkey(HotkeyBindName(hk), __HK_Dummy, "On")
        Hotkey(HotkeyBindName(hk), "Off")
        HotIf
        return true
    } catch {
        HotIf
        return false
    }
}

__HK_Dummy(*) {
}
