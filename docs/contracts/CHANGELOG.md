# سجل إصدارات العقود

صيغة: `MAJOR.MINOR` — MAJOR تغيير يكسر المستهلكين، MINOR إضافة متوافقة.

## v1.0-draft — 2026-11-12 (Claude 1)
- أول مسودة: `Money`, `Quantity`, `UnitOfWork`, `DocumentNumberService`, `AuditLogger`, `IdGenerator`, `Clock`.
- `InventoryPort`, `InventoryQueryPort`, `PostingPort`, `AccountingQueryPort`.
- `CustomerQueryPort`, `SupplierQueryPort`, `SalesQueryPort`, `PurchasingQueryPort`.
- `BackupService`, `PdfService`.
- **الحالة:** غير مجمّد. يُجمَّد (v1.0) عند اعتماد المالك ونهاية المرحلة 0.

## قالب إدخال جديد
```
## vX.Y — التاريخ (من وافق)
- Added / Changed / Removed: ...
- يؤثر على: (المزوّد / المستهلكون)
- CCR: رابط/رقم
```

## v1.0-draft.2 — 2026-11-12 (Claude 1)
- `StockMovementDraft.inValue` → `value` (للخروج: قيمة صريحة اختيارية). `StockMovementResult.valueDelta` هي المرجع الفعلي للمحاسبة.
- إضافة `AppSettings` (core).
- `PurchaseReturnPostingData`: `supplierCredit` + `inventoryValue`؛ الفرق إلى 5200.
- اختبارات العقد يكتبها Claude 5 ويربطها كل مزوّد.
