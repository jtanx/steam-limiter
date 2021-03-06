!include MUI.nsh
!include UAC.nsh

!ifndef OutDir
!define OutDir "..\vs2010\release"
!endif

/*
 * Extract the designed version information from the resource header.
 */

!searchparse /file ..\limitver.h "#define VER_MAJOR       " VER_MAJOR
!searchparse /file ..\limitver.h "#define VER_MINOR       " VER_MINOR
!searchparse /file ..\limitver.h "#define VER_BUILD       " VER_BUILD
!searchparse /file ..\limitver.h "#define VER_REV         " VER_REV
!searchparse /file ..\limitver.h "#define VER_COMPANYNAME_STR " VER_AUTHOR
!searchparse /file ..\limitver.h "#define VER_WEBSITE_STR " VER_WEBSITE

/*
 * Describe the installer executable the NSIS compiler builds. Typically there
 * are two builds, one which writes the version-dependent name and one which
 * writes a fixed name, to make it easier to use the "custom build tool"
 * option in VS2010.
 */

!ifndef DUMMY
OutFile ${OutDir}\steamlimit-${VER_MAJOR}.${VER_MINOR}.${VER_BUILD}.${VER_REV}.exe
!else
OutFile ${OutDir}\installer.exe
!endif

SetCompressor /SOLID lzma

Name "Steam Content Server Limiter"
RequestExecutionLevel user

InstallDir "$LOCALAPPDATA\SteamLimiter"
InstallDirRegKey HKCU "Software\SteamLimiter" "InstallLocation"

Icon ..\steamlimit\monitor.ico

/*
 * The script language requires custom variable declarations here, not in the
 * section where the variables are used.
 */

Var SETTINGS

/*
 * Set the installer executable version information.
 */

VIProductVersion "${VER_MAJOR}.${VER_MINOR}.${VER_BUILD}.${VER_REV}"
VIAddVersionKey /LANG=${LANG_ENGLISH} "ProductName" "Steam Content Server Limiter"
VIAddVersionKey /LANG=${LANG_ENGLISH} "LegalCopyright" "� Nigel Bree <nigel.bree@gmail.com>"
VIAddVersionKey /LANG=${LANG_ENGLISH} "FileDescription" "Steam Content Server Limiter Install"
VIAddVersionKey /LANG=${LANG_ENGLISH} "FileVersion" "${VER_MAJOR}.${VER_MINOR}.${VER_BUILD}"
VIAddVersionKey /LANG=${LANG_ENGLISH} "Author" ${VER_AUTHOR}
VIAddVersionKey /LANG=${LANG_ENGLISH} "Website" ${VER_WEBSITE}

/*
 * Describe the installer flow, very minimal for us.
 */

Page License
LicenseData ..\LICENSE.txt

Page Directory
Page InstFiles

UninstPage UninstConfirm
UninstPage Instfiles

/*
 * For UAC-awareness, we ask the NSIS UAC plug-in to relaunch a nested copy of
 * the installer elevated, which can then call back function fragments as it
 * needs.
 *
 * This is per the UAC plugin wiki page, which is incorrect in most every other
 * respect (as it was rewritten from scratch for v0.2 of the plugin onwards and
 * the author has never documented the new version). This one aspect of the old
 * documentation seems to still work, though, and it's all we need.
 */

Function .onInit
  !insertmacro UAC_RunElevated
  ${Switch} $0
  ${Case} 0
    ${If} $1 == 1
      /*
       * The inner installer ran elevated.
       */
      quit
    ${ElseIf} $3 <> 0
      /*
       * We are the admin user already, let the outer install proceed.
       */

      ${Break}
    ${Endif}
    quit

  ${Default}
    quit

  ${EndSwitch}
FunctionEnd

Function runProgram
  Exec '"$INSTDIR\steamlimit.exe"'
FunctionEnd

Function quitProgram
  ExecWait '"$INSTDIR\steamlimit.exe" -quit'

  /*
   * Somewhat arbitrary delay, since executables on Windows can still be in-use
   * for a short time even after the processes that were running them have
   * called ExitProcess.
   */

  Sleep 20
FunctionEnd

Function quitOldProgram
  ExecWait '"$PROGRAMFILES\LimitSteam\steamlimit.exe" -quit'
  Sleep 20
FunctionEnd


Section
  StrCpy $SETTINGS "Software\SteamLimiter"

  IfFileExists $INSTDIR\steamlimit.exe 0 checkOldInstall
  !insertmacro UAC_AsUser_Call Function quitProgram ${UAC_SYNCINSTDIR}
  goto upgrade

checkOldInstall:
  /*
   * There are two upgrade scenarios; one where we uninstall from the current
   * install directory, but as I am moving towards using $LOCALAPPDATA as the
   * install directory there is also a need to migrate away from an older
   * install that was in $PROGRAMFILES.
   */

  IfFileExists $PROGRAMFILES\LimitSteam\steamlimit.exe 0 freshInstall
  !insertmacro UAC_AsUser_Call Function quitOldProgram ${UAC_SYNCINSTDIR}
  goto upgrade

