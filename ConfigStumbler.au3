#RequireAdmin
;-----------------------------------
$Program_Name = "ConfigStumbler"
$Program_Version = "0.7"
$Last_Modified = "09/18/2010"
$By = "TheMHC"
;-----------------------------------
Opt("GUIOnEventMode", 1);Change to OnEvent mode
Opt("TrayIconHide", 1);Hide icon in system tray
Opt("GUIResizeMode", 802)
#include <ButtonConstants.au3>
#include <GUIConstantsEx.au3>
#include <EditConstants.au3>
#include <ListViewConstants.au3>
#include <StaticConstants.au3>
#include <WindowsConstants.au3>
#include <GuiListView.au3>
#include <String.au3>
#include <SQLite.au3>
#include <INet.au3>
#include "UDFs\ParseCSV.au3"

;Create Directories
Dim $TmpDir = @ScriptDir & '\temp\'
Dim $ConfDir = @ScriptDir & '\configs\'
Dim $SavefDir = @ScriptDir & '\save\'
DirCreate($TmpDir)
DirCreate($ConfDir)
DirCreate($SavefDir)

Dim $settings = @ScriptDir & '\settings.ini'
Dim $ConfigID = 0
Dim $DBhndl
Dim $UDPsocket
Dim $UDPport = 68

Dim $DefaultIntMenuID = '-1'
Dim $Scan = 0
Dim $DocsisDecoder = 0
Dim $DontAddIfInfoBlank = 0
Dim $AutoDownloadConfigs = IniRead($settings, 'Settings', 'AutoDownloadConfigs', "1")
Dim $OverrideTftp = IniRead($settings, 'Settings', 'OverrideTftp', 0)
Dim $OverrideTftpIP = IniRead($settings, 'Settings', 'OverrideTftpIP', "0.0.0.0")
Dim $DefaultIP = IniRead($settings, 'Settings', 'DefaultIP', "127.0.0.1")
Dim $tftp_exe = @ScriptDir & '\tftp.exe'
Dim $DocsisEXE = @ScriptDir & '\docsis.exe'
Dim $PuttyEXE = @ScriptDir & '\putty.exe'
Dim $logfile = @ScriptDir & '\log.txt'
Dim $configfile = @ScriptDir & '\configs.csv'

Dim $5100InfoGUI, $ModemIP, $TelnetUser, $TelnetPass
Dim $5100teletIP = IniRead($settings, '5100tftp', 'teletIP', "192.168.100.1")
Dim $5100teletUN = IniRead($settings, '5100tftp', 'teletUN', "")
Dim $5100teletPW = IniRead($settings, '5100tftp', 'teletPW', "")
Dim $5100telnetSet = IniRead($settings, '5100tftp', 'telnetSet', 0)

Dim $tmrGUI, $rTftp, $rMacPre, $rMacSuf, $rStartMac, $rEndMac
Dim $startmac = IniRead($settings, 'ScanMacRange', 'startmac', "00:00:00:00:00:00")
Dim $endmac = IniRead($settings, 'ScanMacRange', 'endmac', "00:00:00:00:00:00")
Dim $macpre = IniRead($settings, 'ScanMacRange', 'macpre', "")
Dim $macsuf = IniRead($settings, 'ScanMacRange', 'macsuf', "")
Dim $mactftp = IniRead($settings, 'ScanMacRange', 'mactftp', "")

FileDelete($logfile)
FileDelete($configfile)
FileWrite($configfile, 'Mac Address,Client IP,TFTP IP,Config,Info,Times Seen,configtxt(hex)' & @CRLF)

$fldatetimestamp = StringFormat("%04i", @YEAR) & '-' & StringFormat("%02i", @MON) & '-' & StringFormat("%02i", @MDAY) & ' ' & @HOUR & '-' & @MIN & '-' & @SEC
$DB = $TmpDir & $fldatetimestamp & '.SDB'
_SetUpDbTables($DB)

$ConfigStumbler = GUICreate($Program_Name & ' ' & $Program_Version, 443, 250, -1, -1, BitOR($WS_OVERLAPPEDWINDOW, $WS_CLIPSIBLINGS))

