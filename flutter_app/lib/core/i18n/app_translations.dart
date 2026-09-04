/// Bilingual UI strings (2026-09-04, by request — same feature as the
/// web's `resources/js/locales/{ar,en}.json`, ported here). Deliberately a
/// pair of plain flat `Map<String, String>` constants rather than JSON
/// assets + async loading — the content is small enough that Dart source
/// is simpler and has zero load latency, unlike the web's vue-i18n setup
/// which already had a JSON-file convention to match.
///
/// Scoped the same way as the web pass: only chrome around the app
/// (sidebar nav, login, profile) goes through this. Case-sheet field
/// labels come from the server's own `CaseSheetSection`/`CaseSheetField`
/// schema (`case_sheet_form_schema.dart`) and stay exactly as they are
/// regardless of locale, by request ("ماعدا الاسماء الطبية تبقى على
/// وضعها في الكيس شيت") — nothing here touches that code path.
///
/// Both maps MUST carry the same key set — `tr()` falls back to the key
/// itself if a locale is missing one, which would silently ship an
/// untranslated string rather than fail loudly, so keep them in sync by
/// hand.
library;

const Map<String, String> kTranslationsAr = {
  'nav.clinicName': 'العيادة التعليمية',
  'nav.settings': 'الإعدادات',
  'nav.logout': 'تسجيل الخروج',
  'nav.logoutConfirmTitle': 'تسجيل الخروج؟',
  'nav.logoutConfirmBody': 'سيتم إنهاء الجلسة الحالية.',
  'nav.cancel': 'إلغاء',
  'nav.home': 'الرئيسية',
  'nav.records': 'السجلات',
  'nav.admin': 'الإدارة',
  'nav.notifications': 'الإشعارات',
  'nav.caseSheets': 'النماذج السريرية',
  'nav.scanQr': 'مسح QR',
  'nav.pendingTasksQr': 'رموز المهام المعلقة',
  'nav.myTasks': 'مهامي',

  'auth.subtitle1': 'المستشفى التعليمي لكلية طب الأسنان',
  'auth.subtitle2': 'جامعة تكريت',
  'auth.loginPlaceholder': 'البريد الإلكتروني أو اسم المستخدم',
  'auth.passwordPlaceholder': 'كلمة المرور',
  'auth.forgotPassword': 'نسيت كلمة المرور؟',
  'auth.signIn': 'تسجيل الدخول',
  'auth.requiredField': 'هذا الحقل مطلوب',
  'auth.closeBanner': 'إغلاق',

  'profile.title': 'الملف الشخصي',
  'profile.changePhoto': 'تغيير الصورة',
  'profile.personalInfo': 'المعلومات الشخصية',
  'profile.name': 'الاسم',
  'profile.email': 'البريد الإلكتروني',
  'profile.phone': 'رقم الهاتف',
  'profile.saveChanges': 'حفظ التغييرات',
  'profile.changePassword': 'تغيير كلمة المرور',
  'profile.currentPassword': 'كلمة المرور الحالية',
  'profile.newPassword': 'كلمة المرور الجديدة',
  'profile.confirmPassword': 'تأكيد كلمة المرور',
  'profile.requiredField': 'هذا الحقل مطلوب',
  'profile.passwordTooShort': 'يجب أن تتكون من 6 أحرف على الأقل',
  'profile.passwordMismatch': 'كلمتا المرور غير متطابقتين',
  'profile.activeSessions': 'الأجهزة النشطة',
  'profile.activeSessionsSubtitle': 'إدارة الأجهزة المسجّل الدخول منها إلى هذا الحساب',
  'profile.updatedSuccess': 'تم تحديث الملف الشخصي.',
  'profile.saveFailed': 'تعذر الحفظ.',
  'profile.passwordChangedSuccess': 'تم تغيير كلمة المرور.',
  'profile.passwordChangeFailed': 'تعذر تغيير كلمة المرور.',
  'profile.language': 'اللغة',
  'profile.languageSystem': 'حسب لغة النظام',
  'profile.languageAr': 'العربية',
  'profile.languageEn': 'English',

  'common.close': 'إغلاق',

  'settingsMenu.printerSettings': 'إعدادات الطابعة',
  'settingsMenu.clinicSettings': 'إعدادات العيادة',
  'settingsMenu.permissions': 'الصلاحيات',
  'settingsMenu.activityLog': 'سجل النشاط',
  'settingsMenu.backup': 'النسخ الاحتياطي',

  'screening.blockedFlagged': 'لا يمكن الدفع — نتيجة فحص المريض غير سليمة.',
  'screening.blockedNotChecked': 'لا يمكن الدفع قبل تأكيد سلامة المريض من الأمراض المعدية عبر فحص المختبر.',

  'payment.paidTotal': 'تم الدفع — إجمالي المدفوع: ',
  'payment.notPaid': 'لم يتم الدفع',

  'academicYear.active': 'العام الدراسي النشط: ',

  'home.staffRole': 'موظف',
  'home.quickShortcuts': 'اختصارات سريعة',
  'home.sections': 'الأقسام',
  'home.recordsSubtitle': 'المرضى، المواعيد، الدفعات',
  'home.adminSubtitle': 'الأطباء، البيانات الأساسية، الإعدادات',

  'labels.registerNewPatient': 'تسجيل مريض جديد',
  'labels.registerPatients': 'تسجيل المرضى',
  'labels.appointments': 'المواعيد',
  'labels.payments': 'الدفعات',
  'labels.taskProgress': 'تقدم المهام',
  'labels.lab': 'المختبر',

  'adminHub.doctorsGroup': 'إدارة الأطباء',
  'adminHub.doctors': 'الأطباء',
  'adminHub.groups': 'المجموعات',
  'adminHub.clinicChairs': 'خريطة كراسي العيادة',
  'adminHub.referenceData': 'البيانات الأساسية',
  'adminHub.academicSessions': 'الأعوام الدراسية',
  'adminHub.educationTypes': 'أنواع التعليم',
  'adminHub.stages': 'المراحل',
  'adminHub.departments': 'الأقسام',
  'adminHub.tasks': 'المهام',
  'adminHub.caseSheetTypes': 'أنواع النماذج السريرية',
  'adminHub.workflow': 'سير العمل',
};

