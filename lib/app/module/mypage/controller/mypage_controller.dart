import 'dart:io';

import 'package:cashmore_app/app/module/home/controller/home_controller.dart';
import 'package:cashmore_app/common/base_controller.dart';
import 'package:cashmore_app/common/model/board_model.dart';
import 'package:cashmore_app/repository/mypage_repsitory.dart';
import 'package:cashmore_app/service/app_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MyPageController extends BaseController {
  var userName = ''.obs;
  var userEmail = ''.obs;
  var version = ''.obs;

  var isStepCountEnabled = true.obs; // ✅ SharedPreferences에서 불러올 값
  static const platform = MethodChannel('com.getit.getitmoney/steps');

  final appService = Get.find<AppService>();
  MypageRepsitory mypageRepsitory = MypageRepsitory();
  int pageSize = 4;

  var notices = <BoardModel>[].obs;
  var isLoading = true.obs;

  @override
  Future<void> onInit() async {
    super.onInit();

    await _loadStepCountSetting(); // ✅ 앱 시작 시 걸음수 수집 설정 불러오기
    fetchUserInfo();
    fetchBoardData();
  }

  /// 📌 걸음수 수집 설정 불러오기
  Future<void> _loadStepCountSetting() async {
    final prefs = await SharedPreferences.getInstance();
    isStepCountEnabled.value = prefs.getBool('isStepCountEnabled') ?? true; // ✅ 저장된 설정 반영
    print("✅ 걸음수 설정 불러오기 완료: ${isStepCountEnabled.value}");
  }

  /// 📌 걸음수 수집 기능 On/Off
  void toggleStepCountCollection(bool value) async {
    var text = value ? "걸음수 수집을 활성화 하면 걸음 데이터를 수집합니다." : "걸음수 수집을 종료하면 걸음 데이터를 수집하지 않습니다.\n기존 수집된 걸음 수는 초기화됩니다.";

    Get.dialog(
      _buildCustomDialog(
        title: "걸음수 수집",
        message: text,
        onConfirm: () async {
          isStepCountEnabled.value = value;
          SharedPreferences prefs = await SharedPreferences.getInstance();
          await prefs.setBool('isStepCountEnabled', value); // ✅ 설정 저장

          try {
            await platform.invokeMethod('toggleStepTracking', {"enable": value});
            print(value ? "✅ 걸음수 수집 활성화" : "🚫 걸음수 수집 비활성화");

            if (value) {
              _startForegroundService(); // ✅ 활성화 시 포그라운드 서비스 실행
            } else {
              _stopForegroundService(); // ✅ 비활성화 시 포그라운드 서비스 중단
              _stopBackgroundStepCounter(); // ✅ 백그라운드 서비스 중단
            }
          } catch (e) {
            print("🚨 걸음수 수집 상태 변경 실패: $e");
          }

          // 💡 HomeController의 걸음 수 수집 상태에 즉시 반영
          final homeController = Get.find<HomeController>();
          homeController.isStepCountEnabled.value = value;
          homeController.toggleStepCount(value);

          Get.back();
        },
      ),
    );
  }

/// 📌 포그라운드 서비스 중지
  Future<void> _stopForegroundService() async {
    try {
      await platform.invokeMethod('stopForegroundService');
      print("✅ Foreground Service 중지");
    } catch (e) {
      print("🚨 Foreground Service 중지 실패: $e");
    }
  }


/// 📌 백그라운드 걸음수 수집 중지
  void _stopBackgroundStepCounter() {
    print("🚨 백그라운드 걸음수 수집 중지");
    final homeController = Get.find<HomeController>();
    homeController.stopListeningToSteps(); // ✅ 걸음수 업데이트 중지
  }


  /// 사용자 정보를 가져오는 함수
  Future<void> fetchUserInfo() async {
    var user = await AppService().getUser();
    userName.value = user.user_name!;
    userEmail.value = user.user_id;
    version.value = (await AppService.to.getloadAppVersion())!;
  }

  /// 공지사항 데이터를 가져오는 함수
  Future<void> fetchBoardData() async {
    try {
      isLoading.value = true;
      List<BoardModel> list = await mypageRepsitory.boardList(
        AppService.to.userId!,
        "1",
        0,
        pageSize,
      );
      notices.addAll(list);
    } finally {
      isLoading.value = false;
    }
  }

  /// 페이지 이동
  void movePage(String path) {
    Get.toNamed(path);
  }

  /// 공지사항 상세 보기로 이동
  void moveToNoticeDetail(int id) {
    Get.toNamed('/notice_detail', arguments: id);
  }

  /// 포그라운드 서비스 시작 (Android)
  Future<void> _startForegroundService() async {
    try {
      await platform.invokeMethod('startForegroundService');
      print("✅ Foreground Service 시작");
    } catch (e) {
      print("🚨 Foreground Service 시작 실패: $e");
    }
  }


  /// 문의 데이터 제출
  Future<void> submitInquiry(Map<String, String> inquiry) async {
    try {
      var user = await AppService().getUser();

      Map<String, dynamic> requestBody = {
        "user_id": user.user_id,
        "user_hp": user.user_hp,
        "user_gubun": inquiry["category"],
        "user_subject": inquiry["title"],
        "user_contents": inquiry["content"],
      };

      isLoading.value = true;
      await mypageRepsitory.submitInquiry(requestBody).then((response) async {
        Get.snackbar("문의 완료", "문의가 성공적으로 접수되었습니다.");
      });
    } catch (e) {
      Get.snackbar("오류", "문의 제출 중 문제가 발생했습니다: $e");
    } finally {
      isLoading.value = false;
    }
  }

  /// 커스텀 다이얼로그
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
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
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
                  label: "취소",
                  backgroundColor: Colors.grey[300]!,
                  textColor: Colors.black87,
                  onPressed: () => Get.back(),
                ),
                const SizedBox(width: 10),
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

  /// 다이얼로그 버튼 위젯
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
