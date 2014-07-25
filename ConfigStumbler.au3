;-----------------------------------
$Program_Name = "ConfigStumbler"
$Program_Version = "0.6"
$Last_Modified = "08/15/2010"
;-----------------------------------
Opt("GUIOnEventMode", 1);Change to OnEvent mode
Opt("TrayIconHide", 1);Hide icon in system tray
Opt("GUIResizeMode", 802)
#include <ButtonConstants.au3>
#include <GUIConstantsEx.au3>
#include <ListViewConstants.au3>
#include <StaticConstants.au3>
#include <WindowsConstants.au3>
#include <GuiListView.au3>
#include <String.au3>
#include <SQLite.au3>

Dim $settings = @ScriptDir & '\settings.ini'
Dim $ConfigID = 0
Dim $DBhndl
Dim $UDPsocket
Dim $UDPport = 68

Dim $DefaultIntMenuID = '-1'
Dim $Scan = 0
Dim $DocsisDecoder = 0
Dim $AutoDownloadConfigs = IniRead($settings, 'Settings', 'AutoDownloadConfigs', "1")
Dim $AutoDeleteConfigs = IniRead($settings, 'Settings', 'AutoDeleteConfigs', "0")
Dim $DefaultIP = IniRead($settings, 'Settings', 'DefaultIP', "127.0.0.1")
Dim $tftp_exe = @ScriptDir & '\tftp.exe'
Dim $DocsisEXE = @ScriptDir & '\docsis.exe'
Dim $logfile = @ScriptDir & '\log.txt'
Dim $configfile = @ScriptDir & '\configs.txt'
Dim $TmpDir = @ScriptDir & '\temp\'
Dim $ConfDir = @ScriptDir & '\configs\'


FileDelete($logfile)
FileDelete($configfile)

$fldatetimestamp = StringFormat("%04i", @YEAR) & '-' & StringFormat("%02i", @MON) & '-' & StringFormat("%02i", @MDAY) & ' ' & @HOUR & '-' & @MIN & '-' & @SEC
$DB = $TmpDir & $fldatetimestamp & '.SDB'
ConsoleWrite($DB & @CRLF)
_SetUpDbTables($DB)

$ConfigStumbler = GUICreate($Program_Name & ' ' & $Program_Version, 443, 250, -1, -1, BitOR($WS_OVERLAPPEDWINDOW, $WS_CLIPSIBLINGS))

$FileMenu = GUICtrlCreateMenu("File")
$FileSave = GUICtrlCreateMenuItem("Save", $FileMenu)
$FileImportLog = GUICtrlCreateMenuItem("Import Log.txt", $FileMenu)
$FileExit = GUICtrlCreateMenuItem("Exit", $FileMenu)
$EditMenu = GUICtrlCreateMenu("Edit")
$EditCopyMenu = GUICtrlCreateMenu("Copy", $EditMenu)
$EditCopyMac = GUICtrlCreateMenuItem("Mac Address", $EditCopyMenu)
$EditCopyClient = GUICtrlCreateMenuItem("Client IP", $EditCopyMenu)
$EditCopyTftp = GUICtrlCreateMenuItem("Tftp Server", $EditCopyMenu)
$EditCopyConfigName = GUICtrlCreateMenuItem("Config Name", $EditCopyMenu)
$EditCopyConfigPath = GUICtrlCreateMenuItem("Config Path", $EditCopyMenu)
$EditShowConfig = GUICtrlCreateMenuItem("View Selected Config", $EditMenu)
$InterfaceMenu = GUICtrlCreateMenu("Interface")