const Map<String, String> kTranslationsEn = {
  'nav.clinicName': 'Teaching Clinic',
  'nav.settings': 'Settings',
  'nav.logout': 'Log Out',
  'nav.logoutConfirmTitle': 'Log out?',
  'nav.logoutConfirmBody': 'This session will be ended.',
  'nav.cancel': 'Cancel',
  'nav.home': 'Home',
  'nav.records': 'Records',
  'nav.admin': 'Admin',
  'nav.notifications': 'Notifications',
  'nav.caseSheets': 'Case Sheets',
  'nav.scanQr': 'Scan QR',
  'nav.pendingTasksQr': 'Pending Task Codes',
  'nav.myTasks': 'My Tasks',

  'auth.subtitle1': 'Teaching Hospital, College of Dentistry',
  'auth.subtitle2': 'Tikrit University',
  'auth.loginPlaceholder': 'Email or Username',
  'auth.passwordPlaceholder': 'Password',
  'auth.forgotPassword': 'Forgot your password?',
  'auth.signIn': 'Sign In',
  'auth.requiredField': 'This field is required',
  'auth.closeBanner': 'Close',

  'profile.title': 'Profile',
  'profile.changePhoto': 'Change Photo',
  'profile.personalInfo': 'Personal Information',
  'profile.name': 'Name',
  'profile.email': 'Email',
  'profile.phone': 'Phone Number',
  'profile.saveChanges': 'Save Changes',
  'profile.changePassword': 'Change Password',
  'profile.currentPassword': 'Current Password',
  'profile.newPassword': 'New Password',
  'profile.confirmPassword': 'Confirm Password',
  'profile.requiredField': 'This field is required',
  'profile.passwordTooShort': 'Must be at least 6 characters',
  'profile.passwordMismatch': 'Passwords do not match',
  'profile.activeSessions': 'Active Sessions',
  'profile.activeSessionsSubtitle': 'Manage devices signed in to this account',
  'profile.updatedSuccess': 'Profile updated.',
  'profile.saveFailed': 'Could not save.',
  'profile.passwordChangedSuccess': 'Password changed.',
  'profile.passwordChangeFailed': 'Could not change password.',
  'profile.language': 'Language',
  'profile.languageSystem': 'Match system language',
  'profile.languageAr': 'العربية',
  'profile.languageEn': 'English',

  'common.close': 'Close',

  'settingsMenu.printerSettings': 'Printer Settings',
  'settingsMenu.clinicSettings': 'Clinic Settings',
  'settingsMenu.permissions': 'Permissions',
  'settingsMenu.activityLog': 'Activity Log',
  'settingsMenu.backup': 'Backup',

  'screening.blockedFlagged': "Payment isn't possible — the patient's screening result is flagged.",
  'screening.blockedNotChecked': "Payment isn't possible until the patient's infectious-disease screening is confirmed clear.",

  'payment.paidTotal': 'Paid — total paid: ',
  'payment.notPaid': 'Not paid',

  'academicYear.active': 'Active academic year: ',

  'home.staffRole': 'Staff',
  'home.quickShortcuts': 'Quick Shortcuts',
  'home.sections': 'Sections',
  'home.recordsSubtitle': 'Patients, appointments, payments',
  'home.adminSubtitle': 'Doctors, reference data, settings',

  'labels.registerNewPatient': 'Register New Patient',
  'labels.registerPatients': 'Register Patients',
  'labels.appointments': 'Appointments',
  'labels.payments': 'Payments',
  'labels.taskProgress': 'Task Progress',
  'labels.lab': 'Lab',

  'adminHub.doctorsGroup': 'Doctor Management',
  'adminHub.doctors': 'Doctors',
  'adminHub.groups': 'Groups',
  'adminHub.clinicChairs': 'Clinic Chair Map',
  'adminHub.referenceData': 'Reference Data',
  'adminHub.academicSessions': 'Academic Sessions',
  'adminHub.educationTypes': 'Education Types',
  'adminHub.stages': 'Stages',
  'adminHub.departments': 'Departments',
  'adminHub.tasks': 'Tasks',
  'adminHub.caseSheetTypes': 'Case Sheet Types',
  'adminHub.workflow': 'Workflow',
};