freshInstall:
upgrade:
  /*
   * By default, run at login. Since our app is so tiny, this is hardly
   * intrusive and undoing it is a simple context-menu item.
   *
   * We're really doing a per-user install only, not a machine-wide install,
   * and as such the uninstall information should live in HKCU rather than
   * HKLM.
   */

  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Run" "SteamLimiter" \
                   "$\"$INSTDIR\steamlimit.exe$\""
  DeleteRegValue HKLM "SOFTWARE\Microsoft\Windows\CurrentVersion\Run" SteamLimit

  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\SteamLimiter" \
                   "DisplayName" "Steam Content Server Limiter"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\SteamLimiter" \
                   "UninstallString" "$\"$INSTDIR\uninst.exe$\""
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\SteamLimiter" \
                   "Publisher" "Nigel Bree <nigel.bree@gmail.com>"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\SteamLimiter" \
                   "URLInfoAbout" "steam-limiter.googlecode.com"

  WriteRegDWORD HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\SteamLimiter" \
                     "NoModify" "1"
  WriteRegDWORD HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\SteamLimiter" \
                     "NoRepair" "1"

  DeleteRegKey HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\SteamLimiter"
  DeleteRegKey HKLM "Software\SteamLimiter"

  WriteRegStr HKCU "Software\SteamLimiter" "InstallLocation" "$INSTDIR"

  /*
   * Before we write the new steamfilter.dll, deal with any stray copies of it
   * that are still referenced; rarely, versions prior to v0.5 would be able to
   * be confused by things like explorer.exe windows named "Steam" and so could
   * end up with the DLL injected in multiple places. Renaming the in-use DLL
   * works, so do that and then force it to be deleted.
   *
   * This also helps when Windows is just being stupid and hanging onto an open
   * reference to an executable after the process has exited (there are some
   * reasons for this, but they are frustrating because the APIs around this
   * are insufficient to write robust code).
   */

  Rename $INSTDIR\steamfilter.dll $INSTDIR\temp.dll
  Rename $INSTDIR\steamlimit.exe $INSTDIR\temp.exe

  /*
   * Now that I've moved Steam-limiter over to $LOCALAPPDATA, I can remove any
   * old machine-wide installation. Of course, if the install location has been
   * manually set to the old machine-wide location, I need to not wipe out the
   * directory and most of all I need to not do this *after* I install the
   * program in there. Because that would be stupid, as I learned by actually
   * having the install script do that. Ahem.
   */

  StrCmp "$INSTDIR" "$PROGRAMFILES\LimitSteam" noremove
  RMDir /r "$PROGRAMFILES\LimitSteam"
noRemove:

  SetOutPath $INSTDIR
  WriteUninstaller $INSTDIR\uninst.exe

  FILE ${OutDir}\probe.exe
  File ..\scripts\setfilter.js
  File ..\install\serverlist_generic.reg
  File ${OutDir}\steamlimit.exe
  File ${OutDir}\steamfilter.dll

  Delete /REBOOTOK $INSTDIR\temp.dll
  Delete /REBOOTOK $INSTDIR\temp.exe

  /*
   * Put a shortcut into the Start menu in the "Steam" folder, where Valve
   * tend to put Steam content like games so it's open for us to use.
   */

  CreateDirectory "$SMPROGRAMS\Steam"
  CreateShortcut "$SMPROGRAMS\Steam\Start steam-limiter.lnk" \
                "$INSTDIR\steamlimit.exe"

  /*
   * Set the registry keys for the version options; from time to time we can
   * check the webservice to see if an update is available. Writing the current
   * version is a little redundant since it's in the monitor's resources, but
   * that's not always convenient to dig out in e.g. an upgrade script so there
   * seems little harm keeping another copy of the version string around.
   *
   * Of course, comparing *string* versions instead of *numeric* versions is
   * not always ideal. Since this is my own personal project, let's just say
   * that I'm expecting future me not to have to make that many distinct builds
   * and to be able to offload data changes to a webservice.
   */

  WriteRegStr HKCU $SETTINGS "LastVersion" \
                   "${VER_MAJOR}.${VER_MINOR}.${VER_BUILD}.${VER_REV}"
  WriteRegStr HKCU $SETTINGS "NextVersion" \
                   "${VER_MAJOR}.${VER_MINOR}.${VER_BUILD}.${VER_REV}"

  /*
   * There's a whole system for replacing HTTP documents designed for v0.5.6,
   * and for now I'm usually getting the replacement content from the registry.
   * The ideal format for that is REG_MULTI_SZ but NSIS is awful at that, so I
   * could include a .REG file and exec "REG IMPORT" to install it (which looks
   * nice except that the REG_MULTI_SZ export format is hex) or I can use a
   * REG_SZ format string instead. Since NSIS's string quoting is so awful the
   * REG_SZ isn't really maintainable, so REG it is.
   */

  DetailPrint 'Execute: reg import $\"$INSTDIR\serverlist_generic.reg$\"'
  nsExec::ExecToLog 'reg import "$INSTDIR\serverlist_generic.reg"'

  /*
   * See if there's an existing setting under HKCU - if so, preserve it and
   * just move on to launching the monitor app.
   */

  ReadRegStr $0 HKCU $SETTINGS "Server"
  IfErrors detectHomeProfile

