#import "QrScannerPlusPlugin.h"
#if __has_include(<qr_scanner_plus/qr_scanner_plus-Swift.h>)
#import <qr_scanner_plus/qr_scanner_plus-Swift.h>
#else
// Support project import fallback if the generated compatibility header
// is not copied when this plugin is created as a library.
// https://forums.swift.org/t/swift-static-libraries-dont-copy-generated-objective-c-header/19816
#import "qr_scanner_plus-Swift.h"
#endif

@implementation QrScannerPlusPlugin
+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
  [SwiftQrScannerPlusPlugin registerWithRegistrar:registrar];
}
@end
