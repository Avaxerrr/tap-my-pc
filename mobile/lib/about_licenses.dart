import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

void registerBundledLicenses() {
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'Inter',
    ], await rootBundle.loadString('assets/fonts/Inter-OFL.txt'));

    const viewerAssets = 'android/app/src/main/assets/remote-desktop';
    for (final (package, filename) in [
      ('noVNC', 'LICENSE.MPL-2.0'),
      ('noVNC', 'LICENSE.BSD-2-Clause'),
      ('noVNC', 'LICENSE.BSD-3-Clause'),
      ('noVNC', 'AUTHORS'),
      ('noVNC fonts', 'LICENSE.OFL-1.1'),
      ('pako', 'LICENSE.pako'),
    ]) {
      yield LicenseEntryWithLineBreaks([
        package,
      ], await rootBundle.loadString('$viewerAssets/$filename'));
    }
  });
}
