#Requires AutoHotkey v2.0+
#SingleInstance Force
#Include "Modules\AppState.ahk"
#Include "Modules\SendAdapters.ahk"
#Include "Modules\HotkeyHelpers.ahk"

SetWorkingDir A_ScriptDir
CoordMode "Mouse", "Screen"
InstallKeybdHook()
; optional:
InstallMouseHook()

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

dropRunningD := false
dropAbortD := false
resumeIndexD := 0
resumeStampD := 0
resumeWindowMsD := 3000
dropIndexD := 0

ClickSpamEnabled := 1
DropEnabled := 1
ClickSpamDelayMs := 10
DropperDelayMs := 10
ClickSpamHK_Left := "F1"
ClickSpamHK_Right := "F2"
DropHotkeyDefault := "F3"
ClickSpamRunningL := false
ClickSpamRunningR := false
DropperRunning := false
DropHotkey := DropHotkeyDefault


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

CbDropEnabled := 0
CbClickSpamEnabled := 0

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
ApplyDropperHotkeyState()
ApplyClickSpamHotkeyState()

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
    global DefaultConfigFile, SpamHotkeyDefault, MinKeys, MaxKeys, KeyEnabled, KeyName, KeyDelay, DropHotkeyDefault

    if FileExist(DefaultConfigFile)
        return

    ; Minimal template values (do NOT enable keys by default)
    IniWrite(DefaultConfigFile, DefaultConfigFile, "App", "LastProfile")
	IniWrite("Input", DefaultConfigFile, "App", "KeySendMode")
	IniWrite("Event", DefaultConfigFile, "App", "MouseSendMode")
    IniWrite(SpamHotkeyDefault, DefaultConfigFile, "Spam Key", "Hotkey")
    IniWrite(MinKeys, DefaultConfigFile, "Spam Key", "KeyCount")
	IniWrite(1, DefaultConfigFile, "Dropper", "Enabled")
	IniWrite(1, DefaultConfigFile, "ClickSpam", "Enabled")
	IniWrite(DropHotkeyDefault, DefaultConfigFile, "Dropper", "Hotkey")
	
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
	global CbDropEnabled, CbClickSpamEnabled
	
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
		CapBtn[i].OnEvent("Click", CaptureKey.Bind(i))

		EdKeyName[i] := MainGui.Add("Edit", "x" KeyX " y" y2 " w80 ReadOnly -Tabstop")
		EdKeyDelay[i] := MainGui.Add("Edit", "x" DelayX " y" y2 " w80")
		CbKeyEnabled[i] := MainGui.Add("CheckBox", "x" OnX " y" y " w25")

		; Events NACH dem Erzeugen der Controls
		CbKeyEnabled[i].OnEvent("Click", KeyRowEnabled_Changed.Bind(i))
		EdKeyDelay[i].OnEvent("LoseFocus", KeyRowDelay_LoseFocus.Bind(i))
	}

    BtnAddKey := MainGui.Add("Button", "x25 y205 w130 h" BtnH, "Add key")
    BtnAddKey.OnEvent("Click", (*) => AddKeyRow())

    BtnRemoveKey := MainGui.Add("Button", "x165 y205 w130 h" BtnH, "Remove key")
    BtnRemoveKey.OnEvent("Click", (*) => RemoveKeyRow())

	; ---- Settings group ----
	GrpSettings := MainGui.Add("GroupBox", "x" SettingsX " y" SettingsY " w" SettingsW " h196", "Settings")

	sx := SettingsX + 15          ; inner padding
	sw := SettingsW - 25

	; Hotkey row
	LnkHotkeyLabel := MainGui.Add("Link", "x" sx " y35 w70", '<a href="' KeyListURL '">Hotkey:</a>')
	EdHotkey := MainGui.Add("Edit", "x" (sx+70) " y33 w105")
	BtnPickHotkey := MainGui.Add("Button", "x" (sx+180) " y33 w55 h22", "Pick...")
	BtnPickHotkey.OnEvent("Click", (*) => SetHotkeyCapture())

	; --- Align feature rows to EdHotkey column ---
	EdHotkey.GetPos(&hx, &hy, &hw, &hh)  ; take x from the Hotkey edit [web:420]
	xEnable := hx
	xText   := hx + 32                  ; gap after checkbox
	wEnable := 32                        ; IMPORTANT: not too small, else checkbox gets clipped
	wText   := (SettingsX + SettingsW - 15) - xText

	MainGui.Add("Text", "x" sx " y62 w70", "Enabled")

	; Checkbox-Reihe 1
	CbClickSpamEnabled := MainGui.Add("CheckBox", "x" xEnable " y60 w" wEnable " h20", "")
	CbClickSpamEnabled.OnEvent("Click", ClickSpamEnabled_Changed)

	LblClick := MainGui.Add("Text", "x" xText " y62 w" wText, "Spam Clicks (F1/F2)")
	LblClick.OnEvent("Click", (*) => (
		CbClickSpamEnabled.Value := (CbClickSpamEnabled.Value ? 0 : 1),
		ClickSpamEnabled_Changed(CbClickSpamEnabled)
	))
	
	; Checkbox-Reihe 2
	CbDropEnabled := MainGui.Add("CheckBox", "x" xEnable " y84 w" wEnable " h20", "")
	CbDropEnabled.OnEvent("Click", DropEnabled_Changed)

	LblDrop := MainGui.Add("Text", "x" xText " y86 w" wText, "Item Drop (F3)")
	LblDrop.OnEvent("Click", (*) => (
		CbDropEnabled.Value := (CbDropEnabled.Value ? 0 : 1),
		DropEnabled_Changed(CbDropEnabled)
	))

	; Optional separator line
	MainGui.Add("Text", "x" sx " y114 w" sw " 0x10")

	; Profile fields
	MainGui.Add("Text", "x" sx " y125 w70", "Current:")
	EdCurrentProfile := MainGui.Add("Edit", "x" (sx+70) " y123 w" (sw-70) " ReadOnly -Tabstop")

	MainGui.Add("Text", "x" sx " y153 w70", "New name:")
	EdNewProfileName := MainGui.Add("Edit", "x" (sx+70) " y151 w" (sw-70))

	; Buttons (Y wird später von UpdateLayout gesetzt)
	BtnSaveAs := MainGui.Add("Button", "x" sx " y0 w" sw " h" BtnH, "Save As...")
	BtnSaveAs.OnEvent("Click", (*) => SaveProfileAs())

	BtnLoad := MainGui.Add("Button", "x" sx " y0 w" sw " h" BtnH, "Load...")
	BtnLoad.OnEvent("Click", (*) => LoadProfileFromDialog())

	BtnSave := MainGui.Add("Button", "x" sx " y0 w" Floor((sw-8)/2) " h" BtnH, "Save")
	BtnSave.OnEvent("Click", (*) => SaveCurrentProfile())

	BtnExit := MainGui.Add("Button", "x" (sx + Floor((sw-8)/2) + 8) " y0 w" Floor((sw-8)/2) " h" BtnH, "Exit")
	BtnExit.OnEvent("Click", (*) => ExitApp())
}

GuiSize(guiObj, minMax, width, height) {
    ; minMax = -1 => minimized
    if (minMax = -1)
        return ; HideMainGui() to minimize to tray
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
	global __GuiSync
    __GuiSync := true
    global CurrentConfigFile, SpamHotkey, KeyCount, MinKeys, MaxKeys
    global KeyEnabled, KeyName, KeyDelay
    global EdCurrentProfile, EdHotkey, EdKeyName, EdKeyDelay, CbKeyEnabled
    global CapBtn, BtnAddKey, BtnRemoveKey
    global CbDropEnabled, CbClickSpamEnabled, DropEnabled, ClickSpamEnabled

    SplitPath(CurrentConfigFile, &cfgName)

    EdCurrentProfile.Value := cfgName
    EdHotkey.Value := SpamHotkey

    CbDropEnabled.Value := DropEnabled
    CbClickSpamEnabled.Value := ClickSpamEnabled
	
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
	__GuiSync := false
}

UpdateLayout() {
    global MainGui, GuiVisible
    global KeysY, RowsYStart, RowH, ButtonsGap, BtnH, BottomPad
    global BtnAddKey, BtnRemoveKey
    global BtnSaveAs, BtnLoad, BtnSave, BtnExit
    global GrpKeys, GrpSettings
    global EdNewProfileName, KeyCount

    ; Linke Seite: abhängig von KeyCount
    yButtons := RowsYStart + KeyCount * RowH + ButtonsGap

    btnStep := BtnH + 6
    ySaveAs := yButtons - 2 * btnStep
    yLoad   := yButtons - 1 * btnStep

    ; Mindest-Y für SaveAs: unter "New name" + Luft
    EdNewProfileName.GetPos(&nx, &ny, &nw, &nh)
    minSaveAsY := ny + nh + 14

    if (ySaveAs < minSaveAsY) {
        delta := minSaveAsY - ySaveAs
        ySaveAs  += delta
        yLoad    += delta
        yButtons += delta
    }

    ; Links: Add/Remove
    MoveCtlY(BtnAddKey, yButtons)
    MoveCtlY(BtnRemoveKey, yButtons)

    ; Rechts: SaveAs/Load/Save/Exit
    MoveCtlY(BtnSaveAs, ySaveAs)
    MoveCtlY(BtnLoad,   yLoad)
    MoveCtlY(BtnSave,   yButtons)
    MoveCtlY(BtnExit,   yButtons)

    groupH := (yButtons + BtnH + BottomPad) - KeysY

    ResizeCtlH(GrpKeys, groupH)
    ResizeCtlH(GrpSettings, groupH)

    winH := KeysY + groupH + 12
    MainGui.Show((GuiVisible ? "" : "Hide ") "h" winH)
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
    ReadGuiToVars()
    if (KeyCount >= MaxKeys)
        return
    KeyCount += 1
    UpdateGuiFromVars()
}

RemoveKeyRow() {
    global KeyCount, MinKeys, KeyEnabled, KeyName, KeyDelay
    ReadGuiToVars()
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
	DisableClickSpamHotkeys() 
	
    hk := CaptureHotkeyHybrid_OnKeyDown(7000)

    ; restore
    EnableSpamHotkey()
	EnableClickSpamHotkeys()
	
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

KeyToSendToken(key) {
    ; 1 Zeichen (und kein Send-Sonderzeichen) -> direkt.
    ; Alles andere (F1, Tab, Space, etc.) -> in {}.
    if (StrLen(key) = 1 && !InStr("^!+#{}", key))
        return key
    return "{" key "}"
}

CaptureKey(row, *) {
    global SpamHotkey, __cap_done, __cap_key, __cap_mods

    DisableSpamHotkey()
	DisableClickSpamHotkeys()
	
    __cap_done := false
    __cap_key := ""
    __cap_mods := ""

    ; Mouse-Buttons, die viele Handheld-Backbuttons emulieren
    mouseBtns := ["XButton2", "XButton1", "MButton", "RButton", "LButton"]

    ToolTip "Press a key or mouse button combo now (Ctrl/Alt/Shift/Win + Key)..."

    ih := InputHook()
    ih.KeyOpt("{All}", "NS")     ; Notify + Suppress (Keyboard)
    ih.OnKeyDown := __Row_OnKeyDown
    ih.Start()

    timeoutMs := 7000
    start := A_TickCount
    captured := ""

    while (A_TickCount - start < timeoutMs) {

        ; --- Mouse buttons: per polling erfassen (InputHook deckt Mouse oft nicht ab) ---
        for b in mouseBtns {
            if GetKeyState(b, "P") {
                captured := GetModsFromKeyState() KeyToSendToken(b) ; z.B. ^{XButton1}
                goto __done
            }
        }

        ; --- Keyboard: kommt aus InputHook callback ---
        if (__cap_done) {
            captured := __cap_mods KeyToSendToken(__cap_key)        ; z.B. ^+{F8} oder ^a
            goto __done
        }

        Sleep 10
    }

__done:
    ih.Stop()
    ToolTip
    EnableSpamHotkey()
	EnableClickSpamHotkeys()

    if (captured != "")
        SetRowKey(row, captured)
}


__Row_OnKeyDown(ih, vk, sc) {
    global __cap_done, __cap_key, __cap_mods

    key := GetKeyName(Format("vk{:X}sc{:X}", vk, sc))

    ; reine Modifier nicht als "Final Key"
    if (key = "LShift" || key = "RShift"
     || key = "LControl" || key = "RControl"
     || key = "LAlt" || key = "RAlt"
     || key = "LWin" || key = "RWin")
        return

    __cap_mods := GetModsFromKeyState()
    __cap_key := key
    __cap_done := true
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
    DisableClickSpamHotkeys()          ; optional, um beim Umschalten Ruhe zu haben
    DisableDropperHotkey()             ; optional

    CurrentConfigFile := newConfig
    LoadConfigFromIni()

    ApplyDropperHotkeyState()          ; schaltet F3 je nach DropEnabled
    ApplyClickSpamHotkeyState()        ; schaltet F1/F2 je nach ClickSpamEnabled

    RememberLastProfile(CurrentConfigFile, DefaultConfigFile)
    UpdateGuiFromVars()
    UpdateWindowTitle()
}

KeyRowEnabled_Changed(row, ctrl, *) {
    global __GuiSync, KeyEnabled
    if __GuiSync
        return
    KeyEnabled[row] := ctrl.Value ? 1 : 0
}

KeyRowDelay_LoseFocus(row, ctrl, *) {
    global __GuiSync, KeyDelay
    if __GuiSync
        return
    v := Trim(ctrl.Value)
    if RegExMatch(v, "^\d+$") && Integer(v) >= 1
        KeyDelay[row] := Integer(v)
    else
        ctrl.Value := KeyDelay[row]
}

DropEnabled_Changed(ctrl, *) {
    global DropEnabled
    DropEnabled := ctrl.Value ? 1 : 0
    ApplyDropperHotkeyState()
}

ClickSpamEnabled_Changed(ctrl, *) {
    global ClickSpamEnabled
    ClickSpamEnabled := ctrl.Value ? 1 : 0
    ApplyClickSpamHotkeyState()
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
    global DropEnabled, DropHotkeyDefault, DropHotkey
    global x1D, y1D, x2D, y2D, dxD, dyD
	global App
	
    if !FileExist(CurrentConfigFile)
        return

	App.Options["KeySendMode"]   := IniRead(CurrentConfigFile, "App", "KeySendMode", "Input")
	App.Options["MouseSendMode"] := IniRead(CurrentConfigFile, "App", "MouseSendMode", "Event")

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
	
	DropEnabled := IntegerOr(IniRead(CurrentConfigFile, "Dropper", "Enabled", 1), 1)

	tmpDH := IniRead(CurrentConfigFile, "Dropper", "Hotkey", DropHotkeyDefault)
	DropHotkey := (tmpDH != "" && IsValidHotkey(tmpDH)) ? tmpDH : DropHotkeyDefault
	ClickSpamEnabled := IntegerOr(IniRead(CurrentConfigFile, "ClickSpam", "Enabled", 1), 1)

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
	global App
	
	IniWrite(SpamHotkey, CurrentConfigFile, "Spam Key", "Hotkey")
	IniWrite(App.Options["KeySendMode"],   CurrentConfigFile, "App", "KeySendMode")
	IniWrite(App.Options["MouseSendMode"], CurrentConfigFile, "App", "MouseSendMode")
    IniWrite(KeyCount, CurrentConfigFile, "Spam Key", "KeyCount")
	IniWrite(DropEnabled, CurrentConfigFile, "Dropper", "Enabled")
	IniWrite(DropHotkey, CurrentConfigFile, "Dropper", "Hotkey")
	IniWrite(ClickSpamEnabled, CurrentConfigFile, "ClickSpam", "Enabled")

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
DropHotkeyBindName(hk) {
    hk := Trim(hk)
    if (hk = "")
        return hk
    ; Wildcard: fire even if extra modifiers (e.g. Ctrl) are held. [web:181][web:79]
    if (SubStr(hk, 1, 1) = "*")
        return hk
    return "*" hk
}

BindDropperHotkey() {
    global DropHotkey
    hk := DropHotkeyBindName(DropHotkey)     ; liefert i.d.R. "*F3" [file:746]
    try Hotkey(hk,        Dropper_Down, "On")
    try Hotkey(hk " up",  Dropper_Up,   "On")  ; "up" beim Loslassen [web:79]
}

DisableDropperHotkey() {
    global DropHotkey
    hk := DropHotkeyBindName(DropHotkey)
    try Hotkey(hk,       "Off")
    try Hotkey(hk " up", "Off")
}

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

ApplyDropperHotkeyState() {
    global DropEnabled
	if (DropEnabled) {
		BindDropperHotkey()                ; creates/enables F3 + F3 up
	} else {
		DisableDropperHotkey()             ; disables F3 + F3 up
	}
}

ApplyClickSpamHotkeyState() {
    global ClickSpamEnabled
    if (ClickSpamEnabled) {
        EnableClickSpamHotkeys()           ; F1/F2
    } else {
        DisableClickSpamHotkeys()          ; F1/F2 off
    }
}

ClickSpamBindName(hk) {
    hk := Trim(hk)
    if (hk = "")
        return hk
    return (SubStr(hk, 1, 1) = "*") ? hk : "*" hk   ; wildcard ignores extra modifiers [web:79][web:181]
}

ClickSpam_Left_Down(*) {
    global ClickSpamRunningL, ClickSpamDelayMs, ClickSpamHK_Left
    if (ClickSpamRunningL)
        return
    ClickSpamRunningL := true
    while ClickSpamRunningL && GetKeyState(ClickSpamHK_Left, "P") {
        App_Click()
        Sleep ClickSpamDelayMs
    }
    ClickSpamRunningL := false
}

ClickSpam_Left_Up(*) {
    global ClickSpamRunningL
    ClickSpamRunningL := false
}

ClickSpam_Right_Down(*) {
    global ClickSpamRunningR, ClickSpamDelayMs, ClickSpamHK_Right
    if (ClickSpamRunningR)
        return
    ClickSpamRunningR := true
    while ClickSpamRunningR && GetKeyState(ClickSpamHK_Right, "P") {
        App_Click(, , "Right")
        Sleep ClickSpamDelayMs
    }
    ClickSpamRunningR := false
}

ClickSpam_Right_Up(*) {
    global ClickSpamRunningR
    ClickSpamRunningR := false
}

BindClickSpamHotkeys() {
    global ClickSpamEnabled, ClickSpamHK_Left, ClickSpamHK_Right
    if (!ClickSpamEnabled)
        return

    ; Down starts
    Hotkey(ClickSpamBindName(ClickSpamHK_Left),  ClickSpam_Left_Down,  "On")
    Hotkey(ClickSpamBindName(ClickSpamHK_Right), ClickSpam_Right_Down, "On")

    ; Up stops (note the " up" suffix)
    Hotkey(ClickSpamBindName(ClickSpamHK_Left)  " up",  ClickSpam_Left_Up,  "On")
    Hotkey(ClickSpamBindName(ClickSpamHK_Right) " up",  ClickSpam_Right_Up, "On")
}


DisableClickSpamHotkeys() {
    global ClickSpamHK_Left, ClickSpamHK_Right
    try Hotkey(ClickSpamBindName(ClickSpamHK_Left),        "Off")
    try Hotkey(ClickSpamBindName(ClickSpamHK_Left)  " up", "Off")
    try Hotkey(ClickSpamBindName(ClickSpamHK_Right),       "Off")
    try Hotkey(ClickSpamBindName(ClickSpamHK_Right) " up", "Off")
}

EnableClickSpamHotkeys() {
    BindClickSpamHotkeys()
}

ToggleSpam(*) {
    global Toggle, KeyCount, KeyEnabled, KeyName, KeyDelay, TimerFns, TimerActive

    ReadGuiToVars()

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
    k := Trim(KeyName[i])
    if (k = "")
        return

    if (InStr(k, "^") || InStr(k, "!") || InStr(k, "+") || InStr(k, "#") || InStr(k, "{"))
        App_SendKeys("{Blind}" k)
    else
        App_SendKeys("{Blind}{" k "}")
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

Dropper_Down(*) {
    global DropEnabled, DropperRunning, DropperDelayMs
    if (!DropEnabled)
        return
    if (DropperRunning)
        return

    DropperRunning := true
    App_SendKeys("{Ctrl down}")
    try {
        while DropperRunning && GetKeyState("LButton", "P") = false { ; optional safety
            App_Click()               ; left click at current mouse position
            Sleep DropperDelayMs
        }
    } finally {
        App_SendKeys("{Ctrl up}")
        DropperRunning := false
    }
}

Dropper_Up(*) {
    global DropperRunning
    DropperRunning := false
}

