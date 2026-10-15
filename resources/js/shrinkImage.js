/**
 * Photos of paper forms (2026-10-13): a phone camera's photo is several
 * megabytes; this redraws it as a JPEG no larger than `max` pixels on its
 * long side, turned the way the camera held it, before it is uploaded.
 * Anything it can't read is sent as it is.
 */
export async function shrinkImage(file, max = 2000, quality = 0.82) {
    if (!file?.type?.startsWith('image/') || typeof createImageBitmap !== 'function') return file;
    try {
        const bitmap = await createImageBitmap(file, { imageOrientation: 'from-image' });
        const scale = Math.min(1, max / Math.max(bitmap.width, bitmap.height));
        if (scale === 1 && file.type === 'image/jpeg' && file.size < 1_500_000) {
            bitmap.close?.();
            return file;
        }
        const canvas = document.createElement('canvas');
        canvas.width = Math.round(bitmap.width * scale);
        canvas.height = Math.round(bitmap.height * scale);
        canvas.getContext('2d').drawImage(bitmap, 0, 0, canvas.width, canvas.height);
        bitmap.close?.();
        const blob = await new Promise((resolve) => canvas.toBlob(resolve, 'image/jpeg', quality));
        if (!blob) return file;
        return new File([blob], `${file.name.replace(/\.[^.]+$/, '') || 'photo'}.jpg`, { type: 'image/jpeg' });
    } catch {
        return file;
    }
}