$FileMenu = GUICtrlCreateMenu("File")
$FileSave = GUICtrlCreateMenuItem("Save", $FileMenu)
$FileImportCSV = GUICtrlCreateMenuItem("Import CSV", $FileMenu)
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
$ExtraMenu = GUICtrlCreateMenu("Extra")
$EditTestBprMac = GUICtrlCreateMenuItem("Test mac range", $ExtraMenu)
$SigmaX2Menu = GUICtrlCreateMenu("5100 (Sigma X2)", $ExtraMenu)
$Set5100telnetinfo = GUICtrlCreateMenuItem("Set SB5100 telnet info ", $SigmaX2Menu)
$Set5100selmac = GUICtrlCreateMenuItem("Set SB5100 mac to selected", $SigmaX2Menu)
$Set5100toallmacs = GUICtrlCreateMenuItem("Set SB5100 mac to all macs (timed)", $SigmaX2Menu)

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
$messagebox = GUICtrlCreateLabel("", 8, 45, 500, 15, $SS_LEFT)

$ConfigDownload = GUICtrlCreateCheckbox("Automatically download config from tftp (Required for Info)", 104, 8, 297, 17)
If $AutoDownloadConfigs = 1 Then GUICtrlSetState($ConfigDownload, $GUI_CHECKED)
$OverrideTftpCheck = GUICtrlCreateCheckbox("Override tftp server", 104, 26, 120, 17)
If $OverrideTftp = 1 Then GUICtrlSetState($OverrideTftpCheck, $GUI_CHECKED)
$OverrideTftpIpBox = GUICtrlCreateInput($OverrideTftpIP, 225, 24, 150, 20)


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
GUICtrlSetOnEvent($FileImportCSV, '_LoadCSV')
GUICtrlSetOnEvent($FileImportLog, '_LoadLogTXT')
GUICtrlSetOnEvent($FileExit, '_Exit')

GUICtrlSetOnEvent($EditCopyMac, '_CopyMac')
GUICtrlSetOnEvent($EditCopyClient, '_CopyClient')
GUICtrlSetOnEvent($EditCopyTftp, '_CopyTftp')
GUICtrlSetOnEvent($EditCopyConfigName, '_CopyConfigName')
GUICtrlSetOnEvent($EditCopyConfigPath, '_CopyConfigPath')
GUICtrlSetOnEvent($EditShowConfig, '_ShowDecodedConfig')
GUICtrlSetOnEvent($EditTestBprMac, '_TestMacRangeGUI')

GUICtrlSetOnEvent($ConfigDownload, '_ToggleConfigDownload')
GUICtrlSetOnEvent($OverrideTftpCheck, '_ToggleOverrideTftp')
GUICtrlSetOnEvent($ScanButton, '_ToggleScanning')
GUICtrlSetOnEvent($Set5100telnetinfo, '_Set5100telnetinfo')
GUICtrlSetOnEvent($Set5100selmac, '_Set5100selctedmac')
GUICtrlSetOnEvent($Set5100toallmacs, '_Set5100toallmacs')

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
	GUICtrlSetData($messagebox, 'UDP Data: ' & BinaryLen($data) & ' bytes (' & _GetTime() & ')')
	;Get data from UDP Hex String
	If StringLen($data) >= "640" Then
		GUICtrlSetData($messagebox, 'Checking Data: ' & BinaryLen($data) & ' bytes (' & _GetTime() & ')')
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
		WEnd
		$config = _HexToString($confighex)

		_InsertIntoDB($config, $client, $tftp, $mac)
	EndIf
EndFunc   ;==>_CheckData

