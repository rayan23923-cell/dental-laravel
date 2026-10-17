package com.dentalclinic.dental_clinic_app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        PosPrinterPlugin(applicationContext, flutterEngine.dartExecutor.binaryMessenger)
        AppUpdatePlugin(this, flutterEngine.dartExecutor.binaryMessenger)
    }
}
