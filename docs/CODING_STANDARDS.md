# NEXUS Market — معايير الكود

## 1. التسمية
- ملفات Dart: `snake_case.dart`. كلاسات: `PascalCase`. متغيرات ودوال: `camelCase`. ثوابت: `lowerCamelCase`.
- جداول Drift: الكلاس `SalesInvoices` ⇄ الجدول `sales_invoices`. الأعمدة `camelCase` في Dart تُترجم تلقائياً لـ `snake_case`.
- Use Case: فعل + مفعول: `ApproveSalesInvoice`، ملف `approve_sales_invoice.dart`، دالة واحدة `call()`.
- Repository: واجهة `SalesInvoiceRepository` (domain)، تنفيذ `DriftSalesInvoiceRepository` (data).
- Providers: `<name>Provider`، تُعرَّف في `application/providers.dart` لكل وحدة وتُربط في طبقة التركيب.

## 2. المال والكميات (ممنوعات صارمة)
1. لا `double` ولا `num` ولا `REAL` في أي حساب أو تخزين مالي أو كمّي. الفحص الآلي: `tool/check_no_float.sh`.
2. المال دائماً `Money`، الكمية `Quantity`. لا `int` خام يتنقل بين الدوال بمعنى مبلغ.
3. لا حساب نسب بـ `/ 100`. تستخدم `Money.proportion(n, d)` و`Money.timesQuantity(q)`.
4. التحويل لنص للعرض فقط في طبقة العرض (`MoneyFormatter`: فواصل آلاف، "ل.س").
5. مدخل المستخدم يُحوَّل لنص → `Money` عبر محلّل يرفض الكسور في V1، دون `double.parse`.

## 3. الطبقات والاعتماديات
- التزم بمخطط الاعتماد في ARCHITECTURE §2 و§5. استيراد مخالف = رفض PR.
- لا منطق أعمال في `presentation`. لا Drift في `domain`/`application`.
- لا استيراد ملف `data/` أو `presentation/` من وحدة أخرى. التواصل عبر `lib/contracts/`.

## 4. الذرّية والمستندات
- أي Use Case يكتب أكثر من جدول = داخل `uow.run`.
- لا `delete` على جداول المستندات المعتمدة ولا على جداول الإضافة-فقط. التصحيح بإلغاء/مرتجع/قيد عكسي.
- الانتقالات بين الحالات تُفحص صراحةً (`draft → approved → cancelled`)، وأي انتقال غير مسموح يرمي `DocumentStateException`.

## 5. الأخطاء
- استثناءات نطاقية مطبوعة من `core/errors` (لا `Exception('...')` نصي).
- لا `catch (_) {}` صامت. السجل عبر `core/logging`، ولا يُسجَّل محتوى مالي حساس في سجلات التصحيح.

## 6. الواجهة العربية (RTL)
- نصوص عبر `AppLocalizations` (ARB عربي واحد: `lib/l10n/app_ar.arb`). لا نصوص ثابتة داخل Widgets.
- استخدم `EdgeInsetsDirectional`, `AlignmentDirectional`, `PositionedDirectional`, `start/end` لا `left/right`.
- الأرقام: أرقام لاتينية (0-9) افتراضياً للمبالغ، مع إعداد لاحق للأرقام العربية الهندية إن طُلب.
- كل شاشة تُختبر بصرياً RTL على شاشة صغيرة (360dp) وكبيرة. حالات: تحميل، فارغ، خطأ، بيانات طويلة.
- مكونات مشتركة (أزرار، حقول مال، ماسح باركود، حوار تأكيد) من `shared_ui` فقط. لا نسخ مكررة.

## 7. الاختبارات
| النوع | المطلوب |
|---|---|
| وحدة (domain/application) | كل Use Case: المسار الناجح + كل فشل نصّ عليه التصميم + الحالات الحدية |
| مستودعات | على قاعدة Drift في الذاكرة (`NativeDatabase.memory`) |
| عقود | مجموعة اختبارات العقد لكل Port يزوّده العضو |
| ترحيل | كل `schemaVersion` جديد |
| تكامل | سيناريوهات بين وحدات (Claude 5 + المالكون) |
| واجهة | Widget tests للشاشات الحرجة (POS، الدفع) |
- تغطية الـ domain/application للمال والمخزون والمحاسبة ≥ 90%.
- اختبارات إلزامية للتقريب (موجب/سالب/حدود .5)، المتوسط المرجح، عدم التوازن، المخزون السالب، منع تعديل المعتمد.
- لا اختبار يعتمد على الوقت الحقيقي (استخدم `Clock` وهمية) أو على ترتيب التنفيذ.

## 8. الجودة الآلية
- `dart format --set-exit-if-changed .` • `flutter analyze` بلا تحذيرات • `analysis_options.yaml` يفعّل `flutter_lints` + `strict-casts` + `strict-raw-types` + `prefer_const_constructors` + `always_declare_return_types` + `avoid_dynamic_calls`.
- لا `// ignore:` دون سطر سبب. لا `TODO` بلا رقم مهمة.
- حجم الملف: يفضَّل < 300 سطر؛ الدالة < 50 سطراً.

## 9. الاعتماديات (pubspec)
- تعديل `pubspec.yaml` من Claude 1 فقط. العضو يطلب الحزمة بتبرير (ما الحاجة، البدائل، الحجم).
- الحزم المعتمدة مبدئياً: `drift`, `drift_flutter`/`sqlite3_flutter_libs`, `flutter_riverpod`, `go_router`, `uuid` (v7), `intl`, `pdf`, `printing` أو `share_plus`, `mobile_scanner`, `path_provider`, `archive`, `firebase_core`, `firebase_storage` (المرحلة 4)، `mocktail`.
- تُثبَّت الإصدارات بدقة، وكل إصدار مرشَّح بعمر لا يقل عن أسبوعين.

## 10. التوثيق
- كل Interface في `contracts/` موثَّق (`///`): الشروط المسبقة، الاستثناءات، الذرّية.
- كل قرار معماري = ملف في `docs/adr/` (صيغة: السياق، القرار، البدائل، النتائج).
