#RequireAdmin
;-----------------------------------
$Program_Name = "ConfigStumbler"
$Program_Version = "0.8.2.1"
$Last_Modified = "2013-06-27"
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
#include <process.au3>
#include "UDFs\ParseCSV.au3"

Dim $ConfigID = 0
Dim $DBhndl
Dim $UDPsocket
Dim $UDPport = 68

Dim $DefaultIntMenuID = '-1'
Dim $Scan = 0
Dim $DocsisDecoder = 0
Dim $SortColumn = -1

;Settings file
Dim $settings = @ScriptDir & '\settings.ini'

;Set up log files for current session
Dim $logfile = @ScriptDir & '\log.txt'
Dim $configfile = @ScriptDir & '\configs.csv'
FileDelete($logfile)
FileDelete($configfile)
$logfile = FileOpen($logfile, 128 + 2);Open in UTF-8 write mode
$configfile = FileOpen($configfile, 128 + 2);Open in UTF-8 write mode

;Paths to files needed
Dim $tftp_exe = IniRead($settings, 'NeededFiles', 'tftp', @ScriptDir & '\tftp.exe')
Dim $DocsisEXE = IniRead($settings, 'NeededFiles', 'docsis', @ScriptDir & '\docsis.exe')
Dim $PuttyEXE = IniRead($settings, 'NeededFiles', 'putty', @ScriptDir & '\putty.exe')
Dim $pscpEXE = IniRead($settings, 'NeededFiles', 'putty', @ScriptDir & '\pscp.exe')
Dim $TST10EXE = IniRead($settings, 'NeededFiles', 'tst10', @ScriptDir & '\TST10.exe')

