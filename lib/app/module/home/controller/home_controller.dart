// lib/controllers/home_controller.dart
import 'dart:async';
import 'dart:io';

import 'package:cashmore_app/AppLifecycleObserver.dart';
import 'package:cashmore_app/app/module/main/controller/main_controller.dart';
import 'package:cashmore_app/common/base_controller.dart';
import 'package:cashmore_app/common/model/common_model.dart';
import 'package:cashmore_app/common/model/recommender_model.dart';
import 'package:cashmore_app/common/model/totalPoint_model.dart';
import 'package:cashmore_app/common/model/user_model.dart';
import 'package:cashmore_app/repository/PreferencesDatabase.dart';
import 'package:cashmore_app/repository/StepDatabase.dart';
import 'package:cashmore_app/repository/auth_repsitory.dart';
import 'package:cashmore_app/repository/home_repsitory.dart';
import 'package:cashmore_app/repository/mypage_repsitory.dart';
import 'package:cashmore_app/service/app_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:get/get.dart';
import 'package:health/health.dart';
import 'package:intl/intl.dart';
import 'package:pedometer/pedometer.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart'; // pedometer 패키지 사용

/// ── HomeController ───────────────────────────────────────────────────────────────
class HomeController extends BaseController {
  // 포인트, 초대 친구 등 기존 변수
  var points = 0.obs;
  var availablePoints = 0.obs;
  var invitedFriendsCount = 1.obs;
  var accumulatedPoints = 0.obs;
  var boardMessage = '문의는 제휴/광고 게시판으로 연락주세요'.obs;
  var isDontShowChecked = false.obs;

  // 걸음 수 관련 변수 (health 패키지 사용)
  var stepCount = 0.obs;
  var baseStepCount = 0.obs; // 자정 기준 걸음 수 저장

  // Pedometer 상태 메시지 (UI 표시 용)
  var pedometerStatus = '걸음수 대기 중'.obs;

  // 사용자 관련 변수
  var user = Rxn<UserModel>();
  var name = "".obs;

  // 미션/보상 관련 변수
  var step500 = "N".obs;
  var step1000 = "N".obs;
  var step2000 = "N".obs;
  var step3000 = "N".obs;
  var step5000 = "N".obs;
  var step10000 = "N".obs;

  var point500 = 0.obs;
  var point1000 = 0.obs;
  var point2000 = 0.obs;
  var point3000 = 0.obs;
  var point5000 = 0.obs;
  var point10000 = 0.obs;

  // 메시지 관련 타이머
  late Timer _messageTimer = Timer(Duration.zero, () {});
  late Timer pointTimer = Timer(Duration.zero, () {});
  int _messageIndex = 0;
  final List<String> _messages = [
    '문의는 제휴/광고 게시판으로 연락주세요',
    '최신 이벤트: 지금 참여하세요!',
  ];

  final List<int> _noticeIds = [1, 2];

  // 현재 메시지에 해당하는 noticeId 저장 변수
  var currentNoticeId = 1.obs;

  // 걸음 측정 활성화 여부
  var isStepCountEnabled = true.obs;

  static const platform = MethodChannel('com.getit.getitmoney/steps');

  Timer? _midnightResetTimer;
  Timer? _stepUpdateTimer; // Android 걸음수 업데이트
  Timer? _iosStepUpdateTimer; // iOS 걸음수 업데이트

  final AppLifecycleObserver _lifecycleObserver = AppLifecycleObserver();
  final Health health = Health();
  final FlutterBackgroundService _backgroundService = FlutterBackgroundService();

  @override
  Future<void> onInit() async {
    super.onInit();

    await requestPermissions();

    // ✅ 자정 초기화 감지 이벤트 등록
    platform.setMethodCallHandler((call) async {
      if (call.method == "updateSteps") {
        print("🔄 자정 초기화 감지됨! 1초 후 걸음 수 다시 불러오기...");

        await Future.delayed(Duration(seconds: 5)); // ✅ 1초 대기
        final int forcedSteps = await platform.invokeMethod("forceReloadSteps"); // ✅ 강제 로드 요청
        await loadSavedStepCount(); // ✅ 최신 데이터 다시 로드

        print("✅ 걸음 수 업데이트 반영 완료: ${stepCount.value} (강제 로드 후: $forcedSteps)");
      }
    });

    if (Platform.isAndroid) {
      loadSavedStepCount();
      //startListeningToSteps();

      // ✅ 저장된 설정 불러오기
      await _loadStepCountSetting();

      if (isStepCountEnabled.value) {
        startListeningToSteps();
        pedometerStatus.value = '걸음수 측정 중';
      } else {
        pedometerStatus.value = '걸음수 대기 중';
      }
    } else {
      requestHealthPermissions();
      await startIOSStepUpdatesOne();
      startIOSStepUpdates(); // 🔹 iOS 걸음수 업데이트 타이머 시작
    }

    userInfo();
    totalPoint();
    pointAdd();
    friend();
    _startMessageRotation();
    startTotalPointUpdate();

    //scheduleMidnightReset();
    startBackgroundStepCounter();

    pedometerStatus.value = '걸음수 측정 중';

    WidgetsBinding.instance.addObserver(_lifecycleObserver);
  }

  @override
  void onClose() {
    _messageTimer.cancel();
    pointTimer.cancel();
    _midnightResetTimer?.cancel();
    _stepUpdateTimer?.cancel();
    _iosStepUpdateTimer?.cancel();
    WidgetsBinding.instance.removeObserver(_lifecycleObserver);
    super.onClose();
  }

  /// ── 메시지 타이머 (10초마다 변경) ──────────────────────────────────────────
  void _startMessageRotation() {
    // 초기값 설정 (첫 번째 메시지)
    boardMessage.value = _messages[0];
    currentNoticeId.value = _noticeIds[0];

    _messageTimer = Timer.periodic(Duration(seconds: 10), (timer) {
      _messageIndex = (_messageIndex + 1) % _messages.length;
      boardMessage.value = _messages[_messageIndex];
      currentNoticeId.value = _noticeIds[_messageIndex];
    });
  }

  /// ── totalPoint 업데이트 (20초마다) ───────────────────────────────────────
  void startTotalPointUpdate() {
    pointTimer = Timer.periodic(Duration(seconds: 20), (timer) async {
      await totalPoint();
    });
  }

  /// ✅ 걸음수 수집 상태 저장
  Future<void> _saveStepCountSetting(bool isEnabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isStepCountEnabled', isEnabled);
  }

  /// ✅ 걸음수 수집 상태 불러오기 (앱 시작 시)
  Future<void> _loadStepCountSetting() async {
    final prefs = await SharedPreferences.getInstance();
    isStepCountEnabled.value = prefs.getBool('isStepCountEnabled') ?? true;
  }

// ✅ 걸음수 측정 활성화/비활성화 (센서 등록/해제 포함)
  void toggleStepCount(bool isEnabled) async {
    isStepCountEnabled.value = isEnabled;
    await _saveStepCountSetting(isEnabled); // ✅ 설정 저장

    if (isEnabled) {
      pedometerStatus.value = '걸음수 측정 중';

      try {
        // ✅ 현재 센서 걸음 수를 가져와 새로운 기준점 설정
        final int currentSensorSteps = await platform.invokeMethod('getSteps');

        // ✅ 기존 걸음 수를 유지하지 않고 새로운 기준으로 설정
        final prefs = await SharedPreferences.getInstance();
        final int prevBaseStepCount = prefs.getInt("baseStepCount") ?? 0;
        baseStepCount.value = currentSensorSteps - (stepCount.value); // 💡 여기 수정

        // ✅ 저장소 업데이트
        prefs.setInt("baseStepCount", baseStepCount.value);
        prefs.setInt("stepCount", 0);
        stepCount.value = 0; // UI 초기화

        print("✅ 걸음수 수집 활성화됨: baseStepCount = ${baseStepCount.value}");
      } catch (e) {
        print("🚨 센서 걸음 수 가져오기 실패: $e");
      }

      startListeningToSteps(); // ✅ 걸음수 측정 시작
    } else {
      pedometerStatus.value = '걸음수 대기 중';

      stopListeningToSteps(); // ✅ 걸음수 측정 중지
      platform.invokeMethod('stopForegroundService'); // ✅ 백그라운드 서비스 중지

      // ✅ 기존 데이터 초기화
      stepCount.value = 0;
      baseStepCount.value = 0;
      final prefs = await SharedPreferences.getInstance();
      prefs.setInt("baseStepCount", 0);
      prefs.setInt("stepCount", 0);

      try {
        platform.invokeMethod('disableStepSensor'); // 📌 Android 네이티브에서 처리
      } catch (e) {
        print("🚨 센서 비활성화 실패: $e");
      }
    }

    print("✅ 걸음수 수집 상태 변경: ${isStepCountEnabled.value}, 상태: ${pedometerStatus.value}");
  }

// ✅ 걸음수 측정 중지 (센서 및 타이머 해제)
  void stopListeningToSteps() {
    print("🚨 걸음수 측정 중지");
    _stepUpdateTimer?.cancel(); // ✅ 타이머 해제
    platform.invokeMethod('stopForegroundService'); // ✅ 백그라운드 서비스 중지

    try {
      platform.invokeMethod('disableStepSensor'); // 📌 Android 네이티브에서 센서 해제
      print("✅ 센서 비활성화 완료");
    } catch (e) {
      print("🚨 센서 비활성화 실패: $e");
    }
  }

  /// 🚀 권한 요청
  Future<void> requestPermissions() async {
    if (Platform.isAndroid) {
      await Permission.activityRecognition.request();
      //await Permission.location.request();
    } else if (Platform.isIOS) {
      await Permission.sensors.request();
    }
  }

  /// 🚀 Health API 권한 요청 (iOS만 사용)
  Future<void> requestHealthPermissions() async {
    if (!Platform.isIOS) return;

    List<HealthDataType> types = [HealthDataType.STEPS];
    bool authorized = await health.requestAuthorization(types);

    if (!authorized) {
      print("🚨 Apple Health 권한 요청 실패");
    } else {
      print("✅ Apple Health 권한 요청 성공");
    }
  }

  /// 📌 iOS 실시간 걸음 수 가져오기 (아이폰 걸음 수만)
  void startIOSStepUpdates() {
    _iosStepUpdateTimer = Timer.periodic(Duration(seconds: 3), (timer) async {
      try {
        DateTime now = DateTime.now();
        DateTime start = DateTime(now.year, now.month, now.day); // 🔹 오늘 00:00

        // 🔹 걸음 수 데이터 가져오기
        List<HealthDataPoint> data = await health.getHealthDataFromTypes(
          startTime: start,
          endTime: now,
          types: [HealthDataType.STEPS],
        );

        // 🔹 "iPhone"에서 기록된 걸음 수만 필터링
        int totalSteps = data.fold(0, (sum, item) {
          if (item.value is NumericHealthValue && item.sourceName.contains("iPhone")) {
            return sum + (item.value as NumericHealthValue).numericValue.toInt();
          }
          return sum;
        });

        stepCount.value = totalSteps; // 🔹 저장 필요 없음

        print("✅ 실시간 걸음 수 업데이트 (iOS - iPhone만): ${stepCount.value}");
      } catch (e) {
        print("🚨 Apple Health 걸음 수 가져오기 실패: $e");
      }
    });
  }

  Future<void> startIOSStepUpdatesOne() async {
    DateTime now = DateTime.now();
    DateTime start = DateTime(now.year, now.month, now.day); // 🔹 오늘 00:00

    // 🔹 걸음 수 데이터 가져오기
    List<HealthDataPoint> data = await health.getHealthDataFromTypes(
      startTime: start,
      endTime: now,
      types: [HealthDataType.STEPS],
    );

    // 🔹 "iPhone"에서 기록된 걸음 수만 필터링
    int totalSteps = data.fold(0, (sum, item) {
      if (item.value is NumericHealthValue && item.sourceName.contains("iPhone")) {
        return sum + (item.value as NumericHealthValue).numericValue.toInt();
      }
      return sum;
    });

    stepCount.value = totalSteps; // 🔹 저장 필요 없음

    print("✅ 실시간 걸음 수 업데이트 (iOS - iPhone만): ${stepCount.value}");
  }

  /// ✅ 걸음 수 설정 불러오기 (앱 실행 시)
  Future<void> loadSavedStepCount() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final int sensorSteps = await platform.invokeMethod('getSteps');
      final int sensorbaseStepCount = await platform.invokeMethod('getBaseStepCount');
      stepCount.value = sensorSteps;
      baseStepCount.value = sensorbaseStepCount;

     // await prefs.setInt("stepCount", stepCount.value);
     // await prefs.setInt("baseStepCount", baseStepCount.value);
      print("🔄 `stepCount` 새롭게 설정됨: ${stepCount.value}");
    } catch (e) {
      print("🚨 센서 걸음 수 가져오기 실패: $e");
    }

    //print("📊 불러온 걸음 수: baseStepCount=${baseStepCount.value}, stepCount=${stepCount.value}");
    update(); // ✅ UI 강제 업데이트
  }

  /// 📌 Android - 실시간 걸음 수 가져오기 (최초 1 표시 문제 해결)
  void startListeningToSteps() {
    _stepUpdateTimer = Timer.periodic(Duration(seconds: 3), (timer) async {
      try {
        final int newSteps = await platform.invokeMethod('getSteps');
        final int sensorbaseStepCount = await platform.invokeMethod('getBaseStepCount');

        stepCount.value = newSteps;
        print("✅ 걸음 수 업데이트1: $newSteps");
      } catch (e) {
        print("🚨 걸음 수 가져오기 실패: $e");
      }
    });
  }

  // ✅ 걸음수 저장 (SharedPreferences)
  Future<void> saveSteps(int totalSteps) async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setInt("baseStepCount", baseStepCount.value);
    prefs.setInt("stepCount", totalSteps);
    print("✅ 걸음 수 저장 완료: baseStepCount=${baseStepCount.value}, stepCount=${stepCount.value}");
  }

  /// 📌 자정에 걸음 수 초기화 (Android만)
  void scheduleMidnightReset() {
    if (Platform.isIOS) {
      print("🔹 iOS에서는 자정 초기화 필요 없음");
      return; // iOS는 실행하지 않음
    }

    DateTime now = DateTime.now();
    DateTime midnight = DateTime(now.year, now.month, now.day).add(Duration(days: 1));
    Duration timeUntilMidnight = midnight.difference(now);

    _midnightResetTimer = Timer(timeUntilMidnight, () async {
      try {
        await platform.invokeMethod('resetSteps');
        print("✅ Android 걸음 수 기준점(baseSteps) 재설정 완료");
      } catch (e) {
        print("🚨 Android 걸음 수 초기화 실패: $e");
      }
      scheduleMidnightReset(); // 다음 자정에 다시 실행
    });
  }

  /// 📌 백그라운드 서비스 시작
  void startBackgroundStepCounter() {
    if (Platform.isAndroid) {
      try {
        platform.invokeMethod('startForegroundService');
        print("✅ Foreground Service 시작");
      } catch (e) {
        print("🚨 Foreground Service 시작 실패: $e");
      }
    } else {
      final service = FlutterBackgroundService();
      service.invoke("startStepCounter");
    }
  }

  /// 📌 백그라운드 걸음 수 측정 서비스
  @pragma('vm:entry-point')
  static void onBackgroundServiceStart(ServiceInstance service) {
    if (Platform.isAndroid) {
      if (service is AndroidServiceInstance) {
        service.setAsForegroundService();
        service.setForegroundNotificationInfo(
          title: "걸음 수 측정 중",
          content: "백그라운드에서 걸음 수를 기록하고 있습니다.",
        );
      }
    }

    service.on("stopService").listen((event) {
      service.stopSelf();
    });

    Timer.periodic(Duration(minutes: 1), (timer) async {
      Health health = Health();
      DateTime now = DateTime.now();
      DateTime start = DateTime(now.year, now.month, now.day);
      List<HealthDataPoint> data = await health.getHealthDataFromTypes(
        startTime: start,
        endTime: now,
        types: [HealthDataType.STEPS],
      );
      int totalSteps = data.fold(0, (sum, item) => sum + (item.value as int));

      print("📌 백그라운드 걸음 수 업데이트: $totalSteps");

      // 걸음 수 데이터 저장
      final prefs = await SharedPreferences.getInstance();
      prefs.setInt("stepCount", totalSteps);
    });
  }

  //////////////////////////////////////////////////////////////////////////////
  // 이하 기존 포인트, 사용자 정보, 미션 관련 로직 (변경 없이 유지)
  //////////////////////////////////////////////////////////////////////////////

  void pointAdd() async {
    AuthRepository authRepository = AuthRepository();
    Map<String, dynamic> requestBody = {"user_id": AppService.to.userId};
    final response = await authRepository.pointAdd(requestBody);
    if (response.code == 200) {
      userInfo();
      _showPointAddBottomSheet();
    }
  }

  Future<void> friend() async {
    UserModel user = await AppService().getUser();
    MypageRepsitory mypageRepsitory = MypageRepsitory();
    List<RecommenderModel> list = await mypageRepsitory.recommendersList(
      user.user_id,
      user.my_recommender.toString(),
      0,
      100,
    );
    invitedFriendsCount.value = list.length;
  }

  void _showPointAddBottomSheet() {
    Get.bottomSheet(
      Container(
        decoration: const BoxDecoration(
          color: Color.fromRGBO(255, 231, 203, 1),
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(16.0),
            topRight: Radius.circular(16.0),
          ),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              const Text(
                "오늘 출석체크를 완료했습니다.",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w400, color: Colors.black),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Image.asset('assets/images/popup1.png'),
                ],
              ),
              const SizedBox(height: 10),
              const Text(
                "적립완료 !!",
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.black),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () async {
                  final mainController = Get.find<MainController>();
                  mainController.updateIndex(3);
                  await mainController.navigateTo(3);
                  Get.back();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black,
                  minimumSize: const Size(150, 40),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text(
                  "포인트 확인 하기",
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 20),
              Container(
                color: Colors.white,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Obx(() => Checkbox(
                              value: isDontShowChecked.value,
                              onChanged: (value) {
                                isDontShowChecked.value = value ?? false;
                              },
                            )),
                        const Text(
                          "오늘 그만 보기",
                          style: TextStyle(fontSize: 14, color: Colors.black),
                        ),
                      ],
                    ),
                    TextButton(
                      onPressed: () => Get.back(),
                      child: const Text("닫기", style: TextStyle(color: Colors.grey)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      isDismissible: true,
      backgroundColor: Colors.transparent,
    );
  }

  void collectPoints() {
    // 포인트 적립 후 초기화 등 관련 로직 구현 (필요 시)
  }

  Future<void> inviteFriend() async {
    Get.toNamed("/recommen");
  }

  Future<void> inviteCoupon() async {
    final mainController = Get.find<MainController>();
    mainController.updateIndex(2);
    await mainController.navigateTo(2);
  }

  Future<void> userInfo() async {
    await AppService.to.loginInfoRefresh();
    UserModel fetchedUser = await AppService().getUser();
    points.value = fetchedUser.total_point!;
    availablePoints.value = points.value;

    step500.value = fetchedUser.step500 ?? "N";
    step1000.value = fetchedUser.step1000 ?? "N";
    step2000.value = fetchedUser.step2000 ?? "N";
    step3000.value = fetchedUser.step3000 ?? "N";
    step5000.value = fetchedUser.step5000 ?? "N";
    step10000.value = fetchedUser.step10000 ?? "N";

    point500.value = fetchedUser.point500!;
    point1000.value = fetchedUser.point1000!;
    point2000.value = fetchedUser.point2000!;
    point3000.value = fetchedUser.point3000!;
    point5000.value = fetchedUser.point5000!;
    point10000.value = fetchedUser.point10000!;

    user.value = fetchedUser;
    name.value = fetchedUser.user_name!;
  }

  Future<void> totalPoint() async {
    HomeRepsitory homeRepsitory = HomeRepsitory();
    TotalPointModel totalPoint = await homeRepsitory.totalPoint(AppService.to.userId!);
    accumulatedPoints.value = totalPoint.total_point!;
  }

  Future<void> movetoUrl() async {
    final mainController = Get.find<MainController>();
    await mainController.navigateTo(1);
  }

  Future<void> stepPointAdd(int step, int point) async {
    HomeRepsitory homeRepsitory = HomeRepsitory();
    Map<String, dynamic> requestBody = {
      "user_id": AppService.to.userId!,
      "steps": step,
    };

    await homeRepsitory.stepPointAdd(requestBody).then((response) async {
      Get.dialog(
        _buildCustomDialog(
          title: "미션완료",
          message: "$point 포인트 적립 되었습니다.",
          onConfirm: () {
            userInfo();
            Get.back();
          },
        ),
      );
    });
  }

  Widget _buildCustomDialog({
    required String title,
    required String message,
    required VoidCallback onConfirm,
  }) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16.0),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black),
            ),
            const SizedBox(height: 10),
            Text(
              message,
              style: const TextStyle(fontSize: 14, color: Colors.black54),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildDialogButton(
                  label: "확인",
                  backgroundColor: Colors.black,
                  textColor: Colors.white,
                  onPressed: onConfirm,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDialogButton({
    required String label,
    required Color backgroundColor,
    required Color textColor,
    required VoidCallback onPressed,
  }) {
    return Expanded(
      child: SizedBox(
        child: ElevatedButton(
          onPressed: onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: backgroundColor,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8.0),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: textColor,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
        ),
      ),
    );
  }
}
