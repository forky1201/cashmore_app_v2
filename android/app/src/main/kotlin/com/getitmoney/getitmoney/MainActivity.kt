package com.getit.getitmoney

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.SharedPreferences
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.Bundle
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity(), SensorEventListener {
    private val CHANNEL = "com.getit.getitmoney/steps"
    private var sensorManager: SensorManager? = null
    private var steps = 0
    private var baseStepCount = -1
    private lateinit var sharedPreferences: SharedPreferences
    private var isStepCountEnabled = false
    private lateinit var methodChannel: MethodChannel

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        sensorManager = getSystemService(Context.SENSOR_SERVICE) as SensorManager
        val stepSensor = sensorManager?.getDefaultSensor(Sensor.TYPE_STEP_COUNTER)

        sharedPreferences = getSharedPreferences("step_prefs", Context.MODE_PRIVATE)
        baseStepCount = sharedPreferences.getInt("baseStepCount", -1)
        isStepCountEnabled = sharedPreferences.getBoolean("isStepCountEnabled", false)

        methodChannel = MethodChannel(flutterEngine!!.dartExecutor.binaryMessenger, CHANNEL)

        methodChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "getSteps" -> result.success(getStepCount())
                "getBaseStepCount" -> result.success(getBaseStepCount())
                "resetSteps" -> resetStepCount()
                "startForegroundService" -> startStepForegroundService()
                "stopForegroundService" -> stopStepForegroundService()
                "toggleStepTracking" -> toggleStepTracking(call.argument<Boolean>("enable") ?: true, result)
                "disableStepSensor" -> {
                    disableStepSensor()
                    result.success(null)
                }
                "forceReloadSteps" -> { // ✅ 강제 로드 요청 추가
                    val reloadedBase = sharedPreferences.getInt("baseStepCount", -1)
                    val reloadedSteps = sharedPreferences.getInt("stepCount", -1)
                    Log.d("MainActivity", "📌 강제 로드 수행: baseStepCount = $reloadedBase, stepCount = $reloadedSteps")
                    result.success(reloadedSteps)
                }
                else -> result.notImplemented()
            }
        }

        // ✅ 자정 초기화 브로드캐스트 리시버 등록
        val filter = IntentFilter("com.getit.getitmoney.UPDATE_STEPS")
        registerReceiver(stepUpdateReceiver, filter)

        if (isStepCountEnabled) {
            registerStepSensor()
        }

        Log.d("MainActivity", "✅ 앱 시작: baseStepCount = $baseStepCount, isTrackingEnabled = $isStepCountEnabled")
    }

    override fun onDestroy() {
        super.onDestroy()
        unregisterReceiver(stepUpdateReceiver) // ✅ 리시버 해제
    }

    /// ✅ 브로드캐스트 리시버 (자정 걸음 수 초기화 감지)
    private val stepUpdateReceiver: BroadcastReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action == "com.getit.getitmoney.UPDATE_STEPS") {
                resetStepCount()
                Log.d("MainActivity", "✅ 자정 초기화 감지됨! Flutter에 알림 전송")
                methodChannel.invokeMethod("updateSteps", null)
            }
        }
    }

    override fun onSensorChanged(event: SensorEvent?) {
        isStepCountEnabled = sharedPreferences.getBoolean("isStepCountEnabled", false)
        if (!isStepCountEnabled) return

        if (event?.sensor?.type == Sensor.TYPE_STEP_COUNTER) {
            steps = event.values[0].toInt()

            // 앱이 처음 실행되었거나 `baseStepCount`가 설정되지 않았을 경우
            if (baseStepCount == -1) {
                baseStepCount = steps
                sharedPreferences.edit().putInt("baseStepCount", baseStepCount).apply()
                Log.d("MainActivity", "✅ 최초 실행: baseStepCount = $baseStepCount")
            }


            val countedSteps = steps - baseStepCount
            if (countedSteps < 0) {
                baseStepCount = steps
                sharedPreferences.edit().putInt("baseStepCount", baseStepCount).apply()
            }
            if (countedSteps == steps){
                sharedPreferences.edit().putInt("stepCount", 0).apply()
                Log.d("MainActivity", "📌 걸음 수 업데이트1")
            } else {
                sharedPreferences.edit().putInt("stepCount", countedSteps).apply()
                Log.d("MainActivity", "📌 걸음 수 업데이트2")
            }
            
            Log.d("MainActivity", "📌 걸음 수 업데이트: steps = $steps, baseStepCount = $baseStepCount, countedSteps = $countedSteps")

            // UI 업데이트
            if (::methodChannel.isInitialized) {
                methodChannel.invokeMethod("updateSteps", countedSteps)
            } else {
                Log.e("MainActivity", "🚨 MethodChannel is not initialized!")
            }
        }
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}

    /// 📌 현재 걸음 수 가져오기
    private fun getStepCount(): Int {
        return sharedPreferences.getInt("stepCount", 0)
    }

    
    /// 📌 현재 걸음 수 가져오기2
    private fun getBaseStepCount(): Int {
        return sharedPreferences.getInt("baseStepCount", 0)
    }

    /// 📌 앱 실행 시 걸음 수 0부터 시작하도록 강제 초기화
    private fun resetStepCount() {
        baseStepCount = steps
        sharedPreferences.edit().putInt("baseStepCount", baseStepCount).apply()
        sharedPreferences.edit().putInt("stepCount", 0).apply()
        Log.d("MainActivity", "🔄 걸음 수 초기화됨: baseStepCount = $baseStepCount")
    }

    /// 📌 센서 등록
    private fun registerStepSensor() {
        val stepSensor = sensorManager?.getDefaultSensor(Sensor.TYPE_STEP_COUNTER)
        if (stepSensor != null) {
            sensorManager?.registerListener(this, stepSensor, SensorManager.SENSOR_DELAY_UI)
            Log.d("MainActivity", "✅ 센서 리스너 등록됨")
        }
    }

    /// 📌 센서 해제
    private fun unregisterStepSensor() {
        sensorManager?.unregisterListener(this)
        Log.d("MainActivity", "🚫 센서 리스너 해제됨")
    }

    /// 📌 포그라운드 서비스 시작
    private fun startStepForegroundService() {
        val serviceIntent = Intent(this, StepService::class.java)
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
            startForegroundService(serviceIntent)
        } else {
            startService(serviceIntent)
        }
        Log.d("MainActivity", "✅ Foreground Service 시작")
    }

    /// 📌 포그라운드 서비스 중지
    private fun stopStepForegroundService() {
        val serviceIntent = Intent(this, StepService::class.java)
        stopService(serviceIntent)
        Log.d("MainActivity", "✅ Foreground Service 중지")
    }

    /// 📌 걸음 수 수집 활성화/비활성화
    private fun toggleStepTracking(enable: Boolean, result: MethodChannel.Result) {
        isStepCountEnabled = enable
        sharedPreferences.edit().putBoolean("isStepCountEnabled", enable).apply()

        if (enable) {
            // ✅ 현재 센서의 걸음 수를 기준으로 `baseStepCount`를 새롭게 설정
            baseStepCount = steps
            sharedPreferences.edit().putInt("baseStepCount", baseStepCount).apply()

            // ✅ 걸음 수를 0으로 초기화
            sharedPreferences.edit().putInt("stepCount", 0).apply()

            registerStepSensor()
            Log.d("MainActivity", "✅ 걸음 수 수집 활성화됨: baseStepCount = $baseStepCount, stepCount = 0")
        } else {
            unregisterStepSensor()
            stopStepForegroundService()

            // ✅ 걸음 수를 0으로 초기화
            sharedPreferences.edit().putInt("stepCount", 0).apply()
            Log.d("MainActivity", "🚫 걸음 수 수집 비활성화됨")
        }
        result.success(null)
    }

    // ✅ 걸음수 센서 비활성화 메서드 추가
    private fun disableStepSensor() {
        sensorManager?.unregisterListener(this) // ✅ 센서 리스너 제거
        Log.d("MainActivity", "🚫 걸음수 센서 비활성화됨")
    }
}
