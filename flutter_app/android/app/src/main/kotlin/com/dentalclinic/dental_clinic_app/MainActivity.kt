package com.dentalclinic.dental_clinic_app

import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine

// FlutterFragmentActivity: local_auth's biometric prompt needs a fragment activity.
class MainActivity : FlutterFragmentActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        PosPrinterPlugin(applicationContext, flutterEngine.dartExecutor.binaryMessenger)
        AppUpdatePlugin(this, flutterEngine.dartExecutor.binaryMessenger)
    }
}