Func _InsertIntoDB($config, $client, $tftp, $mac, $infostring = "", $configtxt = "", $TimesSeen = 1, $AddIfBlank = 1)
	Local $Add = 1
	If $OverrideTftp = 1 Then $tftp = GUICtrlRead($OverrideTftpIpBox)
	$mac = StringReplace(StringReplace(StringUpper($mac), ":", ""), "-", "")
	$mac = StringMid($mac, 1, 2) & ":" & StringMid($mac, 3, 2) & ":" & StringMid($mac, 5, 2) & ":" & StringMid($mac, 7, 2) & ":" & StringMid($mac, 9, 2) & ":" & StringMid($mac, 11, 2)
	Local $ConfigMatchArray, $iRows, $iColumns, $iRval
	$query = "SELECT configid, line, times, info FROM CONFIGDATA WHERE mac='" & $mac & "' And client='" & $client & "' And tftp='" & $tftp & "' And config='" & $config & "' limit 1"
	$iRval = _SQLite_GetTable2d($DBhndl, $query, $ConfigMatchArray, $iRows, $iColumns)
	If $iRows = 0 Then ;If config is not found then add it
		GUICtrlSetData($messagebox, 'New config found: ' & $config & ' (' & _GetTime() & ')')
		;Get config file
		If $AutoDownloadConfigs = 1 Then
			$config_destname = StringRegExpReplace($config, '[/\\:?"><!]', '_') & '.cfg'
			$config_destfile = $ConfDir & $config_destname
			$tftpget = _GetConfigTFTP($tftp, $config, $config_destfile)
			If $tftpget = 1 Then
				$decodedconfig = _DecodeConfig($config_destfile)
				If $decodedconfig <> "" Then $configtxt = $decodedconfig
				$configinfo = _GetConfigInfo($decodedconfig)
				If $configinfo <> "" Then $infostring = $configinfo
			EndIf
		EndIf
		If $AddIfBlank = 0 And $configtxt = "" Then $Add = 0
		If $Add = 1 Then
			;Add into list
			$ConfigID += 1
			$ListRow = _GUICtrlListView_InsertItem($ConfList, $ConfigID, -1)
			_ListViewAdd($ListRow, $ConfigID, $mac, $client, $tftp, $config, $infostring, $TimesSeen)
			;Add into DB
			GUICtrlSetData($messagebox, 'Inserting into DB')
			$query = "INSERT INTO CONFIGDATA(configid,line,config,client,tftp,mac,info,times,configtxt) VALUES ('" & $ConfigID & "','" & $ListRow & "','" & $config & "','" & $client & "','" & $tftp & "','" & $mac & "','" & $infostring & "','" & $TimesSeen & "','" & $configtxt & "');"
			_SQLite_Exec($DBhndl, $query)
			;Log line
			GUICtrlSetData($messagebox, 'Inserting into Log')
			FileWrite($configfile, '"' & $mac & '",' & $client & ',' & $tftp & ',"' & $config & '","' & $infostring & '",' & $TimesSeen & ',' & StringToBinary($configtxt) & @CRLF)
		EndIf
	Else
		GUICtrlSetData($messagebox, 'Config already exists: ' & $config & ' (' & _GetTime() & ')')
		$FoundConfigID = $ConfigMatchArray[1][0]
		$FoundLine = $ConfigMatchArray[1][1]
		$FoundTimes = $ConfigMatchArray[1][2] + $TimesSeen ;Add $TimeSeen to last found number
		$FoundInfo = $ConfigMatchArray[1][3]
		If $FoundInfo = "" Then
			If $AutoDownloadConfigs = 1 Then
				$config_destname = StringRegExpReplace($config, '[/\\:?"><!]', '_') & '.cfg'
				$config_destfile = $ConfDir & $config_destname
				$tftpget = _GetConfigTFTP($tftp, $config, $config_destfile)
				If $tftpget = 1 Then
					$decodedconfig = _DecodeConfig($config_destfile)
					If $decodedconfig <> "" Then
						$query = "UPDATE CONFIGDATA SET configtxt='" & $decodedconfig & "' WHERE configid = '" & $FoundConfigID & "'"
						_SQLite_Exec($DBhndl, $query)
					EndIf
					$configinfo = _GetConfigInfo($decodedconfig)
					If $configinfo <> "" Then
						$query = "UPDATE CONFIGDATA SET info='" & $configinfo & "' WHERE configid = '" & $FoundConfigID & "'"
						_SQLite_Exec($DBhndl, $query)
						_ListViewAdd($FoundLine, "", "", "", "", "", $infostring, "")
					EndIf
				EndIf
			EndIf
		EndIf
		_ListViewAdd($FoundLine, "", "", "", "", "", "", $FoundTimes)
		$query = "UPDATE CONFIGDATA SET times='" & $FoundTimes & "' WHERE configid = '" & $FoundConfigID & "'"
		_SQLite_Exec($DBhndl, $query)
	EndIf
EndFunc   ;==>_InsertIntoDB

Func _GetConfigTFTP($tftp_server, $tftp_configfile, $local_configfile)
	GUICtrlSetData($messagebox, 'Downloading config: ' & $tftp_configfile & ' (' & _GetTime() & ')')
	$command = '"' & $tftp_exe & '" -i ' & $tftp_server & ' GET ' & $tftp_configfile & ' "' & $local_configfile & '"'
	ConsoleWrite($command & @CRLF)
	$run = RunWait($command, "", @SW_HIDE)
	If FileExists($local_configfile) Then
		Return (1); Success :-)
		GUICtrlSetData($messagebox, 'Downloaded config: (' & _GetTime() & ')')
	Else
		GUICtrlSetData($messagebox, 'Config not downloaded: (' & _GetTime() & ')')
		Return (0); ...awww failure
	EndIf
