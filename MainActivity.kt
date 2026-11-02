package com.bluelink.bluelink

import android.content.pm.ApplicationInfo
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "bluelink/apps")
            .setMethodCallHandler { call, result ->
                if (call.method == "getApps") {
                    val pm = packageManager
                    val me = applicationContext.packageName
                    val list = pm.getInstalledApplications(0)
                        .filter { (it.flags and ApplicationInfo.FLAG_SYSTEM) == 0 && it.packageName != me }
                        .map {
                            mapOf(
                                "name" to pm.getApplicationLabel(it).toString(),
                                "pkg" to it.packageName,
                                "path" to it.sourceDir
                            )
                        }
                        .sortedBy { (it["name"] as String).lowercase() }
                    result.success(list)
                } else {
                    result.notImplemented()
                }
            }
    }
}
