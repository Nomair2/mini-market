#!/usr/bin/env bash
# يفشل إذا وُجد double/REAL في الكود المالي أو الكمّي.
# الاستثناء الوحيد: سطر ينتهي بـ  // allow-double: <سبب>  (يُراجَع في الـ PR).
set -u
cd "$(dirname "$0")/.."
fail=0

# 1) أعمدة REAL ممنوعة في تعريف الجداول
if [ -d lib/core/database/tables ]; then
  hits=$(grep -rnE "RealColumn|real\(\)" lib/core/database/tables --include=*.dart || true)
  if [ -n "$hits" ]; then echo "ممنوع: RealColumn في الجداول:"; echo "$hits"; fail=1; fi
fi

# 2) double ممنوع خارج طبقة العرض (presentation) و shared_ui
paths=$(find lib -type f -name '*.dart' \
  -not -path 'lib/shared_ui/*' -not -path '*/presentation/*' -not -name '*.g.dart' 2>/dev/null || true)
for f in $paths; do
  hits=$(grep -nE "\bdouble\b|\.toDouble\(\)|double\.parse|double\.tryParse" "$f" | grep -v "allow-double:" || true)
  if [ -n "$hits" ]; then echo "ممنوع: double في $f"; echo "$hits"; fail=1; fi
done

# 3) SQL خام يحتوي REAL/FLOAT/DOUBLE
if [ -d lib/core/database ]; then
  hits=$(grep -rniE "\b(REAL|FLOAT|DOUBLE)\b" lib/core/database --include=*.dart --include=*.sql | grep -v "allow-double:" | grep -vE "RealColumn" || true)
  if [ -n "$hits" ]; then echo "ممنوع: نوع عشري في SQL:"; echo "$hits"; fail=1; fi
fi

if [ $fail -eq 0 ]; then echo "check_no_float: OK"; fi
exit $fail