EndFunc   ;==>_GetConfigTFTP

Func _DecodeConfig($local_configfile)
	GUICtrlSetData($messagebox, 'Decoding config: (' & _GetTime() & ')')
	Local $decode_line = ""
	If FileExists($local_configfile) Then ;Use DOCSIS.exe to decode config.
		;Read data from console output
		$command = '"' & $DocsisEXE & '" -d ' & FileGetShortName($local_configfile)
		ConsoleWrite($command & @CRLF)
		$decode_output = Run($command, '', @SW_HIDE, 2)
		Local $timeout = TimerInit()
		While TimerDiff($timeout) <= 15000
			$decode_line &= StdoutRead($decode_output)
			If @error Then ExitLoop
		WEnd
	EndIf
	Return($decode_line)
EndFunc   ;==>_DecodeConfig

Func _GetConfigInfo($decoded_config)
	GUICtrlSetData($messagebox, 'Getting info from config: (' & _GetTime() & ')')
	Local $configinfo = ""
	;Split config output data by ;
	$configdataarr = StringSplit($decoded_config, ";")
	;Pull wanted data into the info string
	For $gd = 1 To $configdataarr[0]
		If StringInStr($configdataarr[$gd], "NetworkAccess ") Then
			$naarr = StringSplit($configdataarr[$gd], "NetworkAccess ", 1)
			If $configinfo <> "" Then $configinfo &= ' - '
			;_ArrayDisplay($naarr)
			$configinfo &= 'NetworkAccess:' & $naarr[2]
		ElseIf StringInStr($configdataarr[$gd], "GlobalPrivacyEnable ") Then
			$gparr = StringSplit($configdataarr[$gd], "GlobalPrivacyEnable ", 1)
			If $configinfo <> "" Then $configinfo &= ' - '
			;_ArrayDisplay($gparr)
			$configinfo &= 'GlobalPrivacyEnable:' & $gparr[2]
		ElseIf StringInStr($configdataarr[$gd], "MaxCPE ") Then
			$cpearr = StringSplit($configdataarr[$gd], "MaxCPE ", 1)
			If $configinfo <> "" Then $configinfo &= ' - '
			;_ArrayDisplay($cpearr)
			$configinfo &= 'MaxCPE:' & $cpearr[2]
		ElseIf StringInStr($configdataarr[$gd], "ServiceClassName ") Then
			$scna = StringSplit($configdataarr[$gd], "ServiceClassName ", 1)
			If $configinfo <> "" Then $configinfo &= ' - '
			;_ArrayDisplay($scna)
			$configinfo &= 'ServiceClassName:' & $scna[2]
		ElseIf StringInStr($configdataarr[$gd], "MaxRateDown ") Then
			$mdrarr = StringSplit($configdataarr[$gd], "MaxRateDown ", 1)
			If $configinfo <> "" Then $configinfo &= ' - '
			;_ArrayDisplay($mdrarr)
			$configinfo &= 'MaxRateDown:' & $mdrarr[2]
		ElseIf StringInStr($configdataarr[$gd], "MaxRateUp ") Then
			$murarr = StringSplit($configdataarr[$gd], "MaxRateUp ", 1)
			If $configinfo <> "" Then $configinfo &= ' - '
			;_ArrayDisplay($murarr)
			$configinfo &= 'MaxRateUp:' & $murarr[2]
		ElseIf StringInStr($configdataarr[$gd], "MaxRateSustained ") Then
			$cpearr = StringSplit($configdataarr[$gd], "MaxRateSustained ", 1)
			If $configinfo <> "" Then $configinfo &= ' - '
			;_ArrayDisplay($cpearr)
			$configinfo &= 'MaxRateSustained:' & $cpearr[2]
		ElseIf StringInStr($configdataarr[$gd], "SnmpMibObject iso.3.6.1.2.1.1.6.0 String ") Then
			$provareaarr = StringSplit($configdataarr[$gd], "SnmpMibObject iso.3.6.1.2.1.1.6.0 String ", 1)
			If $configinfo <> "" Then $configinfo &= ' - '
			;_ArrayDisplay($provareaarr)
			$configinfo &= $provareaarr[2]
		EndIf
	Next
	$configinfo = StringReplace($configinfo, '"', '')
	GUICtrlSetData($messagebox, 'Done getting info from config: (' & _GetTime() & ')')
	Return ($configinfo)
