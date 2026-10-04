package com.fixtrack.fixtrack

import android.Manifest
import android.app.Activity
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.os.Build
import android.telephony.SmsManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.atomic.AtomicInteger

/**
 * بوابة SMS: بتبعت رسائل العملاء من شريحة الموبايل ده.
 * Dart بيكلمها على القناة "fixtrack/sms".
 */
class MainActivity : FlutterActivity() {
    private var pendingPermission: MethodChannel.Result? = null
    private val requestIds = AtomicInteger(1000)

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "fixtrack/sms").setMethodCallHandler { call, result ->
            when (call.method) {
                "hasPermission" -> result.success(hasSmsPermission())
                "requestPermission" -> {
                    if (hasSmsPermission()) {
                        result.success(true)
                    } else {
                        pendingPermission = result
                        requestPermissions(arrayOf(Manifest.permission.SEND_SMS), PERMISSION_REQUEST)
                    }
                }
                "send" -> {
                    val phone = call.argument<String>("phone")
                    val body = call.argument<String>("body")
                    if (phone.isNullOrBlank() || body.isNullOrBlank()) {
                        result.error("bad_args", "phone and body are required", null)
                    } else {
                        sendSms(phone, body, result)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun hasSmsPermission() =
        checkSelfPermission(Manifest.permission.SEND_SMS) == PackageManager.PERMISSION_GRANTED

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == PERMISSION_REQUEST) {
            pendingPermission?.success(grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED)
            pendingPermission = null
        }
    }

    private fun sendSms(phone: String, body: String, result: MethodChannel.Result) {
        if (!hasSmsPermission()) {
            result.error("permission", "SMS permission not granted", null)
            return
        }
        try {
            val sms: SmsManager = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                getSystemService(SmsManager::class.java)
            } else {
                @Suppress("DEPRECATION")
                SmsManager.getDefault()
            }
            val parts = sms.divideMessage(body)
            val action = "com.fixtrack.SMS_SENT_${System.nanoTime()}"
            var remaining = parts.size
            var failure: String? = null
            var finished = false

            // الرسالة الطويلة بتتقسم لأجزاء، ومنستناش غير لما كل الأجزاء تتبعت
            val receiver = object : BroadcastReceiver() {
                override fun onReceive(context: Context, intent: Intent) {
                    if (resultCode != Activity.RESULT_OK) failure = "SMS error code $resultCode"
                    remaining--
                    if (remaining <= 0 && !finished) {
                        finished = true
                        try {
                            unregisterReceiver(this)
                        } catch (_: Exception) {
                        }
                        if (failure == null) result.success(true) else result.error("send_failed", failure, null)
                    }
                }
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                registerReceiver(receiver, IntentFilter(action), Context.RECEIVER_NOT_EXPORTED)
            } else {
                @Suppress("UnspecifiedRegisterReceiverFlag")
                registerReceiver(receiver, IntentFilter(action))
            }

            val sentIntents = ArrayList<PendingIntent>()
            for (i in parts.indices) {
                sentIntents.add(
                    PendingIntent.getBroadcast(
                        this,
                        requestIds.incrementAndGet(),
                        Intent(action).setPackage(packageName),
                        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_ONE_SHOT,
                    )
                )
            }
            sms.sendMultipartTextMessage(phone, null, parts, sentIntents, null)
        } catch (e: Exception) {
            result.error("send_failed", e.message ?: e.toString(), null)
        }
    }

    companion object {
        private const val PERMISSION_REQUEST = 4711
    }
}
