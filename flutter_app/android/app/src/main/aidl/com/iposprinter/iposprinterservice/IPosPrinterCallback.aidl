package com.iposprinter.iposprinterservice;

// Verbatim from
// https://github.com/paystory-de/cordova-plugin-iposprinter
// (src/aidl/iposprinterservice/IPosPrinterCallback.aidl,
// Apache-2.0-licensed) —
// see IPosPrinterService.aidl's doc comment for why this file is needed
// at all (every real print method takes one of these).
interface IPosPrinterCallback {
    oneway void onRunResult(boolean isSuccess);
    oneway void onReturnString(String result);
}