EndFunc   ;==>_GetConfigInfo

Func _ListViewAdd($line, $Add_CID = '', $Add_mac = '', $Add_client = '', $Add_tftp = '', $Add_config = '', $Add_info = '', $Add_times = '')
	If $Add_CID <> '' Then _GUICtrlListView_SetItemText($ConfList, $line, $Add_CID, 0)
	If $Add_mac <> '' Then _GUICtrlListView_SetItemText($ConfList, $line, $Add_mac, 1)
	If $Add_client <> '' Then _GUICtrlListView_SetItemText($ConfList, $line, $Add_client, 2)
	If $Add_tftp <> '' Then _GUICtrlListView_SetItemText($ConfList, $line, $Add_tftp, 3)
	If $Add_config <> '' Then _GUICtrlListView_SetItemText($ConfList, $line, $Add_config, 4)
	If $Add_info <> '' Then _GUICtrlListView_SetItemText($ConfList, $line, $Add_info, 5)
	If $Add_times <> '' Then _GUICtrlListView_SetItemText($ConfList, $line, $Add_times, 6)
EndFunc   ;==>_ListViewAdd

Func _GetTime()
	$ldatetimestamp = StringFormat("%04i", @YEAR) & '/' & StringFormat("%02i", @MON) & '/' & StringFormat("%02i", @MDAY) & ' ' & @HOUR & ':' & @MIN & ':' & @SEC
	Return($ldatetimestamp)
EndFunc

;---------------------------------------------------------------------------------------
; File Menu Functions
;---------------------------------------------------------------------------------------

Func _ExportList()
	$fldatetimestamp = StringFormat("%04i", @YEAR) & '-' & StringFormat("%02i", @MON) & '-' & StringFormat("%02i", @MDAY) & ' ' & @HOUR & '-' & @MIN & '-' & @SEC
	$file = FileSaveDialog('Save As', '', 'Coma Delimeted File (*.CSV)', '', $fldatetimestamp & '.CSV')
	If @error <> 1 Then
		FileDelete($file)
		FileWrite($file, 'Mac Address,Client IP,TFTP IP,Config,Info,Times Seen,configtxt(hex)' & @CRLF)
		Local $ConfigMatchArray, $iRows, $iColumns, $iRval
		$query = "SELECT mac, client, tftp, config, info, times, configtxt FROM CONFIGDATA"
		$iRval = _SQLite_GetTable2d($DBhndl, $query, $ConfigMatchArray, $iRows, $iColumns)
		If $iRows <> 0 Then ;If Configs found, write to file
			For $ed = 1 To $iRows
				$ExpMac = $ConfigMatchArray[$ed][0]
				$ExpClient = $ConfigMatchArray[$ed][1]
				$ExpTftp = $ConfigMatchArray[$ed][2]
				$ExpConfig = $ConfigMatchArray[$ed][3]
				$ExpInfo = $ConfigMatchArray[$ed][4]
				$ExpTimes = $ConfigMatchArray[$ed][5]
				$ExpConfigTXT = StringToBinary($ConfigMatchArray[$ed][6])
				FileWrite($file, '"' & $ExpMac & '",' & $ExpClient & ',' & $ExpTftp & ',"' & $ExpConfig & '","' & $ExpInfo & '",' & $ExpTimes & ',' & $ExpConfigTXT & @CRLF)
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
		WEnd
		For $Load = 1 To $totallines
			$linein = FileReadLine($logfile, $Load);Open Line in file
			$ldatetimestamp = StringFormat("%04i", @YEAR) & '-' & StringFormat("%02i", @MON) & '-' & StringFormat("%02i", @MDAY) & ' ' & @HOUR & ':' & @MIN & ':' & @SEC
			_CheckData($linein)
		Next
		GUICtrlSetData($messagebox, "Done loading file")
	EndIf
EndFunc   ;==>_LoadLogTXT

