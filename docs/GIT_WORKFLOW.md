# NEXUS Market — Git والتسليم

## 1. الفروع والحماية
- `main` محمي ومستقر دائماً: لا Push مباشر، لا Force Push، دمج عبر PR فقط، وبعد مرور كل الفحوص.
- فروع العمل: `feat/<module>/<desc>` • `fix/<module>/<desc>` • `chore/<desc>` • `docs/<desc>`. قصيرة العمر، تُعاد قاعدتها على `main` قبل الـ PR.
- **لا دمج مباشر في `main` من الأعضاء.** كل الدمج يمر عبر Claude 1 (المدير التقني)، والقرار النهائي للمالك.
- الدمج بـ **Squash**. الوسوم: `v1.0.0-rc.N` ثم `v1.0.0`.

## 2. الرسائل (Conventional Commits)
`feat(sales): approve invoice use case` • `fix(inventory): rounding of cogs` • `test(accounting): balanced entries` • `docs(adr): ADR-012` • `chore(ci): add float check`.
النطاقات: `core, contracts, db, app, products, inventory, sales, pos, customers, purchasing, suppliers, accounting, backup, sync, ui, docs, ci`.

## 3. الملكية (CODEOWNERS)
- ملف `.github/CODEOWNERS` يحدد المالك لكل مسار. أي تعديل خارج نطاقك يحتاج موافقة Claude 1 المسبقة.
- **ملفات مشتركة (Claude 1 فقط):** `lib/app/**`, `lib/core/database/app_database.dart`, `lib/core/database/migrations/**`, `lib/contracts/**`, `lib/shared_ui/**`, `pubspec.yaml`, `pubspec.lock`, `.github/**`, `docs/**` (ما عدا ملفات ADR المقترحة).
- **جداول:** العضو يكتب مسودة جدوله في فرعه، ولا تُدمج إلا بعد مراجعة Claude 1 (SCR). لا جدول جديد خارج مجلد وحدته.
- لا يعدّل عضوان الملف نفسه في الوقت نفسه. التعارض المتوقع يُبلَّغ إلى Claude 1 قبل البدء.

## 4. بوابة الدمج (يجب أن تنجح كلها)
1. `dart format --set-exit-if-changed .`
2. `flutter analyze` (بلا تحذيرات)
3. `flutter test` (وحدة + عقود + مستودعات)
4. اختبار الترحيل ومقارنة لقطة المخطط (`drift_schemas/`)
5. `bash tool/check_no_float.sh`
6. اختبارات التكامل المعنية
7. مراجعة Claude 1: توافق معماري، لا تكرار (Models/Repositories/Services)، لا خرق لنطاق الملفات

## 5. التسليم (Handoff)
قالب PR (`.github/pull_request_template.md`) إلزامي. يتضمن: الملفات المنشأة، المعدّلة، مسؤولية كل ملف، العقود (ينفّذ/يستخدم)، الاعتماديات، الاختبارات **ونتائجها الفعلية ملصوقة**، المشكلات المعروفة، تعليمات الدمج.

## 6. أنماط التسليم (لأن الأعضاء جلسات Claude منفصلة)
| النمط | متى | الآلية |
|---|---|---|
| **A — مستودع مشترك** | لدى كل جلسة أدوات Git/تشغيل | كل عضو يدفع فرعه ويفتح PR؛ Claude 1 يراجع ويدمج |
| **B — تسليم ملفات (الأرجح)** | لا Git/تشغيل داخل الجلسات | العضو يسلّم مجلداً بنفس هيكل المشروع + `HANDOFF.md` (قالب PR). المالك يضعه في فرع `member/<n>/<task>` ويرسله لـ Claude 1 للمراجعة والدمج |
- في النمطين: **لا ادّعاء** بتشغيل اختبارات لم تُشغَّل. النتائج تُلصق كما ظهرت. إن تعذّر التشغيل يُكتب ذلك صراحةً في المشكلات المعروفة، ولا يُدمج الكود حتى يُشغَّل عند أحد.
- الصراحة تتفوق على الاكتمال: كود غير مختبر يُوسَم `UNTESTED` في التسليم.

## 7. حل التعارضات
Claude 1: يحدد السبب → يراجع العقود وADR → يختار الحل الأكثر توافقاً مع التصميم → يبلغ العضوين كتابةً بالتعديل المطلوب → لا حلول مؤقتة غير موثقة (أي استثناء يُسجَّل ADR).

## 8. إدارة الإصدارات
- `CHANGELOG.md` للتطبيق و`docs/contracts/CHANGELOG.md` للعقود.
- ترحيل قاعدة البيانات لا يُدمج دون اختبار ترحيل ولقطة مخطط.
