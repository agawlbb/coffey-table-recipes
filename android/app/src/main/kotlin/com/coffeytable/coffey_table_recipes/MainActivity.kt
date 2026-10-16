package com.coffeytable.coffey_table_recipes

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        RecipeTimers.register(this, MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "coffey_table_recipes/timers"))
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "coffey_table_recipes/share_link")
            .setMethodCallHandler { call, result ->
                if (call.method != "share") {
                    result.notImplemented()
                } else {
                    val html = call.argument<String>("html")
                    val text = call.argument<String>("text")
                    val title = call.argument<String>("title")
                    if (html == null || text == null || title == null) {
                        result.error("invalid_link", "Missing recipe link.", null)
                    } else {
                        try {
                            val intent = Intent(Intent.ACTION_SEND).apply {
                                type = "text/plain"
                                putExtra(Intent.EXTRA_TEXT, text)
                                putExtra(Intent.EXTRA_HTML_TEXT, html)
                                putExtra(Intent.EXTRA_SUBJECT, title)
                                putExtra(Intent.EXTRA_TITLE, title)
                            }
                            startActivity(Intent.createChooser(intent, title))
                            result.success(true)
                        } catch (error: Exception) {
                            result.error("share_unavailable", "Could not open sharing.", null)
                        }
                    }
                }
            }
    }
}