Func _LoadCSV()
	$csvfile = FileOpenDialog('Import ConfigStumbler CSV', '', 'ConfigStumbler CSV(*.csv)', 1)
	If Not @error Then
		$CSVArray = _ParseCSV($csvfile, ',', '"')
		$iSize = UBound($CSVArray) - 1
		$iCol = UBound($CSVArray, 2)
		ConsoleWrite("$iCol=" & $iCol & @CRLF)
		If $iCol = 6 Then ;Import ConfigStumbler 0.6 CSV
			For $lc = 1 To $iSize
				$LoadMac = StringReplace($CSVArray[$lc][0], '"', '')
				$LoadClient = $CSVArray[$lc][1]
				$LoadTftp = $CSVArray[$lc][2]
				$LoadConfig = StringReplace($CSVArray[$lc][3], '"', '')
				$LoadInfo = StringReplace($CSVArray[$lc][4], '"', '')
				$LoadTImes = $CSVArray[$lc][5]

				_InsertIntoDB($LoadConfig, $LoadClient, $LoadTftp, $LoadMac, $LoadInfo, "", $LoadTImes)
			Next
		ElseIf $iCol = 7 Then ;Import ConfigStumbler 0.7+ CSV
			For $lc = 1 To $iSize
				$LoadMac = StringReplace($CSVArray[$lc][0], '"', '')
				$LoadClient = $CSVArray[$lc][1]
				$LoadTftp = $CSVArray[$lc][2]
				$LoadConfig = StringReplace($CSVArray[$lc][3], '"', '')
				$LoadInfo = StringReplace($CSVArray[$lc][4], '"', '')
				$LoadTImes = $CSVArray[$lc][5]
				$LoadConfigTXT = BinaryToString($CSVArray[$lc][6])

				_InsertIntoDB($LoadConfig, $LoadClient, $LoadTftp, $LoadMac, $LoadInfo, $LoadConfigTXT, $LoadTImes)
			Next
		EndIf
	EndIf
EndFunc   ;==>_LoadCSV

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
	IniWrite($settings, 'Settings', 'OverrideTftp', $OverrideTftp)
	IniWrite($settings, 'Settings', 'OverrideTftpIP', GUICtrlRead($OverrideTftpIpBox))

	IniWrite($settings, '5100tftp', 'teletIP', $5100teletIP)
	IniWrite($settings, '5100tftp', 'teletUN', $5100teletUN)
	IniWrite($settings, '5100tftp', 'teletPW', $5100teletPW)
	IniWrite($settings, '5100tftp', 'telnetSet', $5100telnetSet)

	IniWrite($settings, 'ScanMacRange', 'startmac', $startmac)
	IniWrite($settings, 'ScanMacRange', 'endmac', $endmac)
	IniWrite($settings, 'ScanMacRange', 'macpre', $macpre)
	IniWrite($settings, 'ScanMacRange', 'macsuf', $macsuf)
	IniWrite($settings, 'ScanMacRange', 'mactftp', $mactftp)

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
EndFunc   ;==>_CopyClient

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
EndFunc   ;==>_CloseDecodedConfig

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
; Extra Menu Functions
;---------------------------------------------------------------------------------------
Func _Set5100telnetinfo()
	$5100InfoGUI = GUICreate("Modem Info", 219, 164)
	GUICtrlCreateLabel("Modem IP", 10, 5, 128, 15)
	$ModemIP = GUICtrlCreateInput($5100teletIP, 10, 20, 200, 20)
	GUICtrlCreateLabel("Telnet Username", 10, 45, 128, 15)
	$TelnetUser = GUICtrlCreateInput($5100teletUN, 10, 60, 200, 21)
	GUICtrlCreateLabel("Telnet Password", 10, 85, 128, 15)
	$TelnetPass = GUICtrlCreateInput($5100teletPW, 10, 100, 200, 21, $ES_PASSWORD)
	$ButtonOK = GUICtrlCreateButton("OK", 10, 130, 95, 25)
	$ButtonCan = GUICtrlCreateButton("Cancel", 110, 130, 95, 25)
	GUISetState(@SW_SHOW)

	GUICtrlSetOnEvent($ButtonOK, '_Set5100telnetinfoOK')
	GUICtrlSetOnEvent($ButtonCan, '_Set5100telnetinfoClose')
EndFunc   ;==>_Set5100telnetinfo

Func _Set5100telnetinfoOK()
	$5100teletIP = GUICtrlRead($ModemIP)
	$5100teletUN = GUICtrlRead($TelnetUser)
	$5100teletPW = GUICtrlRead($TelnetPass)
	$5100telnetSet = 1
	_Set5100telnetinfoClose()
