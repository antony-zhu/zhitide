package com.example.zhixi

import android.app.PendingIntent
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.atomic.AtomicInteger

class MainActivity : FlutterActivity() {
    private val mainHandler = Handler(Looper.getMainLooper())
    private val commandIds = AtomicInteger(1)
    private var termuxPermissionResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.example.zhixi/agent")
            .setMethodCallHandler(::handleAgentCall)
    }

    private fun handleAgentCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "capabilities" -> result.success(
                mapOf(
                    "accessibilityEnabled" to (AgentAccessibilityService.current != null),
                    "termuxInstalled" to isTermuxInstalled(),
                    "termuxPermissionGranted" to
                        (checkSelfPermission(TERMUX_PERMISSION) == PackageManager.PERMISSION_GRANTED),
                ),
            )
            "openAccessibilitySettings" -> {
                startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
                result.success(true)
            }
            "requestTermuxPermission" -> requestTermuxPermission(result)
            "observe" -> withAccessibility(result) { service -> service.observe(result) }
            "tap" -> withAccessibility(result) { service ->
                val x = coordinate(call.argument<Number>("x"), result) ?: return@withAccessibility
                val y = coordinate(call.argument<Number>("y"), result) ?: return@withAccessibility
                service.tap(x, y, result)
            }
            "swipe" -> withAccessibility(result) { service ->
                val x1 = coordinate(call.argument<Number>("x1"), result) ?: return@withAccessibility
                val y1 = coordinate(call.argument<Number>("y1"), result) ?: return@withAccessibility
                val x2 = coordinate(call.argument<Number>("x2"), result) ?: return@withAccessibility
                val y2 = coordinate(call.argument<Number>("y2"), result) ?: return@withAccessibility
                val duration = call.argument<Number>("durationMs")?.toLong() ?: 450L
                if (duration !in 100..3000) {
                    result.error("invalid_argument", "滑动时长应在 100 到 3000 毫秒之间", null)
                    return@withAccessibility
                }
                service.swipe(x1, y1, x2, y2, duration, result)
            }
            "typeText" -> withAccessibility(result) { service ->
                val value = call.argument<String>("text")
                if (value == null) {
                    result.error("invalid_argument", "缺少要输入的文字", null)
                    return@withAccessibility
                }
                service.typeText(value, result)
            }
            "globalAction" -> withAccessibility(result) { service ->
                service.globalAction(call.argument<String>("action"), result)
            }
            "runCommand" -> runCommand(call, result)
            "openTermux" -> {
                val launch = packageManager.getLaunchIntentForPackage(TERMUX_PACKAGE)
                if (launch == null) {
                    result.error("termux_unavailable", "请先安装并打开 Termux", null)
                } else {
                    startActivity(launch)
                    result.success(true)
                }
            }
            else -> result.notImplemented()
        }
    }

    private fun withAccessibility(
        result: MethodChannel.Result,
        block: (AgentAccessibilityService) -> Unit,
    ) {
        val service = AgentAccessibilityService.current
        if (service == null) {
            result.error("accessibility_unavailable", "请在系统设置中启用知汐的无障碍服务", null)
        } else {
            block(service)
        }
    }

    private fun coordinate(value: Number?, result: MethodChannel.Result): Float? {
        val coordinate = value?.toFloat()
        if (coordinate == null || !coordinate.isFinite() || coordinate !in 0f..1000f) {
            result.error("invalid_argument", "坐标应为 0 到 1000", null)
            return null
        }
        return coordinate
    }

    private fun isTermuxInstalled(): Boolean = try {
        packageManager.getPackageInfo(TERMUX_PACKAGE, 0)
        true
    } catch (_: PackageManager.NameNotFoundException) {
        false
    }

    private fun requestTermuxPermission(result: MethodChannel.Result) {
        if (checkSelfPermission(TERMUX_PERMISSION) == PackageManager.PERMISSION_GRANTED) {
            result.success(true)
            return
        }
        if (termuxPermissionResult != null) {
            result.error("permission_pending", "授权请求仍在等待处理", null)
            return
        }
        termuxPermissionResult = result
        requestPermissions(arrayOf(TERMUX_PERMISSION), TERMUX_PERMISSION_REQUEST)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == TERMUX_PERMISSION_REQUEST) {
            termuxPermissionResult?.success(
                grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED,
            )
            termuxPermissionResult = null
        }
    }

    private fun runCommand(call: MethodCall, result: MethodChannel.Result) {
        val command = call.argument<String>("command")?.trim()
        val stdin = call.argument<String>("stdin")
        if (command.isNullOrEmpty()) {
            result.error("invalid_argument", "命令不能为空", null)
            return
        }
        if (command.length > 80000 || (stdin?.length ?: 0) > 80000) {
            result.error("invalid_argument", "命令或输入内容过长", null)
            return
        }
        if (!isTermuxInstalled()) {
            result.error("termux_unavailable", "请先安装并打开 Termux", null)
            return
        }
        if (checkSelfPermission(TERMUX_PERMISSION) != PackageManager.PERMISSION_GRANTED) {
            result.error("termux_permission", "请在知汐的应用权限中允许“在 Termux 中运行命令”", null)
            return
        }

        val id = commandIds.getAndIncrement()
        val replyIntent = Intent(this, TermuxResultReceiver::class.java).putExtra("requestId", id)
        val pendingIntent = PendingIntent.getBroadcast(
            this,
            id,
            replyIntent,
            PendingIntent.FLAG_ONE_SHOT or PendingIntent.FLAG_MUTABLE,
        )
        val timeout = Runnable {
            if (TermuxResultReceiver.pending.remove(id) != null) {
                pendingIntent.cancel()
                result.error("termux_timeout", "Termux 在两分钟内未返回结果，请检查权限和 Termux 设置", null)
            }
        }
        TermuxResultReceiver.pending[id] = { output ->
            mainHandler.removeCallbacks(timeout)
            if (output == null) {
                result.error("termux_failed", "Termux 未返回命令结果", null)
            } else {
                val internalError = output.getInt("err", -1)
                if (internalError != -1) {
                    result.error(
                        "termux_failed",
                        output.getString("errmsg") ?: "Termux 无法执行命令；请检查 allow-external-apps 设置",
                        null,
                    )
                } else {
                    result.success(
                        mapOf(
                            "stdout" to (output.getString("stdout") ?: ""),
                            "stderr" to (output.getString("stderr") ?: ""),
                            "exitCode" to output.getInt("exitCode", -1),
                        ),
                    )
                }
            }
        }
        mainHandler.postDelayed(timeout, 120000)

        val script = "mkdir -p \"\$HOME/zhitide-workspace\" && cd \"\$HOME/zhitide-workspace\" && $command"
        val intent = Intent("com.termux.RUN_COMMAND").apply {
            setClassName(TERMUX_PACKAGE, "com.termux.app.RunCommandService")
            putExtra("com.termux.RUN_COMMAND_PATH", "/data/data/com.termux/files/usr/bin/bash")
            putExtra("com.termux.RUN_COMMAND_ARGUMENTS", arrayOf("-lc", script))
            putExtra("com.termux.RUN_COMMAND_WORKDIR", "/data/data/com.termux/files/home")
            putExtra("com.termux.RUN_COMMAND_BACKGROUND", true)
            putExtra("com.termux.RUN_COMMAND_PENDING_INTENT", pendingIntent)
            if (stdin != null) putExtra("com.termux.RUN_COMMAND_STDIN", stdin)
        }
        try {
            val started = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(intent)
            } else {
                startService(intent)
            }
            if (started == null) {
                throw IllegalStateException("Termux 命令服务不可用")
            }
        } catch (error: Exception) {
            TermuxResultReceiver.pending.remove(id)
            mainHandler.removeCallbacks(timeout)
            pendingIntent.cancel()
            result.error("termux_failed", error.message ?: "无法启动 Termux 命令服务", null)
        }
    }

    companion object {
        private const val TERMUX_PACKAGE = "com.termux"
        private const val TERMUX_PERMISSION = "com.termux.permission.RUN_COMMAND"
        private const val TERMUX_PERMISSION_REQUEST = 7104
    }
}
