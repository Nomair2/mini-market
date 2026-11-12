# NEXUS Market — المعمارية

## 1. المبدأ
**قاعدة SQLite واحدة مشتركة (Drift) + وحدات معزولة تتواصل عبر عقود (Interfaces) فقط + كل عملية أعمال في معاملة واحدة ذرّية.** SQLite هي مصدر الحقيقة، ولا يحتاج أي مسار تشغيلي (بيع/شراء/مخزون) إلى إنترنت.

## 2. الطبقات داخل كل وحدة
```
presentation   (Widgets + Riverpod Notifiers)          ← الواجهة فقط
     ↓
application    (Use Cases — نقطة الذرّية UnitOfWork)    ← منطق الأعمال المنسَّق
     ↓
domain         (Entities, Value Objects, Repository interfaces, Ports)
     ↑
data           (Drift DAOs + Repository implementations)
```
- `domain` لا يعتمد على Flutter ولا Drift ولا أي وحدة أخرى.
- `application` يعتمد على `domain` و`contracts` فقط.
- `data` ينفّذ واجهات المستودعات ويعتمد على `core/database`.
- `presentation` يعتمد على `application` فقط.

## 3. Repository Pattern
- واجهة كل مستودع في `domain/`، تنفيذه في `data/` (تعتمد على DAO).
- المستودعات تُرجع كيانات `domain` (لا صفوف Drift) وتتعامل بـ `Money` و`Quantity` فقط.
- المستودع **لا يبدأ معاملة**؛ المعاملة يفتحها الـ Use Case عبر `UnitOfWork`.

## 4. UnitOfWork والذرّية
- `UnitOfWork.run(action)` تغلّف `db.transaction`. استدعاءات DAO المتداخلة تنضم تلقائياً لنفس المعاملة (Drift يمرّر المعاملة عبر Zone).
- كل Use Case يغيّر أكثر من جدول يعمل داخل `run` واحد، بما فيه الاستدعاءات عبر `InventoryPort` و`PostingPort`.
- أي استثناء يُلغي كل شيء. الواجهات التي تعدّل الحالة (`applyMovements`, `post*`) ترمي `StateError` إن استُدعيت خارج معاملة.
- إعدادات SQLite: `PRAGMA foreign_keys = ON`، `journal_mode = WAL`، `synchronous = FULL` (سلامة البيانات أهم من السرعة في المال).

## 5. التواصل بين الوحدات
1. وحدة تستدعي وحدة أخرى **فقط** عبر Interface في `lib/contracts/`.
2. لا استيراد لـ `data/` أو `presentation/` من وحدة أخرى.
3. لا كتابة مباشرة في جداول وحدة أخرى. القراءة عبر Query Ports.
4. لكل Interface مزوّد واحد. العقود تُجمَّد بعد المرحلة 0، وتُغيَّر بطلب تغيير (CCR).
5. الربط الفعلي (من ينفّذ ماذا) يتم في `lib/app/providers/composition_root.dart` (Claude 1 فقط).

**مخطط الاعتماد المسموح** (الأسهم = "يستخدم"):
```
Sales (3)      → InventoryPort (2), PostingPort (4), AccountingQueryPort (4), Core
Customers (3)  → PostingPort (4), Core
Purchasing (4) → InventoryPort (2), PostingPort (4), Core
Suppliers (4)  → PostingPort (4), Core
Accounting (4) → Core
Inventory (2)  → PostingPort (4) [لتسويات الجرد], Core
OpeningBalances (4) → InventoryPort (2), CustomerQueryPort (3), SupplierQueryPort (4)
Backup/Sync (5) → Core فقط (قراءة/نسخ ملف القاعدة، outbox)
Reports        → Query Ports فقط
```
يسمح بأن تعتمد وحدتان على **عقد** بعضهما (Inventory↔Accounting)، بشرط ألا تتشكل **دورة بين الخدمات الفعلية** عند الحقن: `JournalService` (ينفّذ `PostingPort`) لا يعتمد على `InventoryPort`.

## 6. تدفقات الأعمال الذرّية (ملخص؛ التفصيل في MODULE_CONTRACTS)
**اعتماد فاتورة بيع:** تحقق (draft، الرصيد، حد الائتمان تنبيهاً) → رقم المستند → حفظ الفاتورة approved وبنودها → `InventoryPort.applyMovements` (يعيد `cogs_minor` لكل سطر) → حفظ `cogs_minor` في البنود → `PostingPort.postSale` → تدقيق. فشل أي خطوة = تراجع كامل.

**الإلغاء:** حركات عكسية بتكلفة اللقطة + قيد عكسي + حالة `cancelled`.
**المرتجع:** مستند مستقل مرتبط بالأصل. **الشراء:** رفع الكمية والقيمة + قيد. **التسوية:** حركة `adjustment` + قيد.

## 7. المحاسبة
قيد مزدوج مبسّط بدليل حسابات جاهز (انظر DATABASE_SCHEMA). كل عملية مالية = `journal_entry` + سطور. التحقق: مجموع المدين = مجموع الدائن (يفرضه الـ Use Case، ويفحصه اختبار، ويتحقق منه Trigger اختياري عند الاعتماد). أرصدة العملاء والموردين **مشتقة** من سطور القيود (الحقل `party`).

## 8. تقنيات الواجهة
- Riverpod: `Provider`/`Notifier`؛ الـ Providers تُربط في طبقة التركيب. لا منطق أعمال في Widgets.
- GoRouter: لكل وحدة `routes.dart`؛ التسجيل في `app_router.dart` (Claude 1).
- RTL كامل: `Directionality` عربي، `EdgeInsetsDirectional`/`AlignmentDirectional` فقط (لا left/right). نصوص عبر `intl` (ARB عربي واحد) لا نصوص ثابتة في الودجات.
- الفاتورة PDF: خدمة مشتركة `core/pdf` (خطوط عربية مضمّنة في `assets/fonts`) يبني عليها Claude 3 قالب الفاتورة. المشاركة عبر قائمة مشاركة النظام.
- الباركود: ودجت واحد في `shared_ui` (كاميرا) يُستهلك من المنتجات وPOS.

## 9. النسخ الاحتياطي والمزامنة
- نسخة محلية: لقطة متسقة لملف القاعدة (`VACUUM INTO`) + مشاركة/حفظ. (مقترح للمرحلة 3.)
- Firebase (المرحلة 4): رفع النسخ الاحتياطية واستعادتها. المزامنة ثنائية الاتجاه خيار لاحق عبر `sync_outbox`.
- أي فشل شبكة لا يؤثر على التشغيل المحلي.

## 10. معالجة الأخطاء
استثناءات نطاقية مطبوعة (`InsufficientStockException`, `UnbalancedEntryException`, `ImmutableDocumentException`, `DocumentStateException`, `CreditLimitWarning`…) معرّفة في `core/errors`. لا يُبتلع استثناء. الواجهة تعرض رسالة عربية مفهومة.

## 11. الأداء والحجم المستهدف
متجر واحد: حتى ~50 ألف منتج، مئات الفواتير يومياً. الفهارس مصممة لذلك (DATABASE_SCHEMA §فهارس). البحث بالاسم/الباركود < 100ms على جهاز متوسط (يُقاس في المرحلة 5).
