package com.getit.getitmoney

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

class ResetStepsReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context?, intent: Intent?) {
        if (intent?.action == "RESET_STEPS_AT_TEST_TIME") {
            val prefs = context?.getSharedPreferences("step_prefs", Context.MODE_PRIVATE)
            val baseSteps = prefs?.getInt("baseStepCount", 0) ?: 0

            // ✅ 걸음 수 초기화 후 강제 로드
            prefs?.edit()
                ?.putInt("baseStepCount", baseSteps)
                ?.putInt("stepCount", 0)
                ?.putBoolean("isMidnightResetDone", false)
                ?.commit() // ✅ commit() 사용하여 즉시 반영

            // ✅ 값이 제대로 적용되었는지 확인하기 위해 강제 로드
            val checkBase = prefs?.getInt("baseStepCount", -1)
            val checkStep = prefs?.getInt("stepCount", 0)
            Log.d("ResetStepsReceiver", "✅ 자정 걸음 수 초기화 완료: baseStepCount = $checkBase, stepCount = $checkStep")

            // ✅ 초기화 완료 후 MainActivity로 알림
            val updateIntent = Intent("com.getit.getitmoney.UPDATE_STEPS")
            context?.sendBroadcast(updateIntent)
        }
    }
}
