// Prints a print page (one with ?autoprint=1) in a hidden frame, so saving
// goes straight to the print dialog without a new tab (2026-10-18, by
// request). In the LAN client app the print is silent to the thermal printer.
export const printInFrame = (url) => {
    document.getElementById('print-frame')?.remove();
    const frame = document.createElement('iframe');
    frame.id = 'print-frame';
    frame.style.cssText = 'position:fixed;width:0;height:0;border:0;visibility:hidden';
    frame.src = url;
    document.body.appendChild(frame);
};