gotServerValue:
  /*
   * The existing server setting can get migrated to the "custom" profile, and
   * unless it's one we know already we can select the custom profile as well.
   * If it's one of the 3 ones baked into pre-v0.5 installs we can take that as
   * a sign to use the "home" profile instead as we do for fresh installs.
   *
   * Most of the pre-0.5 installs which need custom servers are in Australia
   * and the new server-side filters should support them better (as they all
   * allow multiple servers to be used), but users should discover the "home"
   * profile option reasonably quickly.
   */

  WriteRegStr HKCU "$SETTINGS\C" "Filter" $0

  StrCmp $0 "203.167.129.4" 0 notTelstra

  WriteRegStr HKCU "$SETTINGS\C" "Country" "NZ"
  WriteRegStr HKCU "$SETTINGS\C" "ISP" "TelstraClear New Zealand"
  goto detectHomeProfile

notTelstra:
  StrCmp $0 "219.88.241.90" 0 notOrcon

  WriteRegStr HKCU "$SETTINGS\C" "Country" "NZ"
  WriteRegStr HKCU "$SETTINGS\C" "ISP" "Orcon New Zealand"
  goto detectHomeProfile

notOrcon:
  StrCmp $0 "202.124.127.66" 0 notSnap

  WriteRegStr HKCU "$SETTINGS\C" "Country" "NZ"
  WriteRegStr HKCU "$SETTINGS\C" "ISP" "Snap! New Zealand"
  goto detectHomeProfile

notSnap:
  /*
   * Stick with the custom profile.
   */

  WriteRegStr HKCU "$SETTINGS\C" "Country" "AU"
  WriteRegStr HKCU "$SETTINGS\C" "ISP" "Unknown"
  WriteRegDWORD HKCU $SETTINGS "Profile" 3

detectHomeProfile:
  /*
   * We don't have an existing setting - try and auto-configure the right
   * one based on detecting the upstream ISP using a web service. There's
   * a small script to do this which we can run (elevated if necessary).
   */

  ExecWait 'wscript "$INSTDIR\setfilter.js" install'
  IfErrors 0 setProfile
    /*
     * This value is for TelstraClear; use it if we have to.
     */

    StrCpy $0 "*:27030=wlgwpstmcon01.telstraclear.co.nz"
    WriteRegStr HKCU "$SETTINGS\A" "Filter" $0
    WriteRegStr HKCU "$SETTINGS\A" "Country" "NZ"
    WriteRegStr HKCU "$SETTINGS\A" "ISP" "TelstraClear New Zealand"

setProfile:
  ReadRegDWORD $0 HKCU $SETTINGS "Profile"
  IfErrors 0 finishInstall
    /*
     * If there's an existing profile selection, leave it.
     * Otherwise, default to the "home" profile.
     */

    WriteRegDWORD HKCU $SETTINGS "Profile" 1

finishInstall:
  /*
   * Remove pre-v0.5 settings that were moved to profile options.
   */

  DeleteRegValue HKCU $SETTINGS "Server"
  DeleteRegValue HKCU $SETTINGS "ISP"

  !insertmacro UAC_AsUser_Call Function runProgram ${UAC_SYNCINSTDIR}
SectionEnd

Section "Uninstall"
  ExecWait "$INSTDIR\steamlimit.exe -quit"

  /*
   * Somewhat arbitrary delay, since executables on Windows can still be in-use
   * for a short time even after the processes that were running them have
   * called ExitProcess.
   */

  Sleep 20

  Delete "$INSTDIR\serverlist_generic.reg"
  Delete "$INSTDIR\setfilter.js"
  Delete "$INSTDIR\uninst.exe"
  Delete "$INSTDIR\probe.exe"
  Delete "$INSTDIR\steamlimit.exe"
  Delete "$INSTDIR\steamfilter.dll"
  Delete "$SMPROGRAMS\Steam\Start steam-limiter.lnk"

  RMDir "$INSTDIR"

  DeleteRegValue HKCU "SOFTWARE\Microsoft\Windows\CurrentVersion\Run" SteamLimit
  DeleteRegKey HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\SteamLimiter"

  /*
   * I used to clean all this up, but it seems friendlier to maintain some of the 
   * old configuration around. I will delete the replacement documents, but the
   * custom configuration data can sit around harmlessly.
   *
   * A particular thing that is kept by this is "InstallLocation" so that now
   * if the install location was previously customized, it stays customized on
   * future reinstalls even after uninstallation.
   */

  DeleteRegKey HKCU "Software\SteamLimiter\Replace"
  /* DeleteRegKey HKCU "Software\SteamLimiter" */
SectionEnd
