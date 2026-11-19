# Remote wake investigation

## Outcome and next implementation

Investigation closed for the current laptop configuration on November 18, 2026. Treat Wi-Fi wake as unavailable on this laptop: independent diagnostic packets and the user's Wolow test did not wake it. This is a practical compatibility decision, not proof that every MT7921 or every possible firmware/driver combination is incapable.

TapMyPC Android provides a [local Wi-Fi wake sender](setup.md#android-wake-on-lan). The user's desktop wakes with Wolow over Wi-Fi from sleep and hibernate after enabling PCIe resume in its BIOS. The user later confirmed that TapMyPC woke the desktop after the Android VPN routing fix. The user’s report confirms wake on that PC, and the Wolow tests separately confirm sleep and hibernate support.

## Laptop and documented support

- Lenovo Legion 5 Pro 16ACH6H, type 82JQ; BIOS GKCN65WW.
- MediaTek Wi-Fi 6 MT7921, driver 3.0.1.1336, dated May 13, 2022.
- Realtek PCIe GbE Ethernet controller, disconnected.
- Windows supports S3 sleep and hibernate; Modern Standby is unavailable.
- Charger connected during testing. The user inspected BIOS and found no wake/PCIe-resume setting.

Lenovo's [model specification](https://psref.lenovo.com/syspool/Sys/PDF/Legion/Legion_5_Pro_16ACH6H/Legion_5_Pro_16ACH6H_Spec.PDF) attaches the Wake-on-LAN/AC-power footnote to Ethernet, without documenting wireless wake. Installed BIOS and MediaTek driver versions match the [BIOS package](https://support.lenovo.com/fi/fi/downloads/ds549277-bios-update-for-windows-10-64-bit-legion-5-pro-16ach6h-legion-5-15ach6h-lenovo-legion-5-17ach6h) and [Windows 11 WLAN package](https://support.lenovo.com/pr/en/downloads/ds551503-wlan-driver-intel-realtek-for-windows-11-64-bit-legion-5-pro-16ach6h-legion-5-15ach6h-legion-5-17ach6h) checked. No documented wireless-wake fix or supported model-specific setup was found.

Lenovo article [HT513317](https://support.lenovo.com/nz/en/solutions/ht513317-wi-fi-card-does-not-wake-from-s3-or-s4-mode-sleep-or-hibernate-thinkstation) describes motherboard limitations with MT7921 on ThinkStation P340/P350. It does not apply to this Legion and is not proof of its limitation. No Lenovo engineer confirmed this laptop's WoWLAN support, and no support ticket was submitted.

## Configuration versus capability

Initially the Wi-Fi adapter was not wake-armed. The user ran this from Administrator PowerShell:

```powershell
powercfg /deviceenablewake "MediaTek Wi-Fi 6 MT7921 Wireless LAN Card"
```

Afterward powercfg listed it in wake_armed and MSPower_DeviceWakeEnable reported True. Advanced driver settings and NDIS WMI configuration indicated enabled magic/pattern wake. Generic PnP power data also advertised wake capability.

However, the elevated Get-NetAdapterPowerManagement probe returned AllowComputerToTurnOffDevice=2, WakeOnMagicPacket=0 and WakeOnPattern=0. Microsoft's [property definitions](https://learn.microsoft.com/en-us/windows/win32/fwp/wmi/netadaptercimprov/msft-netadapterpowermanagementsettingdata) identify 2 as Enabled and 0 as Unsupported. These conflicting interfaces do not demonstrate working network wake. The missing AllowWakeFromS3 property is not evidence either way.

## Packet delivery and sleep tests

An isolated Java/dex diagnostic sender ran on the Android phone, independently of the sleeping laptop and without modifying the normal app. It sent standard 102-byte magic packets to subnet broadcast and the laptop's last-known IPv4, UDP port 9, on the same /24 LAN.

The initial awake receive probe timed out. A later user-run elevated probe verified exact packet receipt through both broadcast and unicast. Its temporary firewall rule was removed afterward. This establishes awake delivery; it does not prove delivery or maintained wireless association during S3 sleep.

Times below are Asia/Taipei, November 18, 2026:

| Test | Evidence and result |
| --- | --- |
| Initial approved sleep test | Sleep at 17:43:40; phone sent ten broadcast/unicast pairs at 17:44:07–17:44:34. Eventual wake at 17:50:28 was attributed to a USB Composite Device by Windows, not Wi-Fi. |
| First traced sleep test | Sleep requested at 20:46:25; suspend call returned after about a minute. Windows reported USB wake and the user reported possible shared keyboard/mouse input. Not a successful Wi-Fi test. |
| Subsequent hands-off test | Sleep requested at 20:52:31; phone independently sent twenty packets at 20:53:01–20:53:28. User reported no automatic wake. Suspend call returned at 21:19:20; that interval is not an exact sleep-duration measurement. Saved events lack a useful matching final wake source, so none is inferred. |
| Wolow cross-check | User tested the laptop using its verified Wi-Fi MAC/address, broadcast destination and UDP port 9, and reported failure. No successful laptop Wi-Fi wake was demonstrated. |

Diagnostic scripts, packet results and traces are under ignored artifacts/wake-test; the phone sender log is /data/local/tmp/tapmypc-wake-run.log. Artifacts contain local machine/network information and are not release assets.

## Limits and retained changes

- Laptop Ethernet wake remains untested. Cabling to the router in another room is not practical for the user; Ethernet is not a prerequisite for moving to monitoring.
- Laptop hibernate, shutdown, battery and Bluetooth wake remain untested. Awake connectivity does not demonstrate wake support.
- The Android sender runs on the phone independently of the PC's power state.
- No app source, installed package, credentials, driver, firmware, BIOS setting, permanent firewall setting, network category or clock was changed by this investigation. The temporary receive-probe firewall rule was removed.
- The user-enabled Wi-Fi wake authorization remains armed. To restore its original state, run Administrator PowerShell:

```powershell
powercfg /devicedisablewake "MediaTek Wi-Fi 6 MT7921 Wireless LAN Card"
```

Reopen laptop Wi-Fi investigation only with new model-specific support information or a supported configuration/fix, rather than repeating the same packet tests.
