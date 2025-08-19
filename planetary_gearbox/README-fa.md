# گیربکس سیاره‌ای پارامتریک (OpenSCAD)

این نمونه یک گیربکس سیاره‌ای ساده و «قابل چاپ سه‌بعدی» است. هندسه دندانه‌ها ساده‌سازی شده (اینولوت دقیق نیست) اما برای نمونه‌های آموزشی و اسباب‌بازی‌ها مناسب است.

## فایل‌ها
- `planetary_gearbox.scad`: مونتاژ و انتخاب قطعه برای خروجی STL
- `gears.scad`: توابع تولید چرخ‌دنده خارجی و رینگی (داخلی) به‌صورت ساده

## پارامترهای پیش‌فرض
- ماژول (`m`): 1.6
- دنده خورشیدی (`z_sun`): 12
- دنده سیاره‌ای (`z_planet`): 18
- دنده رینگی (`z_ring = z_sun + 2*z_planet`): 48
- تعداد سیاره‌ها: 3
- ضخامت دنده‌ها: 8 میلی‌متر

می‌توانید این مقادیر را در ابتدای فایل `planetary_gearbox.scad` تغییر دهید.

## خروجی گرفتن (STL)
با نصب OpenSCAD می‌توانید هر قطعه را جداگانه خروجی بگیرید. مثال‌ها:

```bash
# رندر مونتاژ صرفاً برای پیش‌نمایش
openscad -o assembly_preview.stl -D 'part="assembly"' /workspace/planetary_gearbox/planetary_gearbox.scad

# چرخ‌دنده خورشیدی
openscad -o sun.stl -D 'part="sun"' /workspace/planetary_gearbox/planetary_gearbox.scad

# چرخ‌دنده سیاره‌ای
openscad -o planet.stl -D 'part="planet"' /workspace/planetary_gearbox/planetary_gearbox.scad

# چرخ‌دنده رینگی
openscad -o ring.stl -D 'part="ring"' /workspace/planetary_gearbox/planetary_gearbox.scad

# صفحه‌ی نگه‌دارنده پایین/بالا
openscad -o carrier_bottom.stl -D 'part="carrier_bottom"' /workspace/planetary_gearbox/planetary_gearbox.scad
openscad -o carrier_top.stl    -D 'part="carrier_top"'    /workspace/planetary_gearbox/planetary_gearbox.scad
```

اگر OpenSCAD GUI دارید، فایل `planetary_gearbox.scad` را باز کنید و مقدار `part` را روی قطعه‌ی مدنظر بگذارید و سپس Export STL بگیرید.

## نکات چاپ سه‌بعدی (FDM)
- **نازل 0.4 / لایه 0.2**: کیفیت مناسب/زمان معقول
- **دیوارها**: 3–4 پیرامید برای رینگی، 2–3 برای دنده‌ها
- **پرکنندگی**: 30–60٪ برای رینگی و صفحات؛ 20–40٪ برای دنده‌ها
- **کلیرنس XY** (`clearance_xy`): پیش‌فرض 0.25 میلی‌متر؛ اگر لق یا سفت بود، کمی کم/زیاد کنید
- **جهت قرارگیری**: دنده‌ها را خوابانده چاپ کنید؛ رینگی به صورت لیوانی رو به بالا
- **جنس**: PLA/PLA+ برای آموزش؛ PETG/ABS برای دوام بیشتر

## سرهم‌بندی
1. رینگی را کف میز بگذارید.
2. صفحه‌ی پایین (`carrier_bottom`) را داخل لبه‌ی رینگی قرار دهید.
3. دنده خورشیدی را وسط بگذارید (سوراخ مرکزی برای شفت).
4. دنده‌های سیاره‌ای را با پین‌های 5 میلی‌متری روی شعاع مشخص نصب کنید.
5. صفحه‌ی بالا را بگذارید و با پیچ‌های M3 روی دایره‌ی پیچ، محکم کنید.

> این مدل برای بارهای سبک طراحی شده است. برای انتقال قدرت واقعی، از دندانه‌های اینولوت دقیق و یاتاقان/بوش مناسب استفاده کنید.

## شخصی‌سازی سریع
- نسبت تبدیل: `z_ring - z_sun : z_sun` (برای این تنظیم ≈ 3:1)
- تنظیم خلاصی: `tooth_fraction` را روی 0.40–0.48 و `backlash_angle_extra` را 0–1.0 درجه تغییر دهید.