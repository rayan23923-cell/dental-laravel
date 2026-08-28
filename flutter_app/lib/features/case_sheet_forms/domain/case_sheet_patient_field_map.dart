/// "مسح رمز المريض" (2026-08-28) — which of each case-sheet resource's own
/// real column names (per its model's `$fillable`, not assumed uniform)
/// holds the patient's name/phone/age/sex/address/occupation, so a scan of
/// the same registration-ticket QR used elsewhere can autofill them.
/// Deliberately a client-side constant rather than a new API endpoint — the
/// mapping is static and small enough to duplicate here, mirroring the
/// identical `PATIENT_FIELD_MAP` in `resources/js/Pages/Specialty/
/// SectionedForm.vue`, the same way `CaseSheetResolver`'s `ROUTES` map
/// already has no client-side API equivalent either. `prevention-records`
/// packs its patient fields into the `patient_data` JSON group instead of
/// real columns, so its map targets the grouped `patient_data__*` form keys
/// (see `DynamicSectionForm`'s `formKey`/group reassembly) — same flat
/// `setFieldIfBlank(formKey, …)` target either way.
class CaseSheetPatientField {
  const CaseSheetPatientField({this.name, this.phone, this.age, this.sex, this.address, this.occupation});
  final String? name;
  final String? phone;
  final String? age;
  final String? sex;
  final String? address;
  final String? occupation;
}

const Map<String, CaseSheetPatientField> kCaseSheetPatientFieldMap = {
  'dental-charts': CaseSheetPatientField(
    name: 'patient_id',
    phone: 'patient_phone',
    age: 'patient_age',
    sex: 'patient_sex',
    address: 'patient_address',
    occupation: 'patient_occupation',
  ),
  'oral-medicine-charts': CaseSheetPatientField(
    name: 'patient_id',
    phone: 'patient_phone',
    age: 'patient_age',
    sex: 'patient_sex',
    address: 'patient_address',
    occupation: 'patient_occupation',
  ),
  'surgeries': CaseSheetPatientField(
    name: 'patient_name',
    phone: 'patient_phone',
    age: 'patient_age',
    sex: 'patient_gender',
    address: 'patient_address',
    occupation: 'patient_occupation',
  ),
  'periodontal-charts': CaseSheetPatientField(
    name: 'patient_name',
    phone: 'patient_phone',
    age: 'patient_age',
    sex: 'patient_gender',
    address: 'patient_address',
    occupation: 'patient_occupation',
  ),
  'prosthodontics-records': CaseSheetPatientField(
    name: 'patient_name',
    phone: 'telephone',
    age: 'age',
    sex: 'sex',
    address: 'address',
    occupation: 'occupation',
  ),
  'complete-denture-records': CaseSheetPatientField(
    name: 'patient_name',
    phone: 'telephone',
    age: 'age',
    sex: 'sex',
    address: 'address',
    occupation: 'occupation',
  ),
  'orthodontics-records': CaseSheetPatientField(
    name: 'patient_name',
    phone: 'patient_phone',
    age: 'patient_age',
    sex: 'patient_sex',
    address: 'patient_address',
  ),
  'prevention-records': CaseSheetPatientField(
    name: 'patient_data__child_name',
    phone: 'patient_data__phone_number',
    age: 'patient_data__patient_age',
    sex: 'patient_data__patient_gender',
  ),
};