EndFunc   ;==>_Set5100telnetinfoOK

Func _Set5100telnetinfoClose()
	GUIDelete($5100InfoGUI)
EndFunc   ;==>_Set5100telnetinfoClose

Func _Set5100selctedmac()
	If $5100telnetSet = 0 Then
		MsgBox(0, "Error", "Set 5100 telnet info first")
	Else
		$Selected = _GUICtrlListView_GetNextItem($ConfList); find what config is selected in the list. returns -1 is nothing is selected
		If $Selected <> "-1" Then
			Local $ConfigMatchArray, $iRows, $iColumns, $iRval
			$query = "SELECT mac FROM CONFIGDATA WHERE line='" & $Selected & "'"
			$iRval = _SQLite_GetTable2d($DBhndl, $query, $ConfigMatchArray, $iRows, $iColumns)
			If $iRows <> 0 Then ;If Configs found, write to file
				$mac = $ConfigMatchArray[1][0]
				GUICtrlSetData($messagebox, "Setting modem mac to " & $mac)
				_Set5100mac($mac)

			EndIf
		Else
			MsgBox(0, "Error", "No config selected")
		EndIf
	EndIf
EndFunc   ;==>_Set5100selctedmac

Func _Set5100toallmacs()
	If $5100telnetSet = 0 Then
		MsgBox(0, "Error", "Set 5100 telnet info first")
	Else
		Local $ConfigMatchArray, $iRows, $iColumns, $iRval

		$fldatetimestamp = StringFormat("%04i", @YEAR) & '-' & StringFormat("%02i", @MON) & '-' & StringFormat("%02i", @MDAY) & ' ' & @HOUR & '-' & @MIN & '-' & @SEC
		$file = FileSaveDialog('Save As', '', 'Coma Delimeted File (*.CSV)', '', $fldatetimestamp & '.CSV')
		If @error <> 1 Then
			FileWrite($file, 'Mac Address,Client IP,TFTP IP,Config,Info,Times Seen,configtxt(hex)' & @CRLF)
			$waittime = InputBox("Time to wait before mac change", "Time (in milliseconds)", "25000")
			$query = "SELECT mac FROM CONFIGDATA"
			$iRval = _SQLite_GetTable2d($DBhndl, $query, $ConfigMatchArray, $iRows, $iColumns)
			If $iRows <> 0 Then ;If Configs found, write to file
				For $cm = 1 To $iRows
					$mac = $ConfigMatchArray[$cm][0]
					GUICtrlSetData($messagebox, "Setting modem mac to " & $mac)
					_Set5100mac($mac)
					Sleep($waittime)
					$webpagesource = _INetGetSource("http://192.168.100.1:1337/advanced.html")
					If StringInStr($webpagesource, 'TFTP config file: ') Then
						$tws = StringSplit($webpagesource, "TFTP config file: ", 1)
						;_ArrayDisplay($tws)
						$tws2 = StringSplit($tws[2], ">", 1)
						$configname = StringReplace(StringReplace($tws2[1], "<a href='", ""), "</center", "")
						If StringRight($configname, 1) = "'" Then $configname = StringTrimRight($configname, 1)

						If $configname <> "Not yet provisioned" Then
							$downfile = "http://" & $5100teletIP & ":1337/" & $configname
							$savefile = $ConfDir & $configname & '.cfg'
							InetGet($downfile, $savefile)
							$config_destfile = $savefile
							$configtxt = ""
							$infostring = ""
							If FileExists($config_destfile) Then ;Use DOCSIS.exe to decode config.
								$decodedconfig = _DecodeConfig($savefile)
								If $decodedconfig <> "" Then $configtxt2 = $decodedconfig
								$configinfo = _GetConfigInfo($decodedconfig)
								If $configinfo <> "" Then $infostring = $configinfo
							EndIf
							FileWrite($file, '"' & $mac & '",,,"' & $configname & '","' & $infostring & '",1,' & StringToBinary($configtxt) & @CRLF)
						EndIf
					EndIf
				Next
			EndIf
			GUICtrlSetData($messagebox, "Done setting macs ")
		EndIf
	EndIf
EndFunc   ;==>_Set5100toallmacs

