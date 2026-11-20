# Third-party notices

TapMyPC's original code is available under the [MIT License](LICENSE). Third-party components retain their own licenses and attribution notices. The Windows and Android apps display bundled notices under **About TapMyPC → Third-party licenses**.

## Windows

Windows downloads include the license texts in `THIRD-PARTY-LICENSES.txt`.

- [Inter font notice](src/TapMyPC.Desktop/Assets/Fonts/Inter-OFL.txt)
- [QRCoder license](https://github.com/codebude/QRCoder/blob/v1.8.1/LICENSE.txt)
- [NAudio license](src/TapMyPC.Windows/ThirdParty/NAudio-LICENSE.txt)
- [Concentus license](src/TapMyPC.Windows/ThirdParty/Concentus-LICENSE.txt)
- [Makaretu.Dns and Makaretu.Dns.Multicast license](src/TapMyPC.Windows/ThirdParty/Makaretu.Dns%20and%20Makaretu.Dns.Multicast-LICENSE.txt)
- [Common.Logging and Common.Logging.Core license](src/TapMyPC.Windows/ThirdParty/Common.Logging-LICENSE.txt)
- [IPNetwork2 license](src/TapMyPC.Windows/ThirdParty/IPNetwork2-LICENSE.txt)
- [SimpleBase license](src/TapMyPC.Windows/ThirdParty/SimpleBase-LICENSE.txt)
- [System.Management and System.Numerics.Tensors licenses and notices](src/TapMyPC.Windows/ThirdParty/Microsoft%20libraries-LICENSE.txt)
- [Microsoft Windows SDK redistribution terms for the WinRT libraries](https://learn.microsoft.com/en-us/legal/windows-sdk/redist#microsoftwindowssdknetref)

The optional Remote Desktop feature downloads and installs UltraVNC from the publisher at setup. UltraVNC runs as a separate Windows service under its upstream license. [Official installer](https://uvnc.com/downloads/ultravnc.html) · [UltraVNC source and GPLv3 license](https://github.com/ultravnc/UltraVNC/blob/main/LICENSE)

## Android

The APK includes Flutter package notices, the [Inter font notice](mobile/assets/fonts/Inter-OFL.txt), and the [noVNC viewer notices](mobile/android/app/src/main/assets/remote-desktop/THIRD-PARTY.txt). The viewer's directory includes the [MPL 2.0 license](mobile/android/app/src/main/assets/remote-desktop/LICENSE.MPL-2.0) plus the other bundled license files.

### noVNC source for APK recipients

When distributing an APK, provide its matching noVNC source archive and tell recipients where to get it. For GitHub Releases, attach the archive to the same release as the APK and link to it from the release notes. The archive includes the modified source in its preferred form, its license files, and the build instructions. [MPL 2.0 source requirements](https://www.mozilla.org/en-US/MPL/2.0/FAQ/#q10)

The exact Android 0.18.3 (build 47) viewer source can also be reconstructed from [`@novnc/novnc@1.7.0`](https://www.npmjs.com/package/@novnc/novnc/v/1.7.0) and the matching [TapMyPC patch](mobile/novnc-stream-settings.patch). Use the recipe in the [viewer notices](mobile/android/app/src/main/assets/remote-desktop/THIRD-PARTY.txt). The reproduced `novnc.js` has SHA-256 `09f48a9b98d7e3de48aba551a44581d726b44878d850b4bc097bb6d4babf794d`.
