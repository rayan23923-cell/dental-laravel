/**
 * What a "غير سليم" lab result is (2026-11-03, by request): B, C, HIV,
 * one or more. Same codes and labels as App\Support\ScreeningDiagnosis.
 */
export const DIAGNOSIS_CODES = ['B', 'C', 'HIV'];

export const DIAGNOSIS_LABELS = {
    B: 'التهاب الكبد B',
    C: 'التهاب الكبد C',
    HIV: 'HIV',
};

/** "التهاب الكبد B، HIV", or '' when the result is not flagged / has none. */
export const diagnosisText = (r) => {
    if (r?.screening_status !== 'flagged') return '';
    const codes = Array.isArray(r?.screening_diagnoses) ? r.screening_diagnoses : [];
    return DIAGNOSIS_CODES.filter((c) => codes.includes(c)).map((c) => DIAGNOSIS_LABELS[c]).join('، ');
};
