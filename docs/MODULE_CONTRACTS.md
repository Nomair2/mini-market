# NEXUS Market — عقود الوحدات (v1.0-draft)

العقود في `lib/contracts/` (Claude 1 فقط يكتبها). **تُجمَّد** عند نهاية المرحلة 0؛ بعدها أي تغيير = طلب تغيير عقد (CCR) ويُسجَّل في `docs/contracts/CHANGELOG.md`.

## 1. الأنواع المشتركة (`core/`)
```dart
/// مبلغ بأصغر وحدة (V1: ليرة كاملة). لا double إطلاقاً.
final class Money implements Comparable<Money> {
  final int minor;
  const Money(this.minor);
  Money operator +(Money o); Money operator -(Money o); Money operator -();
  /// تقريب لأقرب وحدة، نصف لأعلى (قيم موجبة وسالبة بتماثل بعيد عن الصفر)
  Money timesQuantity(Quantity q);          // = round(minor * q.milli / 1000)
  Money proportion(int numerator, int denominator); // = round(minor * n / d)
  bool get isZero; bool get isNegative;
}

/// كمية بالأَلف: 1500 = 1.500
final class Quantity implements Comparable<Quantity> {
  final int milli;
  const Quantity(this.milli);
  factory Quantity.fromWhole(int units) => Quantity(units * 1000);
  Quantity operator +(Quantity o); Quantity operator -(Quantity o);
}

typedef Id = String; // UUID v7

abstract interface class IdGenerator { Id next(); }
abstract interface class Clock { DateTime nowUtc(); }

abstract interface class UnitOfWork {
  /// يفتح معاملة أو ينضم لقائمة. أي استثناء = تراجع كامل.
  Future<T> run<T>(Future<T> Function() action);
  bool get isInTransaction;
}

abstract interface class DocumentNumberService {
  /// داخل معاملة قائمة. يعيد مثل SI-000123 بلا فجوات عند الفشل.
  Future<String> next(DocumentType type);
}

abstract interface class AppSettings {   // يعرّفها وينفّذها Claude 1 (features/settings)
  Future<bool> getBool(String key, {required bool fallback});
  Future<String?> getString(String key);
}
// V1: allow_negative_stock محجوز، ويُنفَّذ وضع "ممنوع" فقط. القيمة 1 ⇒ UnsupportedError.

abstract interface class AuditLogger {
  Future<void> log({required String action, required String entityType,
                    required Id entityId, Map<String, Object?> payload = const {}});
}
```
المزوّد: تعريف Claude 1، تنفيذ `UnitOfWork`/`DocumentNumberService`/`AuditLogger` عند Claude 5.

## 2. `InventoryPort` — المزوّد: Claude 2
```dart
final class ProductSnapshot {
  final Id id; final String sku; final String name; final String unitSymbol;
  final bool allowsFraction; final Money salePrice; final Quantity onHand; final bool isActive;
}

enum MovementType { opening, purchase, sale, saleReturn, purchaseReturn, adjustment, cancelReversal }

final class StockMovementDraft {
  final Id productId; final MovementType type;
  final Quantity quantityDelta;      // موقّعة: دخول +، خروج −
  /// دخول: القيمة المُدخَلة (تكلفة الشراء، أو تكلفة العكس cogs المحفوظة) — إلزامية.
  /// خروج: null ⇒ تُحسب بالمتوسط المرجح (بيع/تسوية)؛ غير null ⇒ قيمة صريحة
  /// (مرتجع شراء/إلغاء شراء). وإذا كان الخروج = كامل الرصيد تُؤخذ القيمة كلها دائماً.
  final Money? value;
  final String sourceType; final Id sourceId; final Id? sourceLineId;
  final DateTime occurredAt; final String? note;
}

final class StockMovementResult {
  final Id productId;
  /// القيمة **الفعلية** المطبَّقة (موقّعة): خروج −cogs ، دخول +value.
  /// المحاسبة تُبنى من هذه النتيجة لا من توقعات المستدعي.
  final Money valueDelta;
  final Quantity newOnHand; final Money newInventoryValue;
}

abstract interface class InventoryPort {
  Future<ProductSnapshot?> findById(Id productId);
  Future<ProductSnapshot?> findByBarcode(String barcode);
  Future<List<ProductSnapshot>> search(String query, {int limit = 30});
  Future<Quantity> onHand(Id productId);

  /// داخل UnitOfWork فقط (وإلا StateError). ذرّية على مستوى القائمة.
  /// خروج بلا رصيد كافٍ ⇒ InsufficientStockException (ما لم allow_negative_stock).
  /// يعيد نتيجة لكل حركة بنفس الترتيب (منها cogs للمبيعات).
  Future<List<StockMovementResult>> applyMovements(List<StockMovementDraft> movements);
}

abstract interface class InventoryQueryPort {   // قراءة للتقارير
  Future<List<StockLevelRow>> stockLevels({bool lowOnly = false});
  Future<Money> totalInventoryValue();
}
```