;Get Local IPs
Dim $FoundIP = 0
Dim $InterfaceMenuID_Array[1]
Dim $InterfaceMenuIP_Array[1]
$wbemFlagReturnImmediately = 0x10
$wbemFlagForwardOnly = 0x20
$colItems = ""
$strComputer = "localhost"
$objWMIService = ObjGet("winmgmts:\\" & $strComputer & "\root\CIMV2")
$colItems = $objWMIService.ExecQuery("SELECT * FROM Win32_NetworkAdapterConfiguration", "WQL", $wbemFlagReturnImmediately + $wbemFlagForwardOnly)
If IsObj($colItems) Then
	For $objItem In $colItems
		$ip = $objItem.IPAddress(0)
		$ip = StringStripWS($ip, 8)
		If $ip <> "" Then
			$menuid = GUICtrlCreateMenuItem($ip, $InterfaceMenu)
			GUICtrlSetOnEvent($menuid, '_IPchanged')
			_ArrayAdd($InterfaceMenuID_Array, $menuid)
			_ArrayAdd($InterfaceMenuIP_Array, $ip)
			$InterfaceMenuID_Array[0] = UBound($InterfaceMenuID_Array) - 1
			$InterfaceMenuIP_Array[0] = UBound($InterfaceMenuIP_Array) - 1
			If $ip = $DefaultIP Then
				$FoundIP = 1
				$DefaultIntMenuID = $menuid
				GUICtrlSetState($menuid, $GUI_CHECKED)
			EndIf
		EndIf
	Next
EndIf
If $FoundIP = 0 And $InterfaceMenuID_Array[0] <> 0 Then
	$DefaultIP = $InterfaceMenuIP_Array[1]
	$DefaultIntMenuID = $InterfaceMenuID_Array[1]
	GUICtrlSetState($DefaultIntMenuID, $GUI_CHECKED)
EndIf
;End Get Local IPs
$ScanButton = GUICtrlCreateButton("Scan", 8, 8, 81, 33, $WS_GROUP)
$messagebox = GUICtrlCreateLabel("", 8, 45, 328, 15, $SS_LEFT)

$ConfigDownload = GUICtrlCreateCheckbox("Automatically download config from tftp (Required for Info)", 104, 8, 297, 17)
If $AutoDownloadConfigs = 1 Then GUICtrlSetState($ConfigDownload, $GUI_CHECKED)
$ConfigDelete = GUICtrlCreateCheckbox("Delete config when done", 104, 24, 297, 17)
If $AutoDeleteConfigs = 1 Then GUICtrlSetState($ConfigDelete, $GUI_CHECKED)
GUICtrlSetState ($ConfigDelete, $GUI_DISABLE) ;Disable for now since the file does not seem to be deleting

;GUICtrlSetResizing ($messagebox, $GUI_DOCKBORDERS)
$ConfList = GUICtrlCreateListView("#|Mac|Client|TFTP Server|Config|Info|Times seen", 0, 65, 441, 165, $LVS_REPORT + $LVS_SINGLESEL, $LVS_EX_HEADERDRAGDROP + $LVS_EX_GRIDLINES + $LVS_EX_FULLROWSELECT)
GUICtrlSendMsg(-1, $LVM_SETCOLUMNWIDTH, 0, 30)
GUICtrlSendMsg(-1, $LVM_SETCOLUMNWIDTH, 1, 110)
GUICtrlSendMsg(-1, $LVM_SETCOLUMNWIDTH, 2, 95)
GUICtrlSendMsg(-1, $LVM_SETCOLUMNWIDTH, 3, 95)
GUICtrlSendMsg(-1, $LVM_SETCOLUMNWIDTH, 4, 175)
GUICtrlSendMsg(-1, $LVM_SETCOLUMNWIDTH, 5, 375)
GUICtrlSendMsg(-1, $LVM_SETCOLUMNWIDTH, 6, 50)
GUICtrlSetResizing($ConfList, $GUI_DOCKBORDERS)

GUISetOnEvent($GUI_EVENT_CLOSE, '_Exit')
GUICtrlSetOnEvent($FileSave, '_ExportList')
GUICtrlSetOnEvent($FileImportLog, '_LoadLogTXT')
GUICtrlSetOnEvent($FileExit, '_Exit')

GUICtrlSetOnEvent($EditCopyMac, '_CopyMac')
GUICtrlSetOnEvent($EditCopyClient, '_CopyClient')
GUICtrlSetOnEvent($EditCopyTftp, '_CopyTftp')
GUICtrlSetOnEvent($EditCopyConfigName, '_CopyConfigName')
GUICtrlSetOnEvent($EditCopyConfigPath, '_CopyConfigPath')
GUICtrlSetOnEvent($EditShowConfig, '_ShowDecodedConfig')

