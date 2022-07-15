# qr_scanner_plus

A better qrcode and barcode scanner.

Features:
- ✅ Camera view can click to set focus point.
- ✅ Camera view can use scale gesture.
- ✅ Multi qrcode/barcode supported.
- ✅ Easy to use.
- [  ] Automatically find potential QR codes and automatically zoom in and focus.

### Getting Started

#### iOS 

Support for iOS > 9.0
1. Please add as follows in **info.plist**

<key>NSCameraUsageDescription</key>
<string></string>
<key>NSPhotoLibraryUsageDescription</key>
<string></string>
<key>io.flutter.embedded_views_preview</key>
<true/>

2. and add to **Podfile**
```
post_install do |installer|
  installer.pods_project.targets.each do |target|
    flutter_additional_ios_build_settings(target)


    target.build_configurations.each do |config|
      config.build_settings['ENABLE_BITCODE'] = 'NO'
      
      # https://pub.dev/packages/permission_handler
      # permission_handler的权限设置（详细参考官网）。
      # 在dart代码中，如果是通过permission_handler去申请一些应用权限，需要在这里打开对应宏设置。
      # 否则通过permission_handler获取到的权限状态只是默认值，而不是正确的状态！
      config.build_settings['GCC_PREPROCESSOR_DEFINITIONS'] ||= [
         '$(inherited)',

         ## dart: PermissionGroup.camera
         'PERMISSION_CAMERA=1',

         ## dart: PermissionGroup.microphone
         'PERMISSION_MICROPHONE=1',

         ## dart: PermissionGroup.photos
         'PERMISSION_PHOTOS=1',

         ## dart: [PermissionGroup.location, PermissionGroup.locationAlways, PermissionGroup.locationWhenInUse]
         'PERMISSION_LOCATION=1',

       ]
    end
  end
```

#### Android
minSdkVersion 21

Add to **AndroidManifest.xml**

```xml
    <uses-permission android:name="android.permission.INTERNET"/>
    <uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE"/>
    <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE"/>
```


## Example 

```dart
import 'package:flutter/material.dart';
import 'package:qr_scanner_plus/qr_scanner_plus.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('BarcodeScannerPlus example'),
        ),
        body: Center(
            child: QrScannerPlusView(
          _onResult,
          debug: true,
        )),
      ),
    );
  }

  _onResult(List<Barcode> barcodes) {
    for (final barcode in barcodes) {
      print(barcode.type);
      print(barcode.rawValue);
    }
  }
}

```

## Screenshot
![](https://github.com/fast-flutter/qr_scanner_plus/raw/master/assets/screenshot/1.jpg){width="300px"}