package com.iposprinter.iposprinterservice;

import com.iposprinter.iposprinterservice.IPosPrinterCallback;
import android.graphics.Bitmap;

// Replaces an earlier, WRONG reconstruction of this file that was based
// only on the vendor's summary-table PDF ("2C-POS-V1 Mobile POS Printer
// SDK") — that PDF's tables omitted the `IPosPrinterCallback` parameter
// every method actually takes. The omission wasn't cosmetic: AIDL
// transaction codes are positional, so a client interface with a
// different parameter list per method talks to the wrong method on the
// real service. Confirmed broken by an actual on-device print attempt —
// real error: "Attempt to invoke interface method void
// com.iposprinterservice.IPosPrinterCallback.onRunResult(boolean) on a
// null object reference" — before this fix.
//
// This version is transcribed verbatim from
// https://github.com/paystory-de/cordova-plugin-iposprinter
// (src/aidl/iposprinterservice/IPosPrinterService.aidl,
// Apache-2.0-licensed), an open-source Cordova plugin wrapping this exact
// AIDL service — found by
// searching for the real error message above and cross-checked against
// the vendor PDF (method names/behavior match; this file's callback
// parameters and printerPerformPrint's extra `feedlines` int are the
// corrections). Kept in sync with that plugin's Java reference
// implementation (`IPosPrinterCordovaPlugin.java`) that `PosPrinterPlugin.kt`
// mirrors.
interface IPosPrinterService {
    int getPrinterStatus();
    void printerInit(in IPosPrinterCallback callback);
    void setPrinterPrintDepth(int depth, in IPosPrinterCallback callback);
    void setPrinterPrintFontType(String typeface, in IPosPrinterCallback callback);
    void setPrinterPrintFontSize(int fontsize, in IPosPrinterCallback callback);
    void setPrinterPrintAlignment(int alignment, in IPosPrinterCallback callback);
    void printerFeedLines(int lines, in IPosPrinterCallback callback);
    void printBlankLines(int lines, int height, in IPosPrinterCallback callback);
    void printText(String text, in IPosPrinterCallback callback);
    void printSpecifiedTypeText(String text, String typeface, int fontsize, in IPosPrinterCallback callback);
    void PrintSpecFormatText(String text, String typeface, int fontsize, int alignment, IPosPrinterCallback callback);
    void printColumnsText(in String[] colsTextArr, in int[] colsWidthArr, in int[] colsAlign, int isContinuousPrint, in IPosPrinterCallback callback);
    void printBitmap(int alignment, int bitmapSize, in Bitmap mBitmap, in IPosPrinterCallback callback);
    void printBarCode(String data, int symbology, int height, int width, int textposition, in IPosPrinterCallback callback);
    void printQRCode(String data, int modulesize, int mErrorCorrectionLevel, in IPosPrinterCallback callback);
    void printRawData(in byte[] rawPrintData, in IPosPrinterCallback callback);
    void sendUserCMDData(in byte[] data, in IPosPrinterCallback callback);
    void printerPerformPrint(int feedlines, in IPosPrinterCallback callback);
}