## 3. `PostingPort` — المزوّد: Claude 4
كل دالة داخل `UnitOfWork`، تبني قيداً متوازناً وتحفظه، وترمي `UnbalancedEntryException` عند الخلل. المدخلات أرقام وملخصات، **المحاسبة لا تقرأ جداول المبيعات/المشتريات**.
```dart
final class PaymentLine { final Id paymentMethodId; final Money amount; }

abstract interface class PostingPort {
  Future<Id> postSale(SalePostingData d);                 // d: documentId/number/date, customerId?, total, payments[], credit, totalCogs
  Future<Id> postSaleReturn(SaleReturnPostingData d);      // refund, refundMode(cash|account), customerId?, cogsReversed
  Future<Id> postPurchase(PurchasePostingData d);          // total, payments[], credit, supplierId
  Future<Id> postPurchaseReturn(PurchaseReturnPostingData d);
  // PurchaseReturnPostingData: supplierCredit (ما يُخصم للمورد) + inventoryValue (|valueDelta| الفعلي)
  // والفرق (إن وُجد) يُرحَّل إلى 5200 فروقات الجرد.
  Future<Id> postCustomerReceipt(CustomerReceiptPostingData d);
  Future<Id> postSupplierPayment(SupplierPaymentPostingData d);
  Future<Id> postStockAdjustment(StockAdjustmentPostingData d); // valueDelta موقّعة
  Future<Id> postExpense(ExpensePostingData d);
  Future<Id> postOwnerTransaction(OwnerTxPostingData d);
  Future<Id> postOpeningBalances(OpeningBalancesPostingData d);
  /// قيد عكسي كامل لقيد المصدر. لا حذف.
  Future<Id> reverseBySource({required String sourceType, required Id sourceId, required String reason});
}

abstract interface class AccountingQueryPort {
  Future<Money> partyBalance(PartyType type, Id partyId);   // عميل: موجب = مدين لنا
  Future<Money> accountBalance(String accountCode, {DateTime? asOf});
  Future<List<TrialBalanceRow>> trialBalance({DateTime? from, DateTime? to});
  Future<IncomeStatement> incomeStatement(DateTime from, DateTime to);
}
```

## 4. عقود القراءة بين الوحدات
```dart
abstract interface class CustomerQueryPort { // Claude 3
  Future<CustomerSnapshot?> findById(Id id);
  Future<List<CustomerSnapshot>> search(String q, {int limit = 30});
}
abstract interface class SupplierQueryPort { // Claude 4
  Future<SupplierSnapshot?> findById(Id id);
  Future<List<SupplierSnapshot>> search(String q, {int limit = 30});
}
abstract interface class SalesQueryPort {    // Claude 3 (تقارير)
  Future<SalesSummary> summary(DateTime from, DateTime to);
  Future<List<TopProductRow>> topProducts(DateTime from, DateTime to, {int limit = 20});
  Future<List<OpenReceivableRow>> openInvoices({Id? customerId});
}
abstract interface class PurchasingQueryPort { // Claude 4
  Future<PurchasesSummary> summary(DateTime from, DateTime to);
  Future<List<OpenPayableRow>> openInvoices({Id? supplierId});
}
```

## 5. خدمات البنية (Claude 5 تنفّذ، Claude 1 يعرّف)
```dart
abstract interface class BackupService {
  Future<BackupFile> createLocalBackup();                 // VACUUM INTO + ضغط
  Future<void> restoreFromFile(String path);              // تحقق من النسخة والسلامة قبل الاستبدال
  Future<List<BackupInfo>> history();
}
abstract interface class PdfService {                     // core/pdf: خطوط عربية + أدوات RTL
  Future<File> render(PdfDocumentSpec spec);
  Future<void> share(File file, {String? text});
}
```
قالب الفاتورة نفسه (المحتوى والتخطيط) ملك Claude 3 ويستخدم `PdfService`.

## 6. تدفق "اعتماد فاتورة بيع" (مرجعي — Claude 3)
```
uow.run(() {
  inv = salesRepo.getDraft(id); assert inv.status == draft
  validate(inv)                     // بنود>0، دفعات ≤ إجمالي، آجل ⇒ عميل
  warn if creditLimit exceeded      // تنبيه (يُؤكد المالك قبل الاستدعاء)
  number = docNumbers.next(salesInvoice)
  salesRepo.markApproved(inv, number)
  results = inventory.applyMovements(items → sale movements)
  salesRepo.saveCogs(items, results)               // cogs_minor لكل سطر
  accounting.postSale(SalePostingData(... totalCogs = Σcogs))
  audit.log('sales_invoice.approved', ...)
})
```
الإلغاء: `applyMovements(cancelReversal بقيمة cogs_minor المحفوظة)` + `reverseBySource` + `status=cancelled`.

## 7. قواعد العقود
1. كائنات البيانات immutable، بـ `Money`/`Quantity`/`Id` فقط، بلا `double`.
2. **Claude 5 يكتب مجموعات اختبارات العقد** (`test/contracts/<port>_contract_suite.dart`) كمواصفة قابلة للتنفيذ؛ وكل مزوّد يربطها بتنفيذه الحقيقي (`test/<module>/<port>_contract_test.dart`) وبالـ Fake.
3. Fakes جاهزة في `test/fakes/` (Claude 5) تتبع العقد نفسه، فلا ينتظر أحد أحداً.
4. تغيير عقد = CCR إلى Claude 1 + إصدار جديد في CHANGELOG + إشعار المزوّد والمستهلكين.
5. أي دالة تعدّل حالة ترمي `StateError` خارج `UnitOfWork`.