GUICtrlSetOnEvent($ConfigDownload, '_ToggleConfigDownload')
GUICtrlSetOnEvent($ConfigDelete, '_ToggleConfigDelete')
GUICtrlSetOnEvent($ScanButton, '_ToggleScanning')

;Set Window Size
$a = WinGetPos($ConfigStumbler);Get window current position
Dim $State = IniRead($settings, 'WindowPositions', 'State', "Window");Get last window position from the ini file
Dim $Position = IniRead($settings, 'WindowPositions', 'Position', $a[0] & ',' & $a[1] & ',' & $a[2] & ',' & $a[3])
$b = StringSplit($Position, ",")
If $State = "Maximized" Then
	WinSetState($ConfigStumbler, "", @SW_MAXIMIZE)
Else
	;Split ini posion string
	WinMove($ConfigStumbler, "", $b[1], $b[2], $b[3], $b[4]);Resize window to ini value
EndIf

GUISetState(@SW_SHOW)

;Program Running Loop
While 1
	$ldatetimestamp = StringFormat("%04i", @YEAR) & '/' & StringFormat("%02i", @MON) & '/' & StringFormat("%02i", @MDAY) & ' ' & @HOUR & ':' & @MIN & ':' & @SEC
	If $Scan = 1 Then _ReadUDPdata()
	Sleep(10)
WEnd

;-----------------
;Functions
;-----------------

Func _SetUpDbTables($dbfile)
	_SQLite_Startup()
	$DBhndl = _SQLite_Open($dbfile)
	_SQLite_Exec($DBhndl, "pragma synchronous=0");Speed vs Data security. Speed Wins for now.
	_SQLite_Exec($DBhndl, "CREATE TABLE CONFIGDATA (configid,line,config,client,tftp,mac,info,times,configtxt)")
EndFunc   ;==>_SetUpDbTables

Func _ReadUDPdata()
	$udpdata = UDPRecv($UDPsocket, 500)
	If $udpdata <> "" Then
		FileWrite($logfile, $udpdata & @CRLF)
		_CheckData($udpdata)
	EndIf
EndFunc   ;==>_ReadUDPdata

Func _CheckData($data)
	ConsoleWrite(BinaryLen($data) & 'bytes ' & StringLen($data) & 'chars - ' & $data & @CRLF)
	GUICtrlSetData($messagebox,'UDP Data: ' & BinaryLen($data) & ' bytes (' & $ldatetimestamp & ')')
	;Get data from UDP Hex String
	If StringLen($data) >= "640" Then
		GUICtrlSetData($messagebox,'Checking Data: ' & BinaryLen($data) & ' bytes (' & $ldatetimestamp & ')')
		;Get Modem Mac Address
		$mac = StringMid($data, 59, 12)
		;Get Client IP
		$clienthex = StringMid($data, 35, 8)
		$client = Asc(_HexToString('0x' & StringMid($clienthex, 1, 2))) & '.' & Asc(_HexToString('0x' & StringMid($clienthex, 3, 2))) & '.' & Asc(_HexToString('0x' & StringMid($clienthex, 5, 2))) & '.' & Asc(_HexToString('0x' & StringMid($clienthex, 7, 2)))
		;Get TFTP IP
		$tftphex = StringMid($data, 43, 8)
		$tftp = Asc(_HexToString('0x' & StringMid($tftphex, 1, 2))) & '.' & Asc(_HexToString('0x' & StringMid($tftphex, 3, 2))) & '.' & Asc(_HexToString('0x' & StringMid($tftphex, 5, 2))) & '.' & Asc(_HexToString('0x' & StringMid($tftphex, 7, 2)))
		;Get Config Name
		$confighex = StringMid($data, 219, 256)
		While StringRight($confighex, 2) = "00" ;Strip off tailing 00s
			$confighex = StringTrimRight($confighex, 2)
		Wend
		$config = _HexToString($confighex)
		_SaveData($config, $client, $tftp, $mac)
	EndIf
EndFunc   ;==>_CheckData