Func _Set5100mac($mac)
	$cmd = '"' & $PuttyEXE & '" -telnet ' & $5100teletUN & '@192.168.100.1'
	Run(@ComSpec & ' /c ' & $cmd, '', @SW_HIDE, 2)
	WinActivate($5100teletIP & " - PuTTY")
	WinWaitActive($5100teletIP & " - PuTTY")
	Send("{ENTER}")
	Sleep(50)
	Send($5100teletUN)
	Sleep(50)
	Send("{ENTER}")
	Sleep(50)
	Send($5100teletPW)
	Sleep(50)
	Send("{ENTER}")
	Sleep(50)
	Send("cd non-vol")
	Sleep(50)
	Send("{ENTER}")
	Sleep(50)
	Send("cd halif")
	Sleep(50)
	Send("{ENTER}")
	Sleep(50)
	Send("mac_address 1 " & $mac)
	Send("{ENTER}")
	Sleep(50)
	Send("write")
	Send("{ENTER}")
	Sleep(50)
	Send("cd \")
	Send("{ENTER}")
	Sleep(50)
	Send("reset")
	Send("{ENTER}")
	Sleep(10000)
	Send("q")
	Return ($mac)
EndFunc   ;==>_Set5100mac

Func _TestMacRangeGUI()
	$tmrGUI = GUICreate("Scan Mac Range", 219, 256)
	GUICtrlCreateLabel("TFTP Server", 10, 10, 200, 15)
	$rTftp = GUICtrlCreateInput($mactftp, 10, 25, 200, 21)
	GUICtrlCreateLabel("Mac Prefix", 10, 50, 200, 15)
	$rMacPre = GUICtrlCreateInput($macpre, 10, 65, 200, 21)
	GUICtrlCreateLabel("Mac Suffix", 10, 90, 200, 15)
	$rMacSuf = GUICtrlCreateInput($macsuf, 10, 105, 200, 21)
	GUICtrlCreateLabel("Start Mac", 10, 130, 200, 15)
	$rStartMac = GUICtrlCreateInput($startmac, 10, 145, 200, 21)
	GUICtrlCreateLabel("EndMac", 10, 170, 200, 15)
	$rEndMac = GUICtrlCreateInput($endmac, 10, 185, 200, 21)
	$rOK = GUICtrlCreateButton("Start", 8, 215, 95, 25, $WS_GROUP)
	$rCAN = GUICtrlCreateButton("Cancel", 114, 215, 95, 25, $WS_GROUP)
	GUICtrlSetOnEvent($rOK, '_TestMacRangeGUIOK')
	GUICtrlSetOnEvent($rCAN, '_TestMacRangeGUIClose')
	GUISetState(@SW_SHOW)
EndFunc

Func _TestMacRangeGUIOK()
	$startmac = GUICtrlRead($rStartMac)
	$startmacf = StringReplace(StringReplace($startmac, ":", ""), "-", "")
	$startmac1 = '0x' & StringLeft($startmacf, 6)
	$startmac2 = '0x' & StringRight($startmacf, 6)
	$endmac = GUICtrlRead($rEndMac)
	$endmacf = StringReplace(StringReplace($endmac, ":", ""), "-", "")
	$endmac1 = '0x' & StringLeft($endmacf, 6)
	$endmac2 = '0x' & StringRight($endmacf, 6)
	$macpre = GUICtrlRead($rMacPre)
	$macsuf = GUICtrlRead($rMacSuf)
	$mactftp = GUICtrlRead($rTftp)
	_TestMacRangeGUIClose()
	For $ml = $startmac1 To $endmac1
		$manhex = Hex($ml, 6)
		For $cl = $startmac2 To $endmac2
			$chex = Hex($cl, 6)
			$fullmac = $manhex & $chex
			$configname = $macpre & StringLower($fullmac) & $macsuf
			GUICtrlSetData($messagebox, $fullmac)
			_InsertIntoDB($configname, "", $mactftp, $fullmac, "", "", 1, 0)
		Next
	Next
EndFunc

Func _TestMacRangeGUIClose()
	GUIDelete($tmrGUI)
EndFunc


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
EndFunc   ;==>_ToggleConfigDownload

Func _ToggleOverrideTftp()
	If $OverrideTftp = 0 Then
		$OverrideTftp = 1
		GUICtrlSetState($OverrideTftpCheck, $GUI_CHECKED)
	Else
		$OverrideTftp = 0
		GUICtrlSetState($OverrideTftpCheck, $GUI_UNCHECKED)
	EndIf
EndFunc   ;==>_ToggleConfigDownload