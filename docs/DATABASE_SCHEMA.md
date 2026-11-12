# NEXUS Market — مخطط قاعدة البيانات (V1)

قاعدة واحدة `nexus.db` عبر `AppDatabase` (Drift). **مالك المخطط: Claude 1.** أي تغيير = طلب تغيير مخطط (SCR) + `schemaVersion` + ترحيل + اختبار ترحيل.

## 1. اتفاقيات
| العنصر | القاعدة |
|---|---|
| أسماء الجداول | `snake_case` جمع: `sales_invoices` |
| المعرّف | `id TEXT PK` = UUID v7 يُولَّد على الجهاز |
| مفتاح أجنبي | `<entity>_id` |
| المال | `INTEGER` بأصغر وحدة، لاحقة `_minor` (V1: ليرة كاملة، صفر خانات) |
| الكمية | `INTEGER` بالأَلف، لاحقة `_milli` (1.500 كغ = 1500) |
| الوقت | `INTEGER` UTC epoch ms، لاحقة `_at`؛ التاريخ المحاسبي `entry_date` نصي `YYYY-MM-DD` محلي |
| المنطقي | `INTEGER 0/1`، بادئة `is_` |
| الحالات | `TEXT` + `CHECK(... IN (...))` |
| ممنوع | `REAL`/`FLOAT`/`DOUBLE` في أي عمود |

**أعمدة أساسية (Base) في كل جدول أعمال:** `id, store_id, created_at, updated_at, created_by, updated_by`.
**بيانات رئيسية (Master Data) تضيف:** `deleted_at` (حذف منطقي؛ لا يُحذف سجل مرتبط بمستند).
**جداول إضافة-فقط (append-only)** لا تحمل `updated_*` ولا `deleted_at`.

التقريب: `line_total = round_half_up(unit_price_minor × quantity_milli / 1000)`. الخصم يُخزَّن مبلغاً صحيحاً (لا نسبة).

## 2. جداول النواة والبنية (Claude 1 / Claude 5)
| الجدول | الأعمدة الخاصة | ملاحظات |
|---|---|---|
| `stores` | name, phone, address, currency_code ('SYP'), currency_minor_digits (0) | صف واحد |
| `users` | display_name, role ('owner'), is_active | صف واحد (المالك)، بلا شاشة دخول |
| `app_settings` | key PK, value, updated_at | `allow_negative_stock`=0، `invoice_paper`='A5'، `app_lock_enabled`… |
| `payment_methods` | name, account_id→accounts, is_active | مبذورة: نقد، تحويل/محفظة |
| `document_sequences` | doc_type, prefix, next_number | UNIQUE(store_id, doc_type)؛ تُزاد داخل نفس المعاملة |
| `audit_logs` | action, entity_type, entity_id, payload_json | إضافة فقط |
| `sync_outbox` | entity_type, entity_id, op, payload_json, attempts, last_error, synced_at | Claude 5 (للمرحلة 4+) |
| `sync_state` | key PK, value | Claude 5 |
| `backup_log` | kind ('local'/'cloud'), file_name, size_bytes, status, created_at | Claude 5 |

`doc_type`: `sales_invoice, sales_return, purchase_invoice, purchase_return, customer_receipt, supplier_payment, expense, stock_adjustment, journal_entry`.

## 3. المنتجات والمخزون (Claude 2) — `tables/inventory/`
| الجدول | الأعمدة الخاصة | ملاحظات |
|---|---|---|
| `categories` | name, parent_id, sort_order | Master |
| `units` | name, symbol, allows_fraction (0/1) | Master؛ مبذورة: حبة، كغ، غرام، لتر… |
| `products` | sku, name, category_id, unit_id, sale_price_minor, min_stock_milli, is_active | Master؛ UNIQUE(store_id, sku) |
| `product_barcodes` | product_id, barcode | UNIQUE(store_id, barcode) |
| `inventory_movements` | product_id, movement_type, quantity_delta_milli (موقّعة، ≠0), value_delta_minor (موقّعة), source_type, source_id, source_line_id, occurred_at, note | **إضافة فقط** |
| `stock_levels` | product_id PK, on_hand_milli (≥0), inventory_value_minor (≥0) | مشتق، يُحدَّث في نفس المعاملة |
| `stock_adjustments` | number UNIQUE, reason, status (draft/approved), approved_at | المعتمد غير قابل للتعديل |
| `stock_adjustment_items` | adjustment_id, product_id, counted_milli, system_milli, difference_milli | |

`movement_type`: `opening, purchase, sale, sale_return, purchase_return, adjustment, cancel_reversal`.
**المتوسط المرجح:** `avg_cost = inventory_value_minor / on_hand_milli` (يُحسب للعرض فقط).
قواعد: دخول: `value += تكلفة الدخول`. خروج: `cogs = round(value × qty_out / on_hand)`، وإن كان `qty_out = on_hand` فـ `cogs = value` (لا بقايا). إن لم يوجد رصيد كافٍ والمخزون السالب ممنوع → `InsufficientStockException`.

## 4. المبيعات والعملاء (Claude 3) — `tables/sales/`
| الجدول | الأعمدة الخاصة | ملاحظات |
|---|---|---|
| `customers` | name, phone, address, credit_limit_minor (0 = بلا حد), is_active | Master |
| `sales_invoices` | number UNIQUE, customer_id?, status (draft/approved/cancelled), issued_at, subtotal_minor, discount_minor, total_minor, initial_paid_minor, note, cancelled_at, cancel_reason | البيع الآجل = `initial_paid_minor < total_minor` ويتطلب `customer_id` |
| `sales_invoice_items` | invoice_id, product_id, product_name_snapshot, quantity_milli (>0), unit_price_minor, discount_minor, line_total_minor, cogs_minor | `cogs_minor` تكلفة السطر المحفوظة وقت البيع |
| `sales_payments` | invoice_id, payment_method_id, amount_minor (>0), paid_at | الدفعة عند البيع فقط |
| `sales_returns` | number UNIQUE, original_invoice_id, status, issued_at, refund_minor, refund_mode ('cash'/'account'), note | |
| `sales_return_items` | return_id, original_item_id, product_id, quantity_milli, line_refund_minor, cogs_reversed_minor | الكمية ≤ المتبقية القابلة للإرجاع |
| `customer_receipts` | number UNIQUE, customer_id, payment_method_id, amount_minor, received_at, status, note | تحصيل ديون |
| `customer_receipt_allocations` | receipt_id, invoice_id, amount_minor | غير المخصَّص يبقى رصيداً دائناً للعميل |

المتبقي على الفاتورة = `total − initial_paid − Σ التوزيعات − Σ مرتجعات الحساب`. **لا تُعدَّل الفاتورة المعتمدة.**

## 5. المشتريات والموردون والمحاسبة (Claude 4) — `tables/finance/`
| الجدول | الأعمدة الخاصة | ملاحظات |
|---|---|---|
| `suppliers` | name, phone, address, is_active | Master |
| `purchase_invoices` | number UNIQUE, supplier_id, supplier_ref, status, issued_at, total_minor, initial_paid_minor, note, cancelled_at, cancel_reason | آجل = `initial_paid < total` |
| `purchase_invoice_items` | invoice_id, product_id, quantity_milli, unit_cost_minor, line_total_minor | تكلفة الدخول = `line_total_minor` |
| `purchase_payments` | invoice_id, payment_method_id, amount_minor, paid_at | عند الشراء فقط |
| `purchase_returns` + `purchase_return_items` | مقابل الأصل، `return_cost_minor` تناسبي | |
| `supplier_payments` + `supplier_payment_allocations` | تماثل التحصيل | |
| `expense_categories` | name, account_id→accounts | |
| `expenses` | number UNIQUE, category_id, amount_minor, payment_method_id, spent_at, note, status | |
| `owner_transactions` | number, kind ('capital'/'drawing'), amount_minor, payment_method_id, occurred_at, note | |
| `accounts` | code UNIQUE, name, type (asset/liability/equity/revenue/expense), is_system | |
| `journal_entries` | number UNIQUE, entry_date, source_type, source_id, status (posted/reversed), reverses_entry_id?, memo | **إضافة فقط** |
| `journal_entry_lines` | entry_id, line_no, account_id, debit_minor ≥0, credit_minor ≥0, party_type ('customer'/'supplier'/null), party_id? | **إضافة فقط**، CHECK(`debit_minor=0 OR credit_minor=0`) |

**دليل الحسابات المبذور (نظامي):**
`1100 الصندوق` • `1110 تحويلات ومحافظ` • `1200 ذمم العملاء` • `1300 المخزون` • `2100 ذمم الموردين` • `3100 رأس مال المالك` • `3200 مسحوبات المالك` • `3300 أرصدة افتتاحية` • `4100 المبيعات` • `4200 مردودات المبيعات` • `5100 تكلفة المبيعات` • `5200 فروقات الجرد` • `6100 إيجار` • `6200 رواتب` • `6300 كهرباء وماء واتصالات` • `6400 نقل` • `6900 مصروفات أخرى`.

**قوالب القيود:**
| العملية | مدين | دائن |
|---|---|---|
| بيع | الصندوق/التحويل (المدفوع) + ذمم العملاء (المتبقي) | المبيعات (الإجمالي) |
| تكلفة البيع | تكلفة المبيعات (Σcogs) | المخزون |
| مرتجع بيع | مردودات المبيعات (المبلغ) | الصندوق (نقدي) **أو** ذمم العملاء (على الحساب) |
| عكس تكلفة المرتجع | المخزون | تكلفة المبيعات |
| شراء | المخزون (الإجمالي) | الصندوق (المدفوع) + ذمم الموردين (المتبقي) |
| مرتجع شراء | ذمم الموردين أو الصندوق | المخزون |
| تحصيل عميل | الصندوق/التحويل | ذمم العملاء |
| دفع مورد | ذمم الموردين | الصندوق/التحويل |
| مصروف | حساب المصروف | الصندوق/التحويل |
| رأس مال / مسحوبات | الصندوق / مسحوبات المالك | رأس المال / الصندوق |
| تسوية جرد (نقص) | فروقات الجرد | المخزون (والعكس للزيادة) |
| افتتاحي | المخزون، الصندوق، ذمم العملاء | ذمم الموردين، أرصدة افتتاحية |
| إلغاء/عكس | عكس كامل لسطور القيد الأصلي في قيد جديد `reverses_entry_id` | |

## 6. القيود (CHECK) والـ Triggers
- CHECK: المبالغ ≥ 0؛ `quantity_milli > 0` في البنود؛ `on_hand_milli ≥ 0` و`inventory_value_minor ≥ 0`؛ `debit_minor = 0 OR credit_minor = 0`؛ الحالات ضمن المسموح.
- **TR-1** منع `UPDATE`/`DELETE` على `inventory_movements`, `journal_entries`, `journal_entry_lines`, `audit_logs`.
- **TR-2** منع `UPDATE`/`DELETE` على الفواتير وبنودها ودفعاتها والمرتجعات والسندات والمصروفات إذا كانت الحالة ≠ `draft`، **باستثناء** انتقال `approved → cancelled` (تحديث `status, cancelled_at, cancel_reason` فقط).
- **TR-3** منع `INSERT` في بنود/دفعات مستند حالته ≠ `draft`.
- **TR-4** (اختياري، يقرره Claude 1 في المرحلة 0): عند ترحيل قيد، مجموع المدين = مجموع الدائن.
- لا `ON DELETE CASCADE` على جداول المستندات.

## 7. الفهارس
`product_barcodes(store_id, barcode)` • `products(store_id, name)` • `products(store_id, sku)` • `inventory_movements(product_id, occurred_at)` • `inventory_movements(source_type, source_id)` • `sales_invoices(store_id, number)` • `sales_invoices(issued_at)` • `sales_invoices(customer_id, status)` • `sales_invoice_items(invoice_id)` • `purchase_invoices(supplier_id, status)` • `customer_receipt_allocations(invoice_id)` • `journal_entries(entry_date)` • `journal_entries(source_type, source_id)` • `journal_entry_lines(account_id)` • `journal_entry_lines(party_type, party_id)`.

## 8. الترحيل والاختبار
- كل تغيير: رفع `schemaVersion` + دالة ترحيل في `core/database/migrations/` + لقطة في `drift_schemas/` + اختبار ترحيل (`drift_dev schema` + `SchemaVerifier`).
- ترحيل لا يفقد بيانات. لا تعديل لترحيل نُشر.
- البذور (حسابات، وحدات، طرق دفع، تسلسلات) تُنفَّذ في الترحيل الأول بشكل idempotent.

## 9. مصفوفة الملكية
| المجلد | المالك الوحيد للتعديل بعد موافقة Claude 1 |
|---|---|
| `tables/infra/` | Claude 5 (النواة تبقى لـ Claude 1) |
| `tables/inventory/` | Claude 2 |
| `tables/sales/` | Claude 3 |
| `tables/finance/` | Claude 4 |