;Create Directories
Dim $TmpDir = IniRead($settings, 'Directories', 'tmp', @ScriptDir & '\temp\')
Dim $ConfDir = IniRead($settings, 'Directories', 'config', @ScriptDir & '\configs\')
Dim $SavefDir = IniRead($settings, 'Directories', 'save', @ScriptDir & '\save\')
DirCreate($TmpDir)
DirCreate($ConfDir)
DirCreate($SavefDir)

Dim $AutoDownloadConfigs = IniRead($settings, 'Settings', 'AutoDownloadConfigs', "1")
Dim $OverrideTftp = IniRead($settings, 'Settings', 'OverrideTftp', 0)
Dim $OverrideTftpIP = IniRead($settings, 'Settings', 'OverrideTftpIP', "0.0.0.0")
Dim $DefaultName = IniRead($settings, 'Settings', 'DefaultName', "Local Area Connection")
Dim $DefaultIP = IniRead($settings, 'Settings', 'DefaultIP', "127.0.0.1")

Dim $5100InfoGUI, $5101InfoGUI, $6120InfoGUI, $ModemIP, $User, $Pass
Dim $5100telnetIP = IniRead($settings, '5100', 'telnetIP', "192.168.100.1")
Dim $5100telnetUN = IniRead($settings, '5100', 'telnetUN', "")
Dim $5100telnetPW = IniRead($settings, '5100', 'telnetPW', "")
Dim $5100telnetSet = IniRead($settings, '5100', 'telnetSet', 0)
Dim $5101telnetIP = IniRead($settings, '5101', 'sshIP', "192.168.100.1")
Dim $5101telnetUN = IniRead($settings, '5101', 'sshUN', "")
Dim $5101telnetPW = IniRead($settings, '5101', 'sshPW', "")
Dim $5101telnetSet = IniRead($settings, '5101', 'sshSet', 0)
Dim $6120sshIP = IniRead($settings, '6120', 'sshIP', "192.168.100.1")
Dim $6120sshUN = IniRead($settings, '6120', 'sshUN', "")
Dim $6120sshPW = IniRead($settings, '6120', 'sshPW', "")
Dim $6120sshSet = IniRead($settings, '6120', 'sshSet', 0)
Dim $6120netcon = IniRead($settings, '6120', 'NetworkConnection', 'Local Area Connection')

Dim $InterfaceMenuID_Array[1]
Dim $InterfaceMenuName_Array[1]
Dim $InterfaceMenuIP_Array[1]
Dim $RefreshInterfaces

Dim $tmrGUI, $iTFTP, $iPrefix, $iSuffix, $iStartMac, $iEndMac, $iWaitTime, $rNone, $rTFTP, $rSB5100, $rSB5101, $rSB6120
Dim $startmac = IniRead($settings, 'ScanMacRange', 'startmac', "00:00:00:00:00:00")
Dim $endmac = IniRead($settings, 'ScanMacRange', 'endmac', "00:00:00:00:00:00")
Dim $macpre = IniRead($settings, 'ScanMacRange', 'macpre', "")
Dim $macsuf = IniRead($settings, 'ScanMacRange', 'macsuf', "")
Dim $mactftp = IniRead($settings, 'ScanMacRange', 'mactftp', "")

FileWrite($configfile, 'Mac Address,Client IP,TFTP IP,Config,Info,Times Seen,configtxt(hex)' & @CRLF)

;Set up temp config database
$fldatetimestamp = StringFormat("%04i", @YEAR) & '-' & StringFormat("%02i", @MON) & '-' & StringFormat("%02i", @MDAY) & ' ' & @HOUR & '-' & @MIN & '-' & @SEC
$DB = $TmpDir & $fldatetimestamp & '.SDB'
_SetUpDbTables($DB)

Dim $ManuDB = @ScriptDir & '\Manufacturers.sdb'
Dim $ManuDBhndl
;Connect to manufacturer database
If FileExists($ManuDB) Then
	$ManuDBhndl = _SQLite_Open($ManuDB, $SQLITE_OPEN_READWRITE + $SQLITE_OPEN_CREATE, $SQLITE_ENCODING_UTF16)
Else
	$ManuDBhndl = _SQLite_Open($ManuDB, $SQLITE_OPEN_READWRITE + $SQLITE_OPEN_CREATE, $SQLITE_ENCODING_UTF16)
	_SQLite_Exec($ManuDBhndl, "CREATE TABLE Manufacturers (BSSID,Manufacturer)")
	_SQLite_Exec($ManuDBhndl, "pragma synchronous=0");Speed vs Data security. Speed Wins for now.
EndIf

;---GUI---

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
_AddInterfaces()
$ExtraMenu = GUICtrlCreateMenu("Extra")
$EditTestBprMac = GUICtrlCreateMenuItem("Test mac range", $ExtraMenu)
$SigmaX2Menu = GUICtrlCreateMenu("5100 (Sigma X2)", $ExtraMenu)
$Set5100telnetinfo = GUICtrlCreateMenuItem("Set SB5100 telnet info ", $SigmaX2Menu)
$Set5100selmac = GUICtrlCreateMenuItem("Set SB5100 mac to selected", $SigmaX2Menu)
$Set5100toallmacs = GUICtrlCreateMenuItem("Set SB5100 mac to all macs (timed)", $SigmaX2Menu)
$Set5100toallmacstilonline = GUICtrlCreateMenuItem("Set SB5100 mac to all macs until online (timed)", $SigmaX2Menu)
$5101haxorwareMenu = GUICtrlCreateMenu("5101 (haxorware)", $ExtraMenu)
$Set5101telnetinfo = GUICtrlCreateMenuItem("Set SB5101 telnet info ", $5101haxorwareMenu)
$Set5101selmac = GUICtrlCreateMenuItem("Set SB5101 mac to selected", $5101haxorwareMenu)
$Set5101toallmacs = GUICtrlCreateMenuItem("Set SB5101 mac to all macs (timed)", $5101haxorwareMenu)
$Set5101toallmacstilonline = GUICtrlCreateMenuItem("Set SB5101 mac to all macs until online (timed)", $5101haxorwareMenu)
$6120AlphaMenu = GUICtrlCreateMenu("6120 (ForceWare 1.2+)", $ExtraMenu)
$Set6120sshinfo = GUICtrlCreateMenuItem("Set SB6120 ssh info ", $6120AlphaMenu)
$Set6120selmac = GUICtrlCreateMenuItem("Set SB6120 mac to selected", $6120AlphaMenu)
$Set6120toallmacs = GUICtrlCreateMenuItem("Set SB6120 mac to all macs (timed)", $6120AlphaMenu)
$Set6120toallmacstilonline = GUICtrlCreateMenuItem("Set SB6120 mac to all macs until online (timed)", $6120AlphaMenu)
$importconfigfile = GUICtrlCreateMenuItem("Import config file", $ExtraMenu)
$importconfigfolder = GUICtrlCreateMenuItem("Import folder of config files", $ExtraMenu)

;End Get Local IPs
$ScanButton = GUICtrlCreateButton("Scan", 8, 8, 81, 33, $WS_GROUP)
$messagebox = GUICtrlCreateLabel("", 8, 45, 500, 15, $SS_LEFT)

$ConfigDownload = GUICtrlCreateCheckbox("Automatically download config from tftp (Required for Info)", 104, 8, 297, 17)
If $AutoDownloadConfigs = 1 Then GUICtrlSetState($ConfigDownload, $GUI_CHECKED)
$OverrideTftpCheck = GUICtrlCreateCheckbox("Override tftp server", 104, 26, 120, 17)
If $OverrideTftp = 1 Then GUICtrlSetState($OverrideTftpCheck, $GUI_CHECKED)
$OverrideTftpIpBox = GUICtrlCreateInput($OverrideTftpIP, 225, 24, 150, 20)


;GUICtrlSetResizing ($messagebox, $GUI_DOCKBORDERS)
$ConfList = GUICtrlCreateListView("#|Mac|Manufacturer|Client|TFTP Server|Config|Info|Times seen", 0, 65, 441, 165, $LVS_REPORT + $LVS_SINGLESEL, $LVS_EX_HEADERDRAGDROP + $LVS_EX_GRIDLINES + $LVS_EX_FULLROWSELECT)
GUICtrlSendMsg(-1, $LVM_SETCOLUMNWIDTH, 0, 30)
GUICtrlSendMsg(-1, $LVM_SETCOLUMNWIDTH, 1, 110)
GUICtrlSendMsg(-1, $LVM_SETCOLUMNWIDTH, 2, 110)
GUICtrlSendMsg(-1, $LVM_SETCOLUMNWIDTH, 3, 95)
GUICtrlSendMsg(-1, $LVM_SETCOLUMNWIDTH, 4, 95)
GUICtrlSendMsg(-1, $LVM_SETCOLUMNWIDTH, 5, 175)
GUICtrlSendMsg(-1, $LVM_SETCOLUMNWIDTH, 6, 375)
GUICtrlSendMsg(-1, $LVM_SETCOLUMNWIDTH, 7, 50)
GUICtrlSetResizing($ConfList, $GUI_DOCKBORDERS)
Dim $Direction[8];Direction array for sorting by clicking on the header. Needs to be 1 greatet (or more) than the amount of columns
GUICtrlSetOnEvent($ConfList, '_SortColumnToggle')

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
GUICtrlSetOnEvent($Set5100toallmacstilonline, '_Set5100toallmacstilonline')
GUICtrlSetOnEvent($Set5101telnetinfo, '_Set5101telnetinfo')
GUICtrlSetOnEvent($Set5101selmac, '_Set5101selctedmac')
GUICtrlSetOnEvent($Set5101toallmacs, '_Set5101toallmacs')
GUICtrlSetOnEvent($Set5101toallmacstilonline, '_Set5101toallmacstilonline')
GUICtrlSetOnEvent($Set6120sshinfo, '_Set6120sshinfo')
GUICtrlSetOnEvent($Set6120selmac, '_Set6120selctedmac')
GUICtrlSetOnEvent($Set6120toallmacs, '_Set6120toallmacs')
GUICtrlSetOnEvent($Set6120toallmacstilonline, '_Set6120toallmacstilonline')
GUICtrlSetOnEvent($importconfigfile, '_ImportConfigFile')
GUICtrlSetOnEvent($importconfigfolder, '_ImportConfigFolder')

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
	If $SortColumn <> -1 Then _HeaderSort($SortColumn);Sort clicked listview column
	Sleep(10)
WEnd

;-----------------
;Functions
;-----------------

Func _SetUpDbTables($dbfile)
	_SQLite_Startup()
	$DBhndl = _SQLite_Open($dbfile)
	_SQLite_Exec($DBhndl, "pragma synchronous=0");Speed vs Data security. Speed Wins for now.
	_SQLite_Exec($DBhndl, "CREATE TABLE CONFIGDATA (configid,line,config,client,tftp,mac,manu,info,times,configtxt)")
EndFunc   ;==>_SetUpDbTables

Func _ReadUDPdata()
	$udpdata = UDPRecv($UDPsocket, 500)
	If $udpdata <> "" Then
		FileWrite($logfile, $udpdata & @CRLF)
		$InData = _CheckData($udpdata)
		If $InData[0] = 1 Then
			$mac = $InData[1] ;Modem Mac Address
			$client = $InData[2] ;Client IP
			$tftp = $InData[3] ;TFTP IP
			$config = $InData[4] ;Config Name
			$InsertData = _InsertIntoDB($config, $client, $tftp, $mac)
			If $InsertData[0] = 1 And $AutoDownloadConfigs = 1 Then
				$fconfigid = $InsertData[1] ;DB Config ID
				_UpdateTftpInfoInDB($fconfigid, $tftp, $config)
			EndIf
		EndIf
	EndIf
EndFunc   ;==>_ReadUDPdata

Func _CheckData($data)
	Local $UdpDataArr[5]
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

		$UdpDataArr[0] = 1
		$UdpDataArr[1] = $mac ;Modem Mac Address
		$UdpDataArr[2] = $client ;Client IP
		$UdpDataArr[3] = $tftp ;TFTP IP
		$UdpDataArr[4] = $config ;Config Name
	Else
		$UdpDataArr[0] = 0 ;Not results found, sting not long enough
	EndIf
	Return($UdpDataArr)
EndFunc   ;==>_CheckData

Func _InsertIntoDB($config, $client, $tftp, $mac, $infostring = "", $configtxt = "", $TimesSeen = 1)
	Local $InsertReturn[2]
	If $OverrideTftp = 1 Then $tftp = GUICtrlRead($OverrideTftpIpBox)
	$mac = StringReplace(StringReplace(StringUpper($mac), ":", ""), "-", "")
	$mac = StringMid($mac, 1, 2) & ":" & StringMid($mac, 3, 2) & ":" & StringMid($mac, 5, 2) & ":" & StringMid($mac, 7, 2) & ":" & StringMid($mac, 9, 2) & ":" & StringMid($mac, 11, 2)
	Local $ConfigMatchArray, $iRows, $iColumns, $iRval
	$query = "SELECT configid, line, times, info, configtxt FROM CONFIGDATA WHERE mac='" & $mac & "' And client='" & $client & "' And tftp='" & $tftp & "' And config='" & $config & "' limit 1"
	$iRval = _SQLite_GetTable2d($DBhndl, $query, $ConfigMatchArray, $iRows, $iColumns)
	If $iRows = 0 Then ;If config is not found then add it
		GUICtrlSetData($messagebox, 'New config found: ' & $config & ' (' & _GetTime() & ')')
		$NewConfig = 1
		;Get Manufacturer
		$Manufacturer = _FindManufacturer($mac)
		;Add into list
		$ConfigID += 1
		$ListRow = _GUICtrlListView_InsertItem($ConfList, $ConfigID, -1)
		_ListViewAdd($ListRow, $ConfigID, $mac, $Manufacturer, $client, $tftp, $config, $infostring, $TimesSeen)
		;Add into DB
		GUICtrlSetData($messagebox, 'Inserting into DB')
		$query = "INSERT INTO CONFIGDATA(configid,line,config,client,tftp,mac,manu,info,times,configtxt) VALUES ('" & $ConfigID & "','" & $ListRow & "','" & $config & "','" & $client & "','" & $tftp & "','" & $mac & "','" & $Manufacturer & "','" & $infostring & "','" & $TimesSeen & "','" & $configtxt & "');"
		_SQLite_Exec($DBhndl, $query)
		;Log line
		GUICtrlSetData($messagebox, 'Inserting into Log')
		FileWrite($configfile, '"' & $mac & '",' & $client & ',' & $tftp & ',"' & $config & '","' & $infostring & '",' & $TimesSeen & ',' & StringToBinary($configtxt) & @CRLF)
		;Set return
		$InsertReturn[0] = 1 ;Set as new
		$InsertReturn[1] = $ConfigID ;set config id
	Else
		GUICtrlSetData($messagebox, 'Config already exists: ' & $config & ' (' & _GetTime() & ')')
		$FoundConfigID = $ConfigMatchArray[1][0]
		$FoundLine = $ConfigMatchArray[1][1]
		$FoundTimes = $ConfigMatchArray[1][2] + $TimesSeen ;Add $TimeSeen to last found number
		$FoundInfo = $ConfigMatchArray[1][3]
		$FoundConfigtxt = $ConfigMatchArray[1][3]

		If $FoundInfo = "" And $infostring <> "" Then $FoundInfo = $infostring
		If $FoundConfigtxt = "" And $configtxt <> "" Then $FoundConfigtxt = $configtxt
		_ListViewAdd($FoundLine, "", "", "", "", "", "", $FoundInfo, $FoundTimes)
		$query = "UPDATE CONFIGDATA SET times='" & $FoundTimes & "', info='" & $FoundInfo & "', configtxt='" & $FoundConfigtxt & "' WHERE configid = '" & $FoundConfigID & "'"
		_SQLite_Exec($DBhndl, $query)
		$InsertReturn[0] = 0
		$InsertReturn[1] = $FoundConfigID
	EndIf
	Return($InsertReturn)
EndFunc   ;==>_InsertIntoDB

Func _ListViewAdd($line, $Add_CID = '', $Add_mac = '', $Add_manu = '', $Add_client = '', $Add_tftp = '', $Add_config = '', $Add_info = '', $Add_times = '')
	If $Add_CID <> '' Then _GUICtrlListView_SetItemText($ConfList, $line, $Add_CID, 0)
	If $Add_mac <> '' Then _GUICtrlListView_SetItemText($ConfList, $line, $Add_mac, 1)
	If $Add_manu <> '' Then _GUICtrlListView_SetItemText($ConfList, $line, $Add_manu, 2)
	If $Add_client <> '' Then _GUICtrlListView_SetItemText($ConfList, $line, $Add_client, 3)
	If $Add_tftp <> '' Then _GUICtrlListView_SetItemText($ConfList, $line, $Add_tftp, 4)
	If $Add_config <> '' Then _GUICtrlListView_SetItemText($ConfList, $line, $Add_config, 5)
	If $Add_info <> '' Then _GUICtrlListView_SetItemText($ConfList, $line, $Add_info, 6)
	If $Add_times <> '' Then _GUICtrlListView_SetItemText($ConfList, $line, $Add_times, 7)
EndFunc   ;==>_ListViewAdd

Func _UpdateTftpInfoInDB($configid, $tftp, $config)
	Local $Updated = 0
	$TftpResults = _TFTPDownload($tftp, $config)
	If $TftpResults[0] = 1 Then
		$config_destfile = $TftpResults[1]
		$decodedconfig = $TftpResults[2]
		$configinfo = $TftpResults[3]
		Local $ConfigMatchArray, $iRows, $iColumns, $iRval
		$query = "SELECT configid, line FROM CONFIGDATA WHERE configid='" & $configid & "' limit 1"
		$iRval = _SQLite_GetTable2d($DBhndl, $query, $ConfigMatchArray, $iRows, $iColumns)
		If $iRows = 1 Then
			$FoundConfigID = $ConfigMatchArray[1][0]
			$FoundLine = $ConfigMatchArray[1][1]
			;Update info in database
			If $decodedconfig <> "" Then
				$query = "UPDATE CONFIGDATA SET configtxt='" & $decodedconfig & "' WHERE configid = '" & $configid & "'"
				_SQLite_Exec($DBhndl, $query)
			EndIf
			If $configinfo <> "" Then
				$query = "UPDATE CONFIGDATA SET info='" & $configinfo & "' WHERE configid = '" & $configid & "'"
				_SQLite_Exec($DBhndl, $query)
			EndIf
			;Update Listview
			_ListViewAdd($FoundLine, "", "", "", "", $tftp, $config, $configinfo, "")
			$Updated = 1
		EndIf
	EndIf
	Return($Updated)
EndFunc

Func _TFTPDownload($tftp, $config)
	Local $result[4]
	$config_destname = StringRegExpReplace($config, '[/\\:?"><!]', '_') & '.cfg'
	$config_destfile = $ConfDir & $config_destname
	$tftpget = _GetConfigTFTP($tftp, $config, $config_destfile)
	If $tftpget = 1 Then
		$decodedconfig = _DecodeConfig($config_destfile)
		$configinfo = _GetConfigInfo($decodedconfig)
		$result[0] = 1
		$result[1] = $config_destfile
		$result[2] = $decodedconfig
		$result[3] = $configinfo
	Else
		$result[0] = 0
	EndIf
	Return($result)
EndFunc

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
	Return ($decode_line)
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

Func _FindManufacturer($findmac);Returns Manufacturer for given Mac Address
	$findmac = StringReplace($findmac, ':', '')
	If StringLen($findmac) <> 6 Then $findmac = StringTrimRight($findmac, StringLen($findmac) - 6)
	Local $ManuMatchArray, $iRows, $iColumns, $iRval
	$query = "SELECT Manufacturer FROM Manufacturers WHERE BSSID = '" & $findmac & "'"
	$iRval = _SQLite_GetTable2d($ManuDBhndl, $query, $ManuMatchArray, $iRows, $iColumns)
	$FoundManuMatch = $iRows
	If $FoundManuMatch = 0 Then
		Return ("Unknown")
	Else
		$Manu = $ManuMatchArray[1][0]
		Return ($Manu)
	EndIf
EndFunc   ;==>_FindManufacturer

Func _GetTime()
	$ldatetimestamp = StringFormat("%04i", @YEAR) & '/' & StringFormat("%02i", @MON) & '/' & StringFormat("%02i", @MDAY) & ' ' & @HOUR & ':' & @MIN & ':' & @SEC
	Return ($ldatetimestamp)
EndFunc   ;==>_GetTime

;-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
; File Menu Functions
;-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

Func _ExportList()
	$fldatetimestamp = StringFormat("%04i", @YEAR) & '-' & StringFormat("%02i", @MON) & '-' & StringFormat("%02i", @MDAY) & ' ' & @HOUR & '-' & @MIN & '-' & @SEC
	$file = FileSaveDialog('Save As', '', 'Coma Delimeted File (*.CSV)', '', $fldatetimestamp & '.CSV')
	If @error <> 1 Then
		FileDelete($file)
		$file = FileOpen($file, 128 + 2);Open in UTF-8 write mode
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
		FileClose($file)
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
			$InData = _CheckData($linein)
			If $InData[0] = 1 Then
				$mac = $InData[1] ;Modem Mac Address
				$client = $InData[2] ;Client IP
				$tftp = $InData[3] ;TFTP IP
				$config = $InData[4] ;Config Name
				$InsertData = _InsertIntoDB($config, $client, $tftp, $mac)
				If $InsertData[0] = 1 And $AutoDownloadConfigs = 1 Then
					$fconfigid = $InsertData[1] ;DB Config ID
					_UpdateTftpInfoInDB($fconfigid, $tftp, $config)
				EndIf
			EndIf
		Next
		FileClose($logfile)
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
		If $iCol = 5 Then ;Import ConfigStumbler 0.5 CSV
			For $lc = 1 To $iSize
				$LoadMac = StringReplace($CSVArray[$lc][0], '"', '')
				$LoadTftp = $CSVArray[$lc][1]
				$LoadConfig = StringReplace($CSVArray[$lc][2], '"', '')
				$LoadInfo = StringReplace($CSVArray[$lc][3], '"', '')
				$LoadTImes = $CSVArray[$lc][4]
				$LoadClient = ""
				$LoadConfigTXT = ""

				_InsertIntoDB($LoadConfig, $LoadClient, $LoadTftp, $LoadMac, $LoadInfo, $LoadConfigTXT, $LoadTImes)
			Next
		ElseIf $iCol = 6 Then ;Import ConfigStumbler 0.6 CSV
			For $lc = 1 To $iSize
				$LoadMac = StringReplace($CSVArray[$lc][0], '"', '')
				$LoadClient = $CSVArray[$lc][1]
				$LoadTftp = $CSVArray[$lc][2]
				$LoadConfig = StringReplace($CSVArray[$lc][3], '"', '')
				$LoadInfo = StringReplace($CSVArray[$lc][4], '"', '')
				$LoadTImes = $CSVArray[$lc][5]
				$LoadConfigTXT = ""

				_InsertIntoDB($LoadConfig, $LoadClient, $LoadTftp, $LoadMac, $LoadInfo, $LoadConfigTXT, $LoadTImes)
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
		GUICtrlSetData($messagebox, "Done loading file")
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
	UpdateSettingIni()

	_SQLite_Close($DBhndl)
	_SQLite_Shutdown()
	FileDelete($DB)
	Exit
EndFunc   ;==>_Exit

Func UpdateSettingIni()
	IniWrite($settings, 'Settings', 'DefaultName', $DefaultName)
	IniWrite($settings, 'Settings', 'DefaultIP', $DefaultIP)
	IniWrite($settings, 'Settings', 'AutoDownloadConfigs', $AutoDownloadConfigs)
	IniWrite($settings, 'Settings', 'OverrideTftp', $OverrideTftp)
	IniWrite($settings, 'Settings', 'OverrideTftpIP', GUICtrlRead($OverrideTftpIpBox))

	IniWrite($settings, '5100', 'telnetIP', $5100telnetIP)
	IniWrite($settings, '5100', 'telnetUN', $5100telnetUN)
	IniWrite($settings, '5100', 'telnetPW', $5100telnetPW)
	IniWrite($settings, '5100', 'telnetSet', $5100telnetSet)
	IniWrite($settings, '5101', 'sshIP', $5101telnetIP)
	IniWrite($settings, '5101', 'sshUN', $5101telnetUN)
	IniWrite($settings, '5101', 'sshPW', $5101telnetPW)
	IniWrite($settings, '5101', 'sshSet', $5101telnetSet)
	IniWrite($settings, '6120', 'sshIP', $6120sshIP)
	IniWrite($settings, '6120', 'sshUN', $6120sshUN)
	IniWrite($settings, '6120', 'sshPW', $6120sshPW)
	IniWrite($settings, '6120', 'sshSet', $6120sshSet)

	IniWrite($settings, 'ScanMacRange', 'startmac', $startmac)
	IniWrite($settings, 'ScanMacRange', 'endmac', $endmac)
	IniWrite($settings, 'ScanMacRange', 'macpre', $macpre)
	IniWrite($settings, 'ScanMacRange', 'macsuf', $macsuf)
	IniWrite($settings, 'ScanMacRange', 'mactftp', $mactftp)
EndFunc

;-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
; Edit Menu Functions
;-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

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

;-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
; Interface Menu Functions
;-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

Func _AddInterfaces()
	Dim $InterfaceMenuID_Array[1]
	Dim $InterfaceMenuName_Array[1]
	Dim $InterfaceMenuIP_Array[1]
	$RefreshInterfaces = GUICtrlCreateMenuItem("Refresh Interfaces", $InterfaceMenu)
	GUICtrlSetOnEvent($RefreshInterfaces, '_RefreshInterfaces')
	Dim $FoundIP = 0
	$wbemFlagReturnImmediately = 0x10
	$wbemFlagForwardOnly = 0x20
	$colItems = ""
	$strComputer = "localhost"
	$objWMIService = ObjGet("winmgmts:\\" & $strComputer & "\root\CIMV2")
	$colItems = $objWMIService.ExecQuery("SELECT * FROM Win32_NetworkAdapter WHERE adapterTypeID = 0")
	If IsObj($colItems) Then
		For $objItem In $colItems
			$adaptername = $objItem.NetConnectionID
			$adapterindex = $objItem.Index
			If $adaptername <> "" Then
				$objWMIService2 = ObjGet("winmgmts:\\" & $strComputer & "\root\CIMV2")
				$colItems2 = $objWMIService2.ExecQuery("SELECT * FROM Win32_NetworkAdapterConfiguration WHERE Index = " & $adapterindex)
				If IsObj($colItems2) Then
					For $objItem2 In $colItems2
						$adapterip = StringStripWS($objItem2.IPAddress(0), 8)
						$menuid = GUICtrlCreateMenuItem($adaptername & ' (' & $adapterip & ')', $InterfaceMenu)
						GUICtrlSetOnEvent($menuid, '_IPchanged')
						_ArrayAdd($InterfaceMenuID_Array, $menuid)
						_ArrayAdd($InterfaceMenuName_Array, $adaptername)
						_ArrayAdd($InterfaceMenuIP_Array, $adapterip)
						$InterfaceMenuID_Array[0] = UBound($InterfaceMenuID_Array) - 1
						$InterfaceMenuIP_Array[0] = UBound($InterfaceMenuIP_Array) - 1
						If $adaptername = $DefaultName Then
							$FoundIP = 1
							$DefaultIntMenuID = $menuid
							$DefaultName = $InterfaceMenuName_Array[1]
							$DefaultIP = $InterfaceMenuIP_Array[1]
							GUICtrlSetState($menuid, $GUI_CHECKED)
						EndIf
					Next
				EndIf
			EndIf
		Next
	EndIf
	If $FoundIP = 0 And $InterfaceMenuID_Array[0] <> 0 Then
		$DefaultIntMenuID = $InterfaceMenuID_Array[1]
		$DefaultName = $InterfaceMenuName_Array[1]
		$DefaultIP = $InterfaceMenuIP_Array[1]
		GUICtrlSetState($DefaultIntMenuID, $GUI_CHECKED)
	EndIf
EndFunc   ;==>_AddInterfaces

Func _RefreshInterfaces()
	;Remove Menu Items
	For $ri = 1 To $InterfaceMenuID_Array[0]
		$menuid = $InterfaceMenuID_Array[$ri]
		GUICtrlDelete($menuid)
	Next
	GUICtrlDelete($RefreshInterfaces)
	;Add updated interfaces
	_AddInterfaces()
EndFunc   ;==>_RefreshInterfaces

Func _IPchanged()
	$menuid = @GUI_CtrlId
	For $fs = 1 To $InterfaceMenuID_Array[0]
		If $InterfaceMenuID_Array[$fs] = $menuid Then
			$NewName = $InterfaceMenuName_Array[$fs]
			$NewIP = $InterfaceMenuIP_Array[$fs]
			If $NewName <> $DefaultName Then
				If $DefaultIntMenuID <> '-1' Then GUICtrlSetState($DefaultIntMenuID, $GUI_UNCHECKED)
				$DefaultIntMenuID = $menuid
				$DefaultName = $NewName
				$DefaultIP = $NewIP
				GUICtrlSetState($DefaultIntMenuID, $GUI_CHECKED)
			EndIf
		EndIf
	Next
	ConsoleWrite($DefaultIntMenuID & @CRLF & $DefaultName & @CRLF & $DefaultIP & @CRLF)
EndFunc   ;==>_IPchanged

;-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
; Extra Menu Functions
;-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

;---> 5100 set telnet info GUI <---

Func _Set5100telnetinfo()
	$5100InfoGUI = GUICreate("5100 Modem Info", 219, 164)
	GUICtrlCreateLabel("Modem IP", 10, 5, 128, 15)
	$ModemIP = GUICtrlCreateInput($5100telnetIP, 10, 20, 200, 20)
	GUICtrlCreateLabel("Telnet Username", 10, 45, 128, 15)
	$User = GUICtrlCreateInput($5100telnetUN, 10, 60, 200, 21)
	GUICtrlCreateLabel("Telnet Password", 10, 85, 128, 15)
	$Pass = GUICtrlCreateInput($5100telnetPW, 10, 100, 200, 21, $ES_PASSWORD)
	$ButtonOK = GUICtrlCreateButton("OK", 10, 130, 95, 25)
	$ButtonCan = GUICtrlCreateButton("Cancel", 110, 130, 95, 25)
	GUISetState(@SW_SHOW)

	GUICtrlSetOnEvent($ButtonOK, '_Set5100telnetinfoOK')
	GUICtrlSetOnEvent($ButtonCan, '_Set5100telnetinfoClose')
EndFunc   ;==>_Set5100telnetinfo

Func _Set5100telnetinfoOK()
	$5100telnetIP = GUICtrlRead($ModemIP)
	$5100telnetUN = GUICtrlRead($User)
	$5100telnetPW = GUICtrlRead($Pass)
	$5100telnetSet = 1
	_Set5100telnetinfoClose()
EndFunc   ;==>_Set5100telnetinfoOK

Func _Set5100telnetinfoClose()
	GUIDelete($5100InfoGUI)
EndFunc   ;==>_Set5100telnetinfoClose

;---> 5101 set telnet info GUI <---

Func _Set5101telnetinfo()
	$5101InfoGUI = GUICreate("5101 Modem Info", 219, 164)
	GUICtrlCreateLabel("Modem IP", 10, 5, 128, 15)
	$ModemIP = GUICtrlCreateInput($5101telnetIP, 10, 20, 200, 20)
	GUICtrlCreateLabel("Telnet Username", 10, 45, 128, 15)
	$User = GUICtrlCreateInput($5101telnetUN, 10, 60, 200, 21)
	GUICtrlCreateLabel("Telnet Password", 10, 85, 128, 15)
	$Pass = GUICtrlCreateInput($5101telnetPW, 10, 100, 200, 21, $ES_PASSWORD)
	$ButtonOK = GUICtrlCreateButton("OK", 10, 130, 95, 25)
	$ButtonCan = GUICtrlCreateButton("Cancel", 110, 130, 95, 25)
	GUISetState(@SW_SHOW)

	GUICtrlSetOnEvent($ButtonOK, '_Set5101telnetinfoOK')
	GUICtrlSetOnEvent($ButtonCan, '_Set5101telnetinfoClose')
EndFunc   ;==>_Set5101telnetinfo

Func _Set5101telnetinfoOK()
	$5101telnetIP = GUICtrlRead($ModemIP)
	$5101telnetUN = GUICtrlRead($User)
	$5101telnetPW = GUICtrlRead($Pass)
	$5101telnetSet = 1
	_Set5101telnetinfoClose()
EndFunc   ;==>_Set5101telnetinfoOK

Func _Set5101telnetinfoClose()
	GUIDelete($5101InfoGUI)
EndFunc   ;==>_Set5101telnetinfoClose

;---> 6120 set ssj info GUI <---

Func _Set6120sshinfo()
	$6120InfoGUI = GUICreate("6120 Modem Info", 219, 164)
	GUICtrlCreateLabel("Modem IP", 10, 5, 128, 15)
	$ModemIP = GUICtrlCreateInput($6120sshIP, 10, 20, 200, 20)
	GUICtrlCreateLabel("SSH Username", 10, 45, 128, 15)
	$User = GUICtrlCreateInput($6120sshUN, 10, 60, 200, 21)
	GUICtrlCreateLabel("SSH Password", 10, 85, 128, 15)
	$Pass = GUICtrlCreateInput($6120sshPW, 10, 100, 200, 21, $ES_PASSWORD)
	$ButtonOK = GUICtrlCreateButton("OK", 10, 130, 95, 25)
	$ButtonCan = GUICtrlCreateButton("Cancel", 110, 130, 95, 25)
	GUISetState(@SW_SHOW)

	GUICtrlSetOnEvent($ButtonOK, '_Set6120sshinfoOK')
	GUICtrlSetOnEvent($ButtonCan, '_Set6120sshinfoClose')
EndFunc   ;==>_Set6120sshinfo

Func _Set6120sshinfoOK()
	$6120sshIP = GUICtrlRead($ModemIP)
	$6120sshUN = GUICtrlRead($User)
	$6120sshPW = GUICtrlRead($Pass)
	$6120sshSet = 1
	_Set6120sshinfoClose()
EndFunc   ;==>_Set6120sshinfoOK

Func _Set6120sshinfoClose()
	GUIDelete($6120InfoGUI)
EndFunc   ;==>_Set6120sshinfoClose

;---> Set Modem to selected mac adress <---

Func _Set5100selctedmac()
	_Setselctedmac("5100")
EndFunc   ;==>_Set5100selctedmac

Func _Set5101selctedmac()
	_Setselctedmac("5101")
EndFunc   ;==>_Set5101selctedmac

Func _Set6120selctedmac()
	_Setselctedmac("6120")
EndFunc   ;==>_Set6120selctedmac

Func _Setselctedmac($type)
	If $5100telnetSet = 0 And $type = "5100" Then
		MsgBox(0, "Error", "Set 5100 telnet info first")
	ElseIf $5101telnetSet = 0 And $type = "5101" Then
		MsgBox(0, "Error", "Set 5101 telnet info first")
	ElseIf $6120sshSet = 0 And $type = "6120" Then
		MsgBox(0, "Error", "Set 6120 ssh info first")
	Else
		$Selected = _GUICtrlListView_GetNextItem($ConfList); find what config is selected in the list. returns -1 is nothing is selected
		If $Selected <> "-1" Then
			Local $ConfigMatchArray, $iRows, $iColumns, $iRval
			$query = "SELECT mac FROM CONFIGDATA WHERE line='" & $Selected & "'"
			$iRval = _SQLite_GetTable2d($DBhndl, $query, $ConfigMatchArray, $iRows, $iColumns)
			If $iRows <> 0 Then ;If Configs found, write to file
				$mac = $ConfigMatchArray[1][0]
				GUICtrlSetData($messagebox, "Setting modem mac to " & $mac)
				If $type = "5100" Then _Set5100mac($mac)
				If $type = "5101" Then _Set5101mac($mac)
				If $type = "6120" Then _Set6120mac($mac)
			EndIf
		Else
			MsgBox(0, "Error", "No config selected")
		EndIf
	EndIf
EndFunc   ;==>_Setselctedmac

;---> Set Modem to all mac address in the list <---

Func _Set5100toallmacs()
	_Settoallmacs("5100")
EndFunc   ;==>_Set5100toallmacs

Func _Set5101toallmacs()
	_Settoallmacs("5101")
EndFunc   ;==>_Set5101toallmacs

Func _Set6120toallmacs()
	_Settoallmacs("6120")
EndFunc   ;==>_Set6120toallmacs

Func _Settoallmacs($type)
	If $5100telnetSet = 0 And $type = "5100" Then
		MsgBox(0, "Error", "Set 5100 telnet info first")
	ElseIf $5101telnetSet = 0 And $type = "5101" Then
		MsgBox(0, "Error", "Set 5101 telnet info first")
	ElseIf $6120sshSet = 0 And $type = "6120" Then
		MsgBox(0, "Error", "Set 6120 ssh info first")
	Else
		Local $ConfigMatchArray, $iRows, $iColumns, $iRval, $waittime
		$fldatetimestamp = StringFormat("%04i", @YEAR) & '-' & StringFormat("%02i", @MON) & '-' & StringFormat("%02i", @MDAY) & ' ' & @HOUR & '-' & @MIN & '-' & @SEC
		$file = FileSaveDialog('Save As', '', 'Coma Delimeted File (*.CSV)', '', $fldatetimestamp & '.CSV')
		If @error <> 1 Then
			If $type = "5100" Then $waittime = InputBox("Time to wait before mac change", "Time (in seconds)", "30")
			If $type = "5101" Then $waittime = InputBox("Time to wait before mac change", "Time (in seconds)", "65")
			If $type = "6120" Then $waittime = InputBox("Time to wait before mac change", "Time (in seconds)", "75")
			If Not @error Then
				GUICtrlSetData($messagebox, "Setting ip to 192,168.100.2")
				_RunDOS('netsh inter ip set address "' & $DefaultName & '" source=static addr="192.168.100.2" mask="255.255.255.0" gateway=none')
				Sleep(5000)
				FileWrite($file, 'Mac Address,Client IP,TFTP IP,Config,Info,Times Seen,configtxt(hex)' & @CRLF)
				$query = "SELECT mac, client, tftp FROM CONFIGDATA"
				$iRval = _SQLite_GetTable2d($DBhndl, $query, $ConfigMatchArray, $iRows, $iColumns)
				If $iRows <> 0 Then ;If Configs found, write to file
					For $cm = 1 To $iRows
						;Change modem Mac Adress
						$mac = $ConfigMatchArray[$cm][0]
						$client = $ConfigMatchArray[$cm][1]
						$tftp = $ConfigMatchArray[$cm][2]
						GUICtrlSetData($messagebox, "Setting modem mac to " & $mac & " (" & _GetTime() & ")")
						If $type = "5100" Then _Set5100mac($mac)
						If $type = "5101" Then _Set5101mac($mac)
						If $type = "6120" Then _Set6120mac($mac)
						;wait for modem to reboot
						GUICtrlSetData($messagebox, "Waiting " & $waittime & " seconds for modem to reboot with mac " & $mac & " (" & _GetTime() & ")")
						Sleep($waittime * 1000)
						;Pull config from modem
						GUICtrlSetData($messagebox, "Trying to download and decode config from modem for mac " & $mac & " (" & _GetTime() & ")")
						If $type = "5100" Then $conflocinfo = _Get5100config()
						If $type = "5101" Then $conflocinfo = _Get5101config()
						If $type = "6120" Then $conflocinfo = _Get6120config($mac)
						;Decode config file downloaded above
						$configtxt = ""
						$configname = ""
						$infostring = ""
						If $conflocinfo[0] = 1 Then
							$config_destfile = $conflocinfo[1]
							$configname = $conflocinfo[2]
							$decodedconfig = _DecodeConfig($config_destfile)
							If $decodedconfig <> "" Then $configtxt = $decodedconfig
							$configinfo = _GetConfigInfo($decodedconfig)
							If $configinfo <> "" Then $infostring = $configinfo
						EndIf
						;write to new configstumbler csv file
						FileWrite($file, '"' & $mac & '",' & $client & ',' & $tftp & ',"' & $configname & '","' & $infostring & '",1,' & StringToBinary($configtxt) & @CRLF)
					Next
				EndIf
				GUICtrlSetData($messagebox, "Done setting macs ")
			Else
				GUICtrlSetData($messagebox, "Error setting time to wait :-/")
			EndIf
		EndIf
	EndIf
EndFunc   ;==>_Settoallmacs

;---> Change mac address on modem until it gets online <---

Func _Set5100toallmacstilonline()
	_Settoallmacstilonline("5100")
EndFunc   ;==>_Set5100toallmacstilonline

Func _Set5101toallmacstilonline()
	_Settoallmacstilonline("5101")
EndFunc   ;==>_Set5101toallmacstilonline

Func _Set6120toallmacstilonline()
	_Settoallmacstilonline("6120")
EndFunc   ;==>_Set6120toallmacstilonline

Func _Settoallmacstilonline($type)
	If $5100telnetSet = 0 And $type = "5100" Then
		MsgBox(0, "Error", "Set 5100 telnet info first")
	ElseIf $5101telnetSet = 0 And $type = "5101" Then
		MsgBox(0, "Error", "Set 5101 telnet info first")
	ElseIf $6120sshSet = 0 And $type = "6120" Then
		MsgBox(0, "Error", "Set 6120 ssh info first")
	Else
		Local $ConfigMatchArray, $iRows, $iColumns, $iRval, $waittime
		If $type = "5100" Then $waittime = InputBox("Time to wait before mac change", "Time (in seconds)", "30")
		If $type = "5101" Then $waittime = InputBox("Time to wait before mac change", "Time (in seconds)", "65")
		If $type = "6120" Then $waittime = InputBox("Time to wait before mac change", "Time (in seconds)", "75")
		If Not @error Then
			$query = "SELECT mac FROM CONFIGDATA"
			$iRval = _SQLite_GetTable2d($DBhndl, $query, $ConfigMatchArray, $iRows, $iColumns)
			If $iRows <> 0 Then
				For $cm = 1 To $iRows
					$mac = $ConfigMatchArray[$cm][0]
					;Change lan ip to static
					GUICtrlSetData($messagebox, _GetTime() & ": Setting nic ip to 192.168.100.2")
					_RunDOS('netsh inter ip set address "' & $DefaultName & '" source=static addr="192.168.100.2" mask="255.255.255.0" gateway=none')
					Sleep(5000);Wait for ip changes
					;Change Modem Mac Adress
					GUICtrlSetData($messagebox, _GetTime() & ": Setting modem mac to " & $mac & "(" & $cm & "/" & $iRows & ")")
					If $type = "5100" Then _Set5100mac($mac)
					If $type = "5101" Then _Set5101mac($mac)
					If $type = "6120" Then _Set6120mac($mac)
					;Change lan ip to dhcp
					GUICtrlSetData($messagebox, _GetTime() & ": Setting nic ip to dhcp")
					_RunDOS('netsh inter ip set address "' & $6120netcon & '" source=dhcp')
					GUICtrlSetData($messagebox, _GetTime() & ": Waiting " & $waittime & " seconds for modem to reboot with mac " & $mac & "(" & $cm & "/" & $iRows & ")")
					Sleep($waittime * 1000);Wait for modem to boot and dhcp change to take effect
					;Test Internet Connection
					GUICtrlSetData($messagebox, _GetTime() & ": Checking internet conntection with mac " & $mac)
					If _TestInternetConnection() = 1 Then
						;Modem is online
						GUICtrlSetData($messagebox, _GetTime() & ": Online with mac " & $mac & "! :-D")
						Sleep(1000)
						ExitLoop
					EndIf
				Next
			EndIf
			GUICtrlSetData($messagebox, "Done setting macs ")
		Else
			GUICtrlSetData($messagebox, "Error setting time to wait :-/")
		EndIf
	EndIf
EndFunc   ;==>_Settoallmacstilonline

Func _TestInternetConnection()
	$return = 0
	$s1 = "www.google.com"
	$s2 = "www.msn.com"
	$s3 = "www.yahoo.com"
	Ping($s1)
	If Not @error Then
		$return = 1
	Else
		Ping($s2)
		If Not @error Then
			$return = 1
		Else
			Ping($s3)
			If Not @error Then $return = 1
		EndIf
	EndIf
	Return ($return)
EndFunc   ;==>_TestInternetConnection

;---> Change mac address on modem <---

Func _Set5100mac($mac)
	$cmd = '"' & $PuttyEXE & '" -telnet ' & $5100telnetUN & '@' & $5100telnetIP
	Run(@ComSpec & ' /c ' & $cmd, '', @SW_HIDE, 2)
	WinActivate($5100telnetIP & " - PuTTY")
	WinWaitActive($5100telnetIP & " - PuTTY")
	Send("{ENTER}")
	Sleep(50)
	Send($5100telnetUN)
	Sleep(50)
	Send("{ENTER}")
	Sleep(50)
	Send($5100telnetPW)
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
	Sleep(50)
	Send("{ENTER}")
	Sleep(1000)
	While WinExists($5100telnetIP & " - PuTTY")
		If WinExists("PuTTY Fatal Error") Then
			WinActive("PuTTY Fatal Error")
			Send("{ENTER}")
		EndIf
		If WinExists("PuTTY Exit Confirmation") Then
			WinActivate("PuTTY Exit Confirmation")
			Send("{ENTER}")
		EndIf
		If WinExists($5100telnetIP & " - PuTTY") Then
			WinActivate($5100telnetIP & " - PuTTY")
			Send("!{F4}")
		EndIf
		Sleep(1000)
	WEnd
	Return ($mac)
EndFunc   ;==>_Set5100mac

Func _Set5101mac($mac)
	$scriptfilename = @ScriptDir & '\5101script.txt'
	FileDelete($scriptfilename)
	$scriptfile = $5101telnetIP & ' 23' & @CRLF _
			 & 'WAIT "Username:"' & @CRLF _
			 & 'SEND "' & $5101telnetUN & '\m"' & @CRLF _
			 & 'WAIT "Password:"' & @CRLF _
			 & 'SEND "' & $5101telnetPW & '\m"' & @CRLF _
			 & 'WAIT ">"' & @CRLF _
			 & 'SEND "cd non-vol\m"' & @CRLF _
			 & 'WAIT ">"' & @CRLF _
			 & 'SEND "cd halif\m"' & @CRLF _
			 & 'WAIT ">"' & @CRLF _
			 & 'SEND "mac_address 1 ' & $mac & '\m"' & @CRLF _
			 & 'WAIT ">"' & @CRLF _
			 & 'SEND "write\m"' & @CRLF _
			 & 'WAIT ">"' & @CRLF _
			 & 'SEND "cd \\\m"' & @CRLF _
			 & 'WAIT ">"' & @CRLF _
			 & 'SEND "reset\m"' & @CRLF
	ConsoleWrite($scriptfile & @CRLF)
	FileWrite($scriptfilename, $scriptfile)

	$cmd = $TST10EXE & ' /r:"' & $scriptfilename & '" /o:output.txt'
	RunWait($cmd)
	FileDelete($scriptfilename)
	ConsoleWrite($cmd & @CRLF)
EndFunc   ;==>_Set5101mac

Func _Set6120mac($mac)
	$cmd = '"' & $PuttyEXE & '" -ssh ' & $6120sshUN & '@' & $6120sshIP
	$putty = Run(@ComSpec & ' /c ' & $cmd, '', @SW_HIDE, 2)
	WinActivate($6120sshIP & " - PuTTY")
	WinWaitActive($6120sshIP & " - PuTTY")
	Sleep(2000)
	Send($6120sshPW)
	Sleep(50)
	Send("{ENTER}")
	Sleep(1000)
	Send("/usr/local/bin/mfprod write cmMacAddress " & $mac)
	Sleep(50)
	Send("{ENTER}")
	Sleep(50)
	Send("reboot")
	Sleep(50)
	Send("{ENTER}")
	Sleep(1000)
	While (WinExists($6120sshIP & " - PuTTY") Or WinExists("PuTTY (inactive)"))
		If WinExists("PuTTY Fatal Error") Then
			WinActive("PuTTY Fatal Error")
			Sleep(1000)
			Send("{ENTER}")
		EndIf
		If WinExists("PuTTY Exit Confirmation") Then
			WinActivate("PuTTY Exit Confirmation")
			Sleep(1000)
			Send("{ENTER}")
		EndIf
		If WinExists($6120sshIP & " - PuTTY") Then
			WinActivate($6120sshIP & " - PuTTY")
			Sleep(1000)
			Send("!{F4}")
		EndIf
		If WinExists("PuTTY (inactive)") Then
			WinActivate("PuTTY (inactive)")
			Sleep(1000)
			Send("!{F4}")
		EndIf
		Sleep(1000)
	WEnd
	Return ($mac)
EndFunc   ;==>_Set6120mac

;---> Download config from modem <---

Func _Get5100config()
	Local $return[3]
	$return[0] = "0"
	$webpagesource = _INetGetSource("http://" & $5100telnetIP & ":1337/advanced.html")
	If StringInStr($webpagesource, 'TFTP config file: ') Then
		$tws = StringSplit($webpagesource, "TFTP config file: ", 1)
		;_ArrayDisplay($tws)
		$tws2 = StringSplit($tws[2], ">", 1)
		$configname = StringReplace(StringReplace($tws2[1], "<a href='", ""), "</center", "")
		If StringRight($configname, 1) = "'" Then $configname = StringTrimRight($configname, 1)

		If $configname <> "Not yet provisioned" Then
			$downfile = "http://" & $5100telnetIP & ":1337/" & $configname
			$savefile = $ConfDir & $configname & '.cfg'
			InetGet($downfile, $savefile)
			If FileExists($savefile) Then
				$return[0] = "1"
				$return[1] = $savefile
				$return[2] = $configname
			EndIf
		EndIf
	EndIf
	Return $return
EndFunc

Func _Get5101config()
	Local $return[3]
	$return[0] = "0"
	$webpagesource = _INetGetSource("http://" & $5101telnetIP & "/overview.html")
	If StringInStr($webpagesource, '<a href="getcfg.cgi">') Then
		$tws = StringSplit($webpagesource, '<a href="getcfg.cgi">', 1)
		$tws2 = StringSplit($tws[2], "</a>", 1)
		$configname = StringStripWS($tws2[1], 8)
		$downfile = "http://" & $5101telnetIP & "/getcfg.cgi"
		$savefile = $ConfDir & $configname & '.cfg'
		InetGet($downfile, $savefile)
		If FileExists($savefile) Then
			$return[0] = "1"
			$return[1] = $savefile
			$return[2] = $configname
		EndIf
	EndIf
	Return $return
EndFunc

Func _Get6120config($mac)
	Local $return[3]
	$return[0] = "0"
	$configname = StringReplace($mac, ":", "")
	$savefile = $ConfDir & $configname & '.cfg'
	$cmd = '"' & $pscpEXE & '" -pw ' & $6120sshPW & ' ' & $6120sshUN & '@' & $6120sshIP & ':/forceware/config.running "' & $savefile & '"'
	$pscp = Run($cmd)
	Sleep(2000)
	If FileExists($savefile) Then
		$return[0] = "1"
		$return[1] = $savefile
		$return[2] = $configname
	EndIf
	Return $return
EndFunc

;---> Test downloding configs from a tftp server in a mac address range

Func _TestMacRangeGUI()
	$tmrGUI = GUICreate("Scan Mac Range", 406, 409, 192, 114)
	GUICtrlCreateGroup("Brute Force Method", 17, 10, 369, 245)
	$rNone = GUICtrlCreateRadio("None - Just load mac addresses into list", 27, 30, 350, 17)
	$rTFTP = GUICtrlCreateRadio("TFTP - base config on prefix and suffix, download from tftp", 27, 50, 350, 17)
	GUICtrlCreateLabel("TFTP Server:", 57, 75, 68, 17)
	$iTFTP = GUICtrlCreateInput($mactftp, 137, 70, 225, 21)
	GUICtrlCreateLabel("Mac Prefix", 57, 100, 54, 17)
	$iPrefix = GUICtrlCreateInput($macpre, 137, 95, 225, 21)
	GUICtrlCreateLabel("Mac Suffix", 57, 125, 54, 17)
	$iSuffix = GUICtrlCreateInput($macsuf, 137, 120, 225, 21)
	$rSB5100 = GUICtrlCreateRadio("SB5100 - Change mac using telnet, download config from modem", 27, 150, 350, 17)
	$rSB5101 = GUICtrlCreateRadio("SB5101 - Change mac using telnet, download config from modem", 27, 170, 350, 17)
	$rSB6120 = GUICtrlCreateRadio("SB6120 - Change mac using ssh, download config from modem", 27, 190, 350, 17)
	GUICtrlCreateLabel("Wait until online(secs):", 30, 220, 110, 17)
	$iWaitTime = GUICtrlCreateInput("75", 139, 215, 225, 21)
	$Group2 = GUICtrlCreateGroup("Mac Range to Scan", 16, 264, 369, 97)
	GUICtrlCreateLabel("Start Mac", 30, 302, 50, 17)
	$iStartMac = GUICtrlCreateInput($startmac, 110, 297, 225, 21)
	GUICtrlCreateLabel("End Mac", 30, 327, 47, 17)
	$iEndMac = GUICtrlCreateInput($endmac, 110, 322, 225, 21)
	$rOK = GUICtrlCreateButton("Start", 8, 370, 95, 25, $WS_GROUP)
	$rCAN = GUICtrlCreateButton("Cancel", 114, 370, 95, 25, $WS_GROUP)
	GUICtrlSetOnEvent($rOK, '_TestMacRangeGUIOK')
	GUICtrlSetOnEvent($rCAN, '_TestMacRangeGUIClose')
	GUISetState(@SW_SHOW)
EndFunc   ;==>_TestMacRangeGUI

Func _TestMacRangeGUIOK()
	$startmac = GUICtrlRead($iStartMac)
	$startmacf = StringReplace(StringReplace($startmac, ":", ""), "-", "")
	$startmac1 = '0x' & StringLeft($startmacf, 6)
	$startmac2 = '0x' & StringRight($startmacf, 6)
	$endmac = GUICtrlRead($iEndMac)
	$endmacf = StringReplace(StringReplace($endmac, ":", ""), "-", "")
	$endmac1 = '0x' & StringLeft($endmacf, 6)
	$endmac2 = '0x' & StringRight($endmacf, 6)
	$macpre = GUICtrlRead($iPrefix)
	$macsuf = GUICtrlRead($iSuffix)
	$mactftp = GUICtrlRead($iTFTP)
	$wait = GuiCtrlRead($iWaitTime)
	$radnone = GuiCtrlRead($rNone)
	$radtftp = GuiCtrlRead($rTFTP)
	$rad5100 = GuiCtrlRead($rSB5100)
	$rad5101 = GuiCtrlRead($rSB5101)
	$rad6120 = GuiCtrlRead($rSB6120)
	_TestMacRangeGUIClose()
	For $ml = $startmac1 To $endmac1
		$manhex = Hex($ml, 6)
		For $cl = $startmac2 To $endmac2
			$chex = Hex($cl, 6)
			$fullmac = $manhex & $chex
			$configname = $macpre & StringLower($fullmac) & $macsuf
			GUICtrlSetData($messagebox, $fullmac)
			ConsoleWrite('-------------------' & @CRLF)
			ConsoleWrite($radnone & @CRLF)
			ConsoleWrite($radtftp & @CRLF)
			ConsoleWrite($rad5100 & @CRLF)
			ConsoleWrite($rad5101 & @CRLF)
			ConsoleWrite($rad6120 & @CRLF)
			If $radnone = 1 Then
				_InsertIntoDB($configname, "", $mactftp, $fullmac, "", "", 0)
			ElseIf $radtftp = 1 Then
				$InsertData = _InsertIntoDB($configname, "", $mactftp, $fullmac, "", "", 0)
				$fconfigid = $InsertData[1] ;DB Config ID
				_UpdateTftpInfoInDB($fconfigid, $mactftp, $configname);Update TFTP info
			ElseIf $rad5100 = 1 Then
				_Set5100mac($fullmac)
				Sleep($wait)
				$ConfData = _Get5100config()
				Local $decodedconfig = "", $configinfo = ""
				If $ConfData[0] = 1 Then
					$savefile = $ConfData[1]
					$configname = $ConfData[2]
					$decodedconfig = _DecodeConfig($savefile)
					$configinfo = _GetConfigInfo($decodedconfig)
				EndIf
				$InsertData = _InsertIntoDB($configname, "", $mactftp, $fullmac, $configinfo, $decodedconfig, 0)
			ElseIf $rad5101 = 1 Then
				_Set5101mac($fullmac)
				Sleep($wait)
				$ConfData = _Get5101config()
				Local $decodedconfig = "", $configinfo = ""
				If $ConfData[0] = 1 Then
					$savefile = $ConfData[1]
					$configname = $ConfData[2]
					$decodedconfig = _DecodeConfig($savefile)
					$configinfo = _GetConfigInfo($decodedconfig)
				EndIf
				$InsertData = _InsertIntoDB($configname, "", $mactftp, $fullmac, $configinfo, $decodedconfig, 0)
			ElseIf $rad6120 = 1 Then
				_Set6120mac($fullmac)
				Sleep($wait)
				$ConfData = _Get6120config($fullmac)
				Local $decodedconfig = "", $configinfo = ""
				If $ConfData[0] = 1 Then
					$savefile = $ConfData[1]
					$configname = $ConfData[2]
					$decodedconfig = _DecodeConfig($savefile)
					$configinfo = _GetConfigInfo($decodedconfig)
				EndIf
				$InsertData = _InsertIntoDB($configname, "", $mactftp, $fullmac, $configinfo, $decodedconfig, 0)
			EndIf
		Next
	Next
EndFunc   ;==>_TestMacRangeGUIOK

Func _TestMacRangeGUIClose()
	GUIDelete($tmrGUI)
EndFunc   ;==>_TestMacRangeGUIClose


;-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
; Button Functions
;-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

Func _ToggleScanning()
	If $Scan = 0 Then ;Start Scanning
		UDPStartup()
		$UDPsocket = UDPBind($DefaultIP, $UDPport)
		If @error = 0 Then
			$Scan = 1
			GUICtrlSetData($ScanButton, "Stop")
			GUICtrlSetData($messagebox, "Started - waiting for data")
		Else
			GUICtrlSetData($messagebox, "Error binding to ip (" & $DefaultIP & ":" & $UDPport & ")")
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
EndFunc   ;==>_ToggleOverrideTftp

Func _ImportConfigFile()
	$opencfgfile = FileOpenDialog("Select config file to import", $SavefDir, "Config files (*.cfg;*.cm)")
	If Not @error Then
		$config = StringTrimLeft($opencfgfile, StringInStr($opencfgfile, "\", 0, -1))
		$decodedconfig = _DecodeConfig($opencfgfile)
		$infostring = _GetConfigInfo($decodedconfig)
		;Add into list
		$ConfigID += 1
		$ListRow = _GUICtrlListView_InsertItem($ConfList, $ConfigID, -1)
		_ListViewAdd($ListRow, $ConfigID, "", "", "", "", $config, $infostring, 1)
		;Add into DB
		GUICtrlSetData($messagebox, 'Inserting into DB')
		$query = "INSERT INTO CONFIGDATA(configid,line,config,client,tftp,mac,info,times,configtxt) VALUES ('" & $ConfigID & "','" & $ListRow & "','" & $config & "','','','','" & $infostring & "','1','" & $decodedconfig & "');"
		_SQLite_Exec($DBhndl, $query)
		;Log line
		GUICtrlSetData($messagebox, 'Inserting into Log')
		FileWrite($configfile, '"",,,"' & $config & '","' & $infostring & '",1,' & StringToBinary($decodedconfig) & @CRLF)
	EndIf
EndFunc   ;==>_ImportConfigFile

Func _ImportConfigFolder()
	$opencfgfolder = FileSelectFolder("Select a folder with config files to import", "", 0,$ConfDir)
	If Not @error Then
		$cfgfiles = _FileListToArray($opencfgfolder)
		For $if = 1 to $cfgfiles[0]
			$configpath = $opencfgfolder & "\" & $cfgfiles[$if]
			$config = $cfgfiles[$if]
			$decodedconfig = _DecodeConfig($configpath)
			$infostring = _GetConfigInfo($decodedconfig)
			;Add into list
			$ConfigID += 1
			$ListRow = _GUICtrlListView_InsertItem($ConfList, $ConfigID, -1)
			_ListViewAdd($ListRow, $ConfigID, "", "", "", "", $config, $infostring, 1)
			;Add into DB
			GUICtrlSetData($messagebox, 'Inserting into DB')
			$query = "INSERT INTO CONFIGDATA(configid,line,config,client,tftp,mac,info,times,configtxt) VALUES ('" & $ConfigID & "','" & $ListRow & "','" & $config & "','','','','" & $infostring & "','1','" & $decodedconfig & "');"
			_SQLite_Exec($DBhndl, $query)
			;Log line
			GUICtrlSetData($messagebox, 'Inserting into Log')
			FileWrite($configfile, '"",,,"' & $config & '","' & $infostring & '",1,' & StringToBinary($decodedconfig) & @CRLF)
		Next
	EndIf
EndFunc   ;==>_ImportConfigFile

Func _SortColumnToggle(); Sets the conf list column header that was clicked
	$SortColumn = GUICtrlGetState($ConfList)
EndFunc   ;==>_SortColumnToggle

Func _HeaderSort($column);Sort a column in conf list
	If $Direction[$column] = 0 Then
		Dim $v_sort = False;set descending
	Else
		Dim $v_sort = True;set ascending
	EndIf
	If $Direction[$column] = 0 Then
		$Direction[$column] = 1
	Else
		$Direction[$column] = 0
	EndIf
	_GUICtrlListView_SimpleSort($ConfList, $v_sort, $column)
	_FixLineNumbers()
	$SortColumn = -1
EndFunc   ;==>_HeaderSort

Func _FixLineNumbers();Update Listview Row Numbers in DataArray
	$ListViewSize = _GUICtrlListView_GetItemCount($ConfList) - 1; Get List Size
	For $lisviewrow = 0 To $ListViewSize
		$LINENUM = _GUICtrlListView_GetItemText($ConfList, $lisviewrow, 0)
		$query = "UPDATE CONFIGDATA SET line = '" & $lisviewrow & "' WHERE configid = '" & $LINENUM & "'"
		_SQLite_Exec($DBhndl, $query)
	Next
EndFunc   ;==>_FixLineNumbers