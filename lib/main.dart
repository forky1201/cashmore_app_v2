// lib/main.dart
import 'dart:io';

import 'package:cashmore_app/app/module/common/controller/auth_controller.dart';
import 'package:cashmore_app/app/module/home/controller/home_controller.dart';
import 'package:cashmore_app/app/module/intro/controller/session_controller.dart';
import 'package:cashmore_app/pages.dart';
import 'package:cashmore_app/service/app_prefs.dart';
import 'package:cashmore_app/service/app_service.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:get/get_navigation/src/root/get_material_app.dart';
import 'package:flutter_keyboard_visibility/flutter_keyboard_visibility.dart';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:workmanager/workmanager.dart';

const String dailyTaskKey = "dailyTask";
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) {
    var now = DateTime.now();
    print("🛠 Workmanager 실행됨: $task $now");
    if (task == dailyTaskKey) {
      HomeController homeController = Get.find<HomeController>();
      //homeController.checkAndResetSteps();
    }
    return Future.value(true);
  });
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 세로로만 UI 표시 설정
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  if (Platform.isAndroid) {
    //Workmanager().initialize(callbackDispatcher, isInDebugMode: false);
  }

  await initializeApp();
  await requestPermissions();

  if (Platform.isAndroid) {
    //scheduleDailyTask();
  }

  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return KeyboardDismissOnTap(
        child: GetMaterialApp(
      builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaleFactor: 1.0), child: child!),
      debugShowCheckedModeBanner: false,
      //supportedLocales: context.supportedLocales,
      title: '겟잇머니',
      theme: ThemeData(
        //primarySwatch: Colors.purple,
        fontFamily: "Pretendard",
      ),
      getPages: Pages.routes,
      initialRoute: Pages.initial,
      //home: SplashScreenView(),
      //home: MainPage(),
    ));
  }
}

Future<void> initializeApp() async {
  /// SharedPreferences instance 생성
  await AppPrefs.init();

  Get.lazyPut(() => AppService());
  Get.put(SessionController());
  Get.put(AuthController());

  // runApp() 호출 전 Flutter SDK 초기화
  KakaoSdk.init(
    nativeAppKey: 'ab18a221cb1c3054430fbec3e97cf5f4',
    javaScriptAppKey: 'de0da86fee794e9525e6c7287f762f8a',
  );

  //await requestGalleryPermission(); // 권한 요청
}

Future<void> requestPermissions() async {
  if (Platform.isIOS) {
    // iOS에서 Permission.photos 대신 Permission.photosAddOnly 사용
    Map<Permission, PermissionStatus> statuses = await [
      Permission.photosAddOnly, // iOS에서 사진 권한
      Permission.activityRecognition, // 활동 인식 권한
    ].request();

    if (statuses[Permission.photosAddOnly]?.isGranted == true) {
      print("📸 iOS - 사진 권한이 허용되었습니다.");
    } else {
      print("📸 iOS - 사진 권한이 거부되었습니다.");
    }
  } else {
    // 안드로이드에서 기존 코드 유지
    Map<Permission, PermissionStatus> statuses = await [
      Permission.photos,
      Permission.activityRecognition,
    ].request();

    if (statuses[Permission.photos]?.isGranted == true) {
      print("📸 사진 권한이 허용되었습니다.");
    } else {
      print("📸 사진 권한이 거부되었습니다.");
    }
  }

  // 활동 인식 권한 요청 (iOS & Android 공통)
  if (await Permission.activityRecognition.status.isGranted) {
    print("🏃 활동 인식 권한이 허용되었습니다.");
  } else {
    print("🏃 활동 인식 권한이 거부되었습니다.");
  }
}

void scheduleDailyTask() {
  final now = DateTime.now();
  final nextMidnight = DateTime(now.year, now.month, now.day + 1, 0, 0, 0);
  final initialDelay = nextMidnight.difference(now);

  Workmanager().registerPeriodicTask(
    dailyTaskKey,
    dailyTaskKey,
    frequency: Duration(days: 1), // 하루마다 실행
    //frequency: Duration(minutes:15), // 하루마다 실행
    initialDelay: initialDelay, // 자정에 실행되도록 딜레이 설정
    existingWorkPolicy: ExistingWorkPolicy.replace,
    constraints: Constraints(
      networkType: NetworkType.not_required,
      requiresBatteryNotLow: true,
      requiresCharging: false,
      requiresDeviceIdle: false,
      requiresStorageNotLow: true,
    ),
  );
}