Func _SaveData($config, $client, $tftp, $mac, $infostring = "")
	$decode_line = ""
	$mac = StringMid($mac, 1, 2) & ":" & StringMid($mac, 3, 2) & ":" & StringMid($mac, 5, 2) & ":" & StringMid($mac, 7, 2) & ":" & StringMid($mac, 9, 2) & ":" & StringMid($mac, 11, 2)
	ConsoleWrite(@CRLF & '----------------------------------------------------------' & @CRLF)
	If $AutoDownloadConfigs = 1 Then ;Download Config File
		$config_destname = StringRegExpReplace($config, '[/\\:?"><!]', '_') & '.cfg'
		$config_destfile = $ConfDir & $config_destname
		ConsoleWrite($config_destfile & @CRLF)
		$command = '"' & $tftp_exe & '" -i ' & $tftp & ' GET ' & $config & ' "' & $config_destfile & '"'
		ConsoleWrite($command & @CRLF)
		RunWait($command, @WindowsDir, @SW_HIDE)
		If FileExists($config_destfile) Then ;Use DOCSIS.exe to decode config.
			;Read data from console output
			$decode_output = Run(@ComSpec & ' /c "' & $DocsisEXE & '" -d ' & FileGetShortName($config_destfile), '', @SW_HIDE, 2)
			ConsoleWrite(@ComSpec & ' /c "' & $DocsisEXE & '" -d ' & FileGetShortName($config_destfile) & @CRLF)
			$timeout = TimerInit()
			While TimerDiff($timeout) <= 30000
				$decode_line &= StdoutRead($decode_output)
				If @error Then ExitLoop
			WEnd
			;Split config output data by ;
			$configdataarr = StringSplit($decode_line, ";")
			;Pull wanted data into the info string
			For $gd = 1 To $configdataarr[0]
				If StringInStr($configdataarr[$gd], "NetworkAccess ") Then
					$naarr = StringSplit($configdataarr[$gd], "NetworkAccess ", 1)
					If $infostring <> "" Then $infostring &= ' - '
					;_ArrayDisplay($naarr)
					$infostring &= 'NetworkAccess:' & $naarr[2]
				ElseIf StringInStr($configdataarr[$gd], "GlobalPrivacyEnable ") Then
					$gparr = StringSplit($configdataarr[$gd], "GlobalPrivacyEnable ", 1)
					If $infostring <> "" Then $infostring &= ' - '
					;_ArrayDisplay($gparr)
					$infostring &= 'GlobalPrivacyEnable:' & $gparr[2]
				ElseIf StringInStr($configdataarr[$gd], "MaxCPE ") Then
					$cpearr = StringSplit($configdataarr[$gd], "MaxCPE ", 1)
					If $infostring <> "" Then $infostring &= ' - '
					;_ArrayDisplay($cpearr)
					$infostring &= 'MaxCPE:' & $cpearr[2]
				ElseIf StringInStr($configdataarr[$gd], "ServiceClassName ") Then
					$scna = StringSplit($configdataarr[$gd], "ServiceClassName ", 1)
					If $infostring <> "" Then $infostring &= ' - '
					;_ArrayDisplay($scna)
					$infostring &= 'ServiceClassName:' & $scna[2]
				ElseIf StringInStr($configdataarr[$gd], "MaxRateDown ") Then
					$mdrarr = StringSplit($configdataarr[$gd], "MaxRateDown ", 1)
					If $infostring <> "" Then $infostring &= ' - '
					;_ArrayDisplay($mdrarr)
					$infostring &= 'MaxRateDown:' & $mdrarr[2]
				ElseIf StringInStr($configdataarr[$gd], "MaxRateUp ") Then
					$murarr = StringSplit($configdataarr[$gd], "MaxRateUp ", 1)
					If $infostring <> "" Then $infostring &= ' - '
					;_ArrayDisplay($murarr)
					$infostring &= 'MaxRateUp:' & $murarr[2]
				ElseIf StringInStr($configdataarr[$gd], "MaxRateSustained ") Then
					$cpearr = StringSplit($configdataarr[$gd], "MaxRateSustained ", 1)
					If $infostring <> "" Then $infostring &= ' - '
					;_ArrayDisplay($cpearr)
					$infostring &= 'MaxRateSustained:' & $cpearr[2]
				ElseIf StringInStr($configdataarr[$gd], "SnmpMibObject iso.3.6.1.2.1.1.6.0 String ") Then
					$provareaarr = StringSplit($configdataarr[$gd], "SnmpMibObject iso.3.6.1.2.1.1.6.0 String ", 1)
					If $infostring <> "" Then $infostring &= ' - '
					;_ArrayDisplay($provareaarr)
					$infostring &= $provareaarr[2]
				EndIf
			Next
			$infostring = StringReplace($infostring, '"', '')
			If $AutoDeleteConfigs = 1 Then FileDelete($config_destfile)
			ConsoleWrite("Error: " & @error & ' - ' & $AutoDeleteConfigs)
		EndIf
	EndIf
	ConsoleWrite($config & '|' & $client & '|' & $tftp & '|' & $mac & '|' & $infostring & @CRLF)
	_InsertIntoDB($config, $client, $tftp, $mac, $infostring, $decode_line)
	ConsoleWrite('----------------------------------------------------------' & @CRLF)
EndFunc   ;==>_SaveData

Func _InsertIntoDB($config, $client, $tftp, $mac, $infostring, $configtxt)
	ConsoleWrite($configtxt & @CRLF)
	Local $ConfigMatchArray, $iRows, $iColumns, $iRval
	$query = "SELECT configid, line, times FROM CONFIGDATA WHERE mac='" & $mac & "' And client='" & $client & "' And tftp='" & $tftp & "' And config='" & $config & "' limit 1"
	$iRval = _SQLite_GetTable2d($DBhndl, $query, $ConfigMatchArray, $iRows, $iColumns)
	If $iRows = 0 Then ;If config is not found then add it
		$ConfigID += 1
		$ListRow = _GUICtrlListView_InsertItem($ConfList, $ConfigID, -1)
		_ListViewAdd($ListRow, $ConfigID, $mac, $client, $tftp, $config, $infostring, 1)
		$TimesSeen = 1
		$query = "INSERT INTO CONFIGDATA(configid,line,config,client,tftp,mac,info,times,configtxt) VALUES ('" & $ConfigID & "','" & $ListRow & "','" & $config & "','" & $client & "','" & $tftp & "','" & $mac & "','" & $infostring & "','" & $TimesSeen & "','" & $configtxt & "');"
		_SQLite_Exec($DBhndl, $query)
		FileWrite($configfile, $config & '|' & $tftp & '|' & $mac & '|' & $infostring & @CRLF)
	Else
		$FoundConfigID = $ConfigMatchArray[1][0]
		$FoundLine = $ConfigMatchArray[1][1]
		$FoundTimes = $ConfigMatchArray[1][2] + 1 ;Add one to last found number
		_ListViewAdd($FoundLine, "", "", "", "", "", "", $FoundTimes)
		$query = "UPDATE CONFIGDATA SET times='" & $FoundTimes & "' WHERE configid = '" & $FoundConfigID & "'"
		_SQLite_Exec($DBhndl, $query)
		If $infostring <> "" Then
			$query = "UPDATE CONFIGDATA SET info='" & $infostring & "' WHERE configid = '" & $FoundConfigID & "'"
			_SQLite_Exec($DBhndl, $query)
			_ListViewAdd($FoundLine, "", "", "", "", "", $infostring, "")
		EndIf
		If $configtxt <> "" Then
			$query = "UPDATE CONFIGDATA SET configtxt='" & $configtxt & "' WHERE configid = '" & $FoundConfigID & "'"
			_SQLite_Exec($DBhndl, $query)
		EndIf
	EndIf
EndFunc   ;==>_InsertIntoDB

Func _ListViewAdd($line, $Add_CID = '', $Add_mac = '', $Add_client = '', $Add_tftp = '', $Add_config = '', $Add_info = '', $Add_times = '')
	If $Add_CID <> '' Then _GUICtrlListView_SetItemText($ConfList, $line, $Add_CID, 0)
	If $Add_mac <> '' Then _GUICtrlListView_SetItemText($ConfList, $line, $Add_mac, 1)
	If $Add_client <> '' Then _GUICtrlListView_SetItemText($ConfList, $line, $Add_client, 2)
	If $Add_tftp <> '' Then _GUICtrlListView_SetItemText($ConfList, $line, $Add_tftp, 3)
	If $Add_config <> '' Then _GUICtrlListView_SetItemText($ConfList, $line, $Add_config, 4)
	If $Add_info <> '' Then _GUICtrlListView_SetItemText($ConfList, $line, $Add_info, 5)
	If $Add_times <> '' Then _GUICtrlListView_SetItemText($ConfList, $line, $Add_times, 6)
EndFunc   ;==>_ListViewAdd

;---------------------------------------------------------------------------------------
; File Menu Functions
;---------------------------------------------------------------------------------------

Func _ExportList()
	$fldatetimestamp = StringFormat("%04i", @YEAR) & '-' & StringFormat("%02i", @MON) & '-' & StringFormat("%02i", @MDAY) & ' ' & @HOUR & '-' & @MIN & '-' & @SEC
	$file = FileSaveDialog('Save As', '', 'Coma Delimeted File (*.CSV)', '', $fldatetimestamp & '.CSV')
	If @error <> 1 Then
		FileDelete($file)
		FileWriteLine($file, 'Mac Adress,Client IP,TFTP IP,Config,Info,Times Seen')
		Local $ConfigMatchArray, $iRows, $iColumns, $iRval
		$query = "SELECT mac, client, tftp, config, info, times FROM CONFIGDATA"
		$iRval = _SQLite_GetTable2d($DBhndl, $query, $ConfigMatchArray, $iRows, $iColumns)
		If $iRows <> 0 Then ;If Configs found, write to file
			For $ed = 1 To $iRows
				$ExpMac = $ConfigMatchArray[$ed][0]
				$ExpClient = $ConfigMatchArray[$ed][1]
				$ExpTftp = $ConfigMatchArray[$ed][2]
				$ExpConfig = $ConfigMatchArray[$ed][3]
				$ExpInfo = $ConfigMatchArray[$ed][4]
				$ExpTimes = $ConfigMatchArray[$ed][5]
				FileWriteLine($file, $ExpMac & ',' & $ExpClient & ',' & $ExpTftp & ',' & $ExpConfig & ',' & $ExpInfo & ',' & $ExpTimes)
			Next
		EndIf
		GUICtrlSetData($messagebox, "Done saving file")
	EndIf
EndFunc   ;==>_ExportList

Func _LoadLogTXT()
	$logfile = FileOpenDialog('Import log.txt', '', 'Log.txt (*.txt)', 1)
	If Not @error Then
		$logfile = FileOpen($logfile, 0)
		$totallines = 0
		While 1
			FileReadLine($logfile)
			If @error = -1 Then ExitLoop
			$totallines += 1
			ConsoleWrite($totallines & @CRLF)
		WEnd
		For $Load = 1 To $totallines
			$linein = FileReadLine($logfile, $Load);Open Line in file
			$ldatetimestamp = StringFormat("%04i", @YEAR) & '-' & StringFormat("%02i", @MON) & '-' & StringFormat("%02i", @MDAY) & ' ' & @HOUR & ':' & @MIN & ':' & @SEC
			_CheckData($linein)
		Next
		GUICtrlSetData($messagebox, "Done loading file")
	EndIf
EndFunc

Func _Exit()
	If $Scan = 1 Then _ToggleScanning()
	;Get Window Postions
	$a = WinGetPos($ConfigStumbler)
	$winstate = WinGetState($ConfigStumbler, "")
	If BitAND($winstate, 32) Then;Set
		$State = "Maximized"
	Else
		$State = "Window"
		$Position = $a[0] & ',' & $a[1] & ',' & $a[2] & ',' & $a[3]
	EndIf
	IniWrite($settings, 'WindowPositions', 'State', $State)
	IniWrite($settings, 'WindowPositions', 'Position', $Position)
	;End Get Window Postions
	IniWrite($settings, 'Settings', 'DefaultIP', $DefaultIP)
	IniWrite($settings, 'Settings', 'AutoDownloadConfigs', $AutoDownloadConfigs)
	IniWrite($settings, 'Settings', 'AutoDeleteConfigs', $AutoDeleteConfigs)
	_SQLite_Close($DBhndl)
	_SQLite_Shutdown()
	FileDelete($DB)
	Exit
EndFunc   ;==>_Exit

;---------------------------------------------------------------------------------------
; Edit Menu Functions
;---------------------------------------------------------------------------------------

Func _CopyMac()
	$Selected = _GUICtrlListView_GetNextItem($ConfList); find what config is selected in the list. returns -1 is nothing is selected
	If $Selected <> "-1" Then
		Local $ConfigMatchArray, $iRows, $iColumns, $iRval
		$query = "SELECT mac FROM CONFIGDATA WHERE line='" & $Selected & "'"
		$iRval = _SQLite_GetTable2d($DBhndl, $query, $ConfigMatchArray, $iRows, $iColumns)
		If $iRows <> 0 Then ;If Configs found, write to file
			$mac = $ConfigMatchArray[1][0]
			ClipPut($mac)
		EndIf
	Else
		MsgBox(0, "Error", "No config selected")
	EndIf
EndFunc   ;==>_CopyMac

Func _CopyClient()
	$Selected = _GUICtrlListView_GetNextItem($ConfList); find what config is selected in the list. returns -1 is nothing is selected
	If $Selected <> "-1" Then
		Local $ConfigMatchArray, $iRows, $iColumns, $iRval
		$query = "SELECT client FROM CONFIGDATA WHERE line='" & $Selected & "'"
		$iRval = _SQLite_GetTable2d($DBhndl, $query, $ConfigMatchArray, $iRows, $iColumns)
		If $iRows <> 0 Then ;If Configs found, write to file
			$clientip = $ConfigMatchArray[1][0]
			ClipPut($clientip)
		EndIf
	Else
		MsgBox(0, "Error", "No config selected")
	EndIf
EndFunc   ;==>_CopyTftp

Func _CopyTftp()
	$Selected = _GUICtrlListView_GetNextItem($ConfList); find what config is selected in the list. returns -1 is nothing is selected
	If $Selected <> "-1" Then
		Local $ConfigMatchArray, $iRows, $iColumns, $iRval
		$query = "SELECT tftp FROM CONFIGDATA WHERE line='" & $Selected & "'"
		$iRval = _SQLite_GetTable2d($DBhndl, $query, $ConfigMatchArray, $iRows, $iColumns)
		If $iRows <> 0 Then ;If Configs found, write to file
			$tftp = $ConfigMatchArray[1][0]
			ClipPut($tftp)
		EndIf
	Else
		MsgBox(0, "Error", "No config selected")
	EndIf
EndFunc   ;==>_CopyTftp

Func _CopyConfigName()
	$Selected = _GUICtrlListView_GetNextItem($ConfList); find what config is selected in the list. returns -1 is nothing is selected
	If $Selected <> "-1" Then
		Local $ConfigMatchArray, $iRows, $iColumns, $iRval
		$query = "SELECT config FROM CONFIGDATA WHERE line='" & $Selected & "'"
		$iRval = _SQLite_GetTable2d($DBhndl, $query, $ConfigMatchArray, $iRows, $iColumns)
		If $iRows <> 0 Then ;If Configs found, write to file
			$config = $ConfigMatchArray[1][0]
			ClipPut($config)
		EndIf
	Else
		MsgBox(0, "Error", "No config selected")
	EndIf
EndFunc   ;==>_CopyConfigName

Func _CopyConfigPath()
	$Selected = _GUICtrlListView_GetNextItem($ConfList); find what config is selected in the list. returns -1 is nothing is selected
	If $Selected <> "-1" Then
		Local $ConfigMatchArray, $iRows, $iColumns, $iRval
		$query = "SELECT config FROM CONFIGDATA WHERE line='" & $Selected & "'"
		$iRval = _SQLite_GetTable2d($DBhndl, $query, $ConfigMatchArray, $iRows, $iColumns)
		If $iRows <> 0 Then ;If Configs found, write to file
			$configname = StringRegExpReplace($ConfigMatchArray[1][0], '[/\\:?"><!]', '_')
			$configfile = $ConfDir & $configname & '.cfg'
			If FileExists($configfile) Then
				ClipPut($configfile)
				GUICtrlSetData($messagebox, "Copied config location of " & $configname)
			Else
				MsgBox(0, "File not found", $configname & " does not exist ")
			EndIf
		EndIf
	Else
		MsgBox(0, "Error", "No config selected")
	EndIf
EndFunc   ;==>_CopyConfigPath

Func _ShowDecodedConfig()
	$Selected = _GUICtrlListView_GetNextItem($ConfList); find what config is selected in the list. returns -1 is nothing is selected
	If $Selected <> "-1" Then
		Local $ConfigMatchArray, $iRows, $iColumns, $iRval
		$query = "SELECT config, configtxt FROM CONFIGDATA WHERE line='" & $Selected & "'"
		$iRval = _SQLite_GetTable2d($DBhndl, $query, $ConfigMatchArray, $iRows, $iColumns)
		If $iRows <> 0 Then ;If Configs found, write to file
			If WinExists($DocsisDecoder) Then GUIDelete($DocsisDecoder)
			$config = $ConfigMatchArray[1][0]
			$ConfigText = StringReplace($ConfigMatchArray[1][1], ";", ";" & @CRLF)
			$DocsisDecoder = GUICreate($config, 625, 430, -1, -1, BitOR($WS_OVERLAPPEDWINDOW, $WS_CLIPSIBLINGS))
			$Edit = GUICtrlCreateEdit($ConfigText, 8, 5, 609, 420)
			GUISetOnEvent($GUI_EVENT_CLOSE, '_CloseDecodedConfig')
			GUISetState(@SW_SHOW)
		Else
			MsgBox(0, "Error", "Selected config not found...weird...")
		EndIf
	Else
		MsgBox(0, "Error", "No config selected")
	EndIf
EndFunc   ;==>_ShowDecodedConfig

Func _CloseDecodedConfig()
	GUIDelete($DocsisDecoder)
EndFunc   ;==>_CloseActiveWindow

;---------------------------------------------------------------------------------------
; Interface Menu Functions
;---------------------------------------------------------------------------------------

Func _IPchanged()
	$menuid = @GUI_CtrlId
	For $fs = 1 To $InterfaceMenuID_Array[0]
		If $InterfaceMenuID_Array[$fs] = $menuid Then
			$NewIP = $InterfaceMenuIP_Array[$fs]
			If $NewIP <> $DefaultIP Then
				If $DefaultIntMenuID <> '-1' Then GUICtrlSetState($DefaultIntMenuID, $GUI_UNCHECKED)
				$DefaultIP = $NewIP
				$DefaultIntMenuID = $menuid
				GUICtrlSetState($DefaultIntMenuID, $GUI_CHECKED)
			EndIf
		EndIf
	Next
EndFunc   ;==>_IPchanged

;---------------------------------------------------------------------------------------
; Button Functions
;---------------------------------------------------------------------------------------

Func _ToggleScanning()
	If $Scan = 0 Then ;Start Scanning
		UDPStartup()
		$UDPsocket = UDPBind($DefaultIP, $UDPport)
		If @error = 0 Then
			$Scan = 1
			GUICtrlSetData($ScanButton, "Stop")
			GUICtrlSetData($messagebox, "Started - waiting for data")
		Else
			GUICtrlSetData($messagebox, "Error binding to ip")
		EndIf
	Else ;Stop Scanning
		UDPShutdown()
		UDPCloseSocket($UDPsocket)
		$Scan = 0
		GUICtrlSetData($ScanButton, "Scan")
		GUICtrlSetData($messagebox, "Stopped")
	EndIf
EndFunc   ;==>_ToggleScanning

Func _ToggleConfigDownload()
	If $AutoDownloadConfigs = 0 Then
		$AutoDownloadConfigs = 1
		GUICtrlSetState($ConfigDownload, $GUI_CHECKED)
	Else
		$AutoDownloadConfigs = 0
		GUICtrlSetState($ConfigDownload, $GUI_UNCHECKED)
	EndIf
EndFunc

Func _ToggleConfigDelete()
	If $AutoDeleteConfigs = 0 Then
		$AutoDeleteConfigs = 1
		GUICtrlSetState($ConfigDelete, $GUI_CHECKED)
	Else
		$AutoDeleteConfigs = 0
		GUICtrlSetState($ConfigDelete, $GUI_UNCHECKED)
	EndIf
EndFunc