package com.getit.getitmoney

import android.app.*
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.net.Uri
import android.os.Build
import android.os.IBinder
import android.provider.Settings
import android.util.Log
import java.util.*
import java.util.concurrent.TimeUnit

class StepService : Service(), SensorEventListener {
    private var sensorManager: SensorManager? = null
    private var steps = 0
    private var baseStepCount = -1  // ✅ 최초 실행 시 -1로 설정
    private lateinit var sharedPreferences: SharedPreferences
    private var isTrackingEnabled = false // ✅ 걸음 수 수집 여부

    override fun onCreate() {
        super.onCreate()
        sharedPreferences = getSharedPreferences("step_prefs", Context.MODE_PRIVATE)
        baseStepCount = sharedPreferences.getInt("baseStepCount", -1) // ✅ 기존 값 유지
        isTrackingEnabled = sharedPreferences.getBoolean("isStepCountEnabled", true)

        startForegroundNotification()
        requestExactAlarmPermission() // ✅ Android 12 이상에서 권한 요청
        scheduleTestReset() // ✅ 20:51 초기화 예약

        if (!isTrackingEnabled) {
            Log.d("StepService", "🚨 걸음 수 수집 비활성화 -> 서비스 중지")
            stopSelf()
            return
        }

        sensorManager = getSystemService(Context.SENSOR_SERVICE) as SensorManager
        val stepSensor = sensorManager?.getDefaultSensor(Sensor.TYPE_STEP_COUNTER)
        if (stepSensor != null) {
            sensorManager?.registerListener(this, stepSensor, SensorManager.SENSOR_DELAY_UI)
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        isTrackingEnabled = sharedPreferences.getBoolean("isStepCountEnabled", true)

        if (!isTrackingEnabled) {
            Log.d("StepService", "🚨 걸음 수 수집 비활성화 -> 서비스 중지")
            stopSelf()
            return START_NOT_STICKY
        }

        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? {
        return null
    }

    override fun onDestroy() {
        super.onDestroy()
        stopForeground(true)
        stopSelf()
        sensorManager?.unregisterListener(this) // ✅ 센서 리스너 해제
        Log.d("StepService", "🚨 Foreground Service 중지됨")
    }

    override fun onSensorChanged(event: SensorEvent?) {
        if (!isTrackingEnabled || event?.sensor?.type != Sensor.TYPE_STEP_COUNTER) return

        steps = event.values[0].toInt()
        baseStepCount = sharedPreferences.getInt("baseStepCount", -1) // ✅ 기존 값 유지
        var countedSteps = if (baseStepCount >= 0) {
        steps - baseStepCount
        } else {
            baseStepCount = steps // ✅ 첫 번째 값으로 초기화
            sharedPreferences.edit().putInt("baseStepCount", baseStepCount).apply()
            0 // ✅ 초기화 후 countedSteps = 0
        }
        
        sharedPreferences.edit().putInt("stepCount", countedSteps).apply()
        Log.d("StepService", "📌 Stepservice 걸음 수 업데이트: steps = $steps, baseStepCount = $baseStepCount, countedSteps = $countedSteps")
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}

    /// 📌 `AlarmManager`로 20:51 예약
    private fun scheduleTestReset() {
        val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val intent = Intent(this, ResetStepsReceiver::class.java).apply {
            action = "RESET_STEPS_AT_TEST_TIME"
        }
        val pendingIntent = PendingIntent.getBroadcast(
            this, 0, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val testTime = getTestTimeInMillis()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && !alarmManager.canScheduleExactAlarms()) {
            Log.e("StepService", "🚨 정확한 알람 권한이 없음. 요청 필요.")
            return
        }

        alarmManager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, testTime, pendingIntent)
        Log.d("StepService", "✅ 20:51 초기화 예약 완료: $testTime")
    }

    /// 📌 테스트를 위한 20:51 시간 계산
    private fun getTestTimeInMillis(): Long {
        val now = Calendar.getInstance()
        now.set(Calendar.HOUR_OF_DAY, 0)
        now.set(Calendar.MINUTE, 0)
        now.set(Calendar.SECOND, 2)
        now.set(Calendar.MILLISECOND, 0)

        // 만약 현재 시간이 20:51을 넘었다면, 다음날 20:51로 설정
        if (System.currentTimeMillis() > now.timeInMillis) {
            now.add(Calendar.DAY_OF_MONTH, 1)
        }

        return now.timeInMillis
    }

    /// 📌 Android 12(API 31) 이상에서 정확한 알람 권한 요청
    private fun requestExactAlarmPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
            if (!alarmManager.canScheduleExactAlarms()) {
                val intent = Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM, Uri.parse("package:$packageName"))
                startActivity(intent)
            }
        }
    }

    private fun startForegroundNotification() {
        val channelId = "step_service_channel"
        val channelName = "Step Service"

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                channelId,
                channelName,
                NotificationManager.IMPORTANCE_LOW
            )
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(channel)
        }

        val notification: Notification = Notification.Builder(this, channelId)
            .setContentTitle("걸음 수 측정 중")
            .setContentText("백그라운드에서 걸음 수를 기록하고 있습니다.")
            .setSmallIcon(R.mipmap.ic_launcher)
            .build()

        startForeground(1, notification)
    }
}
