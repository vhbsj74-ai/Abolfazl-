<?php
/*
ربات فروش VPN - نسخه بهبود یافته و ایمن
- کیبوردهای اینلاین صحیح با callback_data
- خواندن تنظیمات حساس از متغیرهای محیطی
- بهبود جریان خرید و پرداخت/رسید
- مدیریت فایل‌ها و JSON با قفل فایل
- آمار و گزارش‌گیری دقیق‌تر
*/

// ===============================
// تنظیمات کلی
// ===============================

error_reporting(E_ALL & ~E_NOTICE);
ini_set('display_errors', '0');
ini_set('log_errors', '1');
date_default_timezone_set('Asia/Tehran');

// ===============================
// ابزارهای کمکی
// ===============================

function envValue(string $key, $default = null) {
    $value = getenv($key);
    return ($value === false || $value === null || $value === '') ? $default : $value;
}

function ensureDir(string $path): void {
    if (!is_dir($path)) {
        mkdir($path, 0755, true);
    }
}

function json_read(string $path, $assoc = true) {
    if (!file_exists($path)) return $assoc ? [] : (object)[];
    $content = file_get_contents($path);
    if ($content === '' || $content === false) return $assoc ? [] : (object)[];
    $data = json_decode($content, $assoc);
    if ($data === null && json_last_error() !== JSON_ERROR_NONE) return $assoc ? [] : (object)[];
    return $data;
}

function json_write(string $path, $data): bool {
    $tmp = $path . '.tmp';
    $json = json_encode($data, JSON_UNESCAPED_UNICODE | JSON_PRETTY_PRINT);
    $fp = fopen($tmp, 'c+');
    if ($fp === false) return false;
    try {
        if (!flock($fp, LOCK_EX)) { fclose($fp); return false; }
        ftruncate($fp, 0);
        fwrite($fp, $json);
        fflush($fp);
        flock($fp, LOCK_UN);
        fclose($fp);
        if (!@rename($tmp, $path)) {
            // Windows fallback
            @unlink($path);
            @rename($tmp, $path);
        }
        return true;
    } finally {
        if (is_resource($fp)) fclose($fp);
        @unlink($tmp);
    }
}

function log_event(string $event, $user_id = null): void {
    $line = date('Y-m-d H:i:s') . ' | User: ' . ($user_id ?: '-') . ' | ' . $event . "\n";
    ensureDir(__DIR__ . '/data/logs');
    file_put_contents(__DIR__ . '/data/logs/events.log', $line, FILE_APPEND);
}

function sanitize_gift_code(string $code): ?string {
    return preg_match('/^[A-Za-z0-9_-]{3,64}$/u', $code) ? $code : null;
}

// ===============================
// مسیرها و دایرکتوری‌ها
// ===============================

define('DATA_DIR', __DIR__ . '/data');
ensureDir(DATA_DIR);
ensureDir(DATA_DIR . '/user');
ensureDir(DATA_DIR . '/vpn');
ensureDir(DATA_DIR . '/vpn/v2ray');
ensureDir(DATA_DIR . '/vpn/iran');
ensureDir(DATA_DIR . '/products');
ensureDir(DATA_DIR . '/logs');
ensureDir(DATA_DIR . '/backup');
ensureDir(DATA_DIR . '/code');
ensureDir(DATA_DIR . '/deposits');

// فایل‌های پایه محصولات
$categoriesPath = DATA_DIR . '/products/categories.json';
$itemsPath      = DATA_DIR . '/products/items.json';
if (!file_exists($categoriesPath)) json_write($categoriesPath, []);
if (!file_exists($itemsPath))      json_write($itemsPath, []);

// فایل‌های پایه عمومی
$cartPath = DATA_DIR . '/cart';
$helpPath = DATA_DIR . '/helpcont';
$exPath   = DATA_DIR . '/ex';
$v2Path   = DATA_DIR . '/v2ray';
if (!file_exists($cartPath)) file_put_contents($cartPath, '6037-XXXX-XXXX-XXXX');
if (!file_exists($helpPath)) file_put_contents($helpPath, "📚 راهنمای اتصال:\n\n1. اپلیکیشن V2Ray را نصب کنید\n2. کانفیگ را کپی کنید\n3. در اپ اضافه کنید\n4. متصل شوید!");
if (!file_exists($exPath))   file_put_contents($exPath, '50000');
if (!file_exists($v2Path))   file_put_contents($v2Path, '60000');

// ===============================
// پیکربندی حساس از محیط
// ===============================

$TOKEN   = envValue('BOT_TOKEN');
$ADMIN   = (int) envValue('ADMIN_ID', 0);
$PAY_URL = envValue('PAY_URL', 'https://yourdomain.com');
$SPONSOR = envValue('SPONSOR_CHANNEL', 'SOLO_Confiig');

if (!$TOKEN) {
    http_response_code(500);
    echo 'BOT_TOKEN is not set';
    exit;
}

// ===============================
// توابع تلگرام
// ===============================

function tg_request(string $method, array $params = []) {
    global $TOKEN;
    $url = "https://api.telegram.org/bot{$TOKEN}/{$method}";
    $ch = curl_init();
    curl_setopt_array($ch, [
        CURLOPT_URL => $url,
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_POSTFIELDS => $params,
        CURLOPT_SSL_VERIFYPEER => false,
        CURLOPT_TIMEOUT => 15,
    ]);
    $res = curl_exec($ch);
    $err = curl_error($ch);
    curl_close($ch);
    if ($err) {
        log_event('cURL error: ' . $err);
        return null;
    }
    return json_decode($res, true);
}

function tg_sendMessage($chat_id, string $text, $reply_markup = null) {
    $params = [
        'chat_id' => $chat_id,
        'text' => $text,
        'parse_mode' => 'HTML',
        'disable_web_page_preview' => true,
    ];
    if ($reply_markup) $params['reply_markup'] = $reply_markup;
    return tg_request('sendMessage', $params);
}

function tg_editMessage($chat_id, $message_id, string $text, $reply_markup = null) {
    $params = [
        'chat_id' => $chat_id,
        'message_id' => $message_id,
        'text' => $text,
        'parse_mode' => 'HTML',
        'disable_web_page_preview' => true,
    ];
    if ($reply_markup) $params['reply_markup'] = $reply_markup;
    return tg_request('editMessageText', $params);
}

function tg_answerCallback($callback_id, string $text = '', bool $show_alert = false) {
    return tg_request('answerCallbackQuery', [
        'callback_query_id' => $callback_id,
        'text' => $text,
        'show_alert' => $show_alert,
    ]);
}

function make_reply_kb(array $rows): string {
    return json_encode(['keyboard' => $rows, 'resize_keyboard' => true]);
}

function make_inline_kb(array $rows): string {
    return json_encode(['inline_keyboard' => $rows], JSON_UNESCAPED_UNICODE);
}

// ===============================
// دسترسی به اطلاعات کاربر
// ===============================

function user_dir($user_id): string {
    $dir = DATA_DIR . '/user/' . $user_id;
    ensureDir($dir);
    ensureDir($dir . '/vpn');
    ensureDir($dir . '/vpn/v2ray');
    ensureDir($dir . '/vpn/iran');
    ensureDir($dir . '/purchases');
    if (!file_exists($dir . '/coin.txt')) file_put_contents($dir . '/coin.txt', '0');
    if (!file_exists($dir . '/step.txt')) file_put_contents($dir . '/step.txt', 'none');
    return $dir;
}

function user_get_step($user_id): string {
    $path = user_dir($user_id) . '/step.txt';
    return trim(@file_get_contents($path)) ?: 'none';
}

function user_set_step($user_id, string $step): void {
    $path = user_dir($user_id) . '/step.txt';
    file_put_contents($path, $step);
}

function user_get_coin($user_id): int {
    $path = user_dir($user_id) . '/coin.txt';
    return (int) trim(@file_get_contents($path));
}

function user_set_coin($user_id, int $amount): void {
    $path = user_dir($user_id) . '/coin.txt';
    file_put_contents($path, (string) max(0, $amount));
}

// ===============================
// کلاس مدیریت محصولات
// ===============================

class ProductManager {
    public static function categoriesPath(): string { global $categoriesPath; return $categoriesPath; }
    public static function itemsPath(): string { global $itemsPath; return $itemsPath; }

    public static function addCategory(string $name, string $icon = '📦'): string {
        $categories = json_read(self::categoriesPath(), true) ?: [];
        $id = uniqid('cat_', true);
        $categories[$id] = [
            'id' => $id,
            'name' => $name,
            'icon' => $icon,
            'created_at' => time(),
        ];
        json_write(self::categoriesPath(), $categories);
        return $id;
    }

    public static function deleteCategory(string $id): void {
        $categories = json_read(self::categoriesPath(), true) ?: [];
        unset($categories[$id]);
        json_write(self::categoriesPath(), $categories);
        $items = json_read(self::itemsPath(), true) ?: [];
        foreach ($items as $key => $item) if (($item['category_id'] ?? '') === $id) unset($items[$key]);
        json_write(self::itemsPath(), $items);
    }

    public static function addProduct(array $data): string {
        $items = json_read(self::itemsPath(), true) ?: [];
        $id = uniqid('prd_', true);
        $items[$id] = [
            'id' => $id,
            'category_id' => $data['category_id'],
            'name' => trim($data['name']),
            'description' => trim($data['description']),
            'price' => (int) $data['price'],
            'volume' => trim($data['volume']),
            'duration' => trim($data['duration']),
            'operator' => trim($data['operator']),
            'config_type' => trim($data['config_type']),
            'stock' => (int) $data['stock'],
            'status' => 'active',
            'created_at' => time(),
        ];
        json_write(self::itemsPath(), $items);
        return $id;
    }

    public static function updateProduct(string $id, array $data): bool {
        $items = json_read(self::itemsPath(), true) ?: [];
        if (!isset($items[$id])) return false;
        $items[$id] = array_merge($items[$id], $data);
        json_write(self::itemsPath(), $items);
        return true;
    }

    public static function deleteProduct(string $id): void {
        $items = json_read(self::itemsPath(), true) ?: [];
        unset($items[$id]);
        json_write(self::itemsPath(), $items);
    }

    public static function getCategoryProducts(string $category_id): array {
        $items = json_read(self::itemsPath(), true) ?: [];
        $result = [];
        foreach ($items as $item) {
            if (($item['category_id'] ?? '') === $category_id && ($item['status'] ?? '') === 'active') $result[] = $item;
        }
        return array_values($result);
    }

    public static function getAllCategories(): array {
        return json_read(self::categoriesPath(), true) ?: [];
    }

    public static function getProduct(string $id): ?array {
        $items = json_read(self::itemsPath(), true) ?: [];
        return $items[$id] ?? null;
    }
}

// ===============================
// تولید کانفیگ
// ===============================

function generateConfig(array $product): string {
    $operator = $product['operator'] ?? '';
    $opNorm = mb_strtolower($operator, 'UTF-8');
    $isIrancell = (strpos($opNorm, 'ایرانسل') !== false) || (strpos($opNorm, 'irancell') !== false) || (strpos($operator, '🎖 ایرانسل') !== false);
    $configDir = DATA_DIR . '/vpn/' . ($isIrancell ? 'iran' : 'v2ray');

    if (is_dir($configDir)) {
        $files = array_values(array_diff(scandir($configDir), ['.', '..']));
        if (!empty($files)) {
            $rand = $files[array_rand($files)];
            $content = @file_get_contents($configDir . '/' . $rand);
            if ($content) {
                @unlink($configDir . '/' . $rand); // مصرف شد
                return trim($content);
            }
        }
    }

    // fallback نمونه
    $samples = [
        'v2ray://eyJ2IjoiMiIsInBzIjoiVGVzdCBDb25maWciLCJhZGQiOiJleGFtcGxlLmNvbSIsInBvcnQiOiI0NDMiLCJpZCI6IjExMTExMTExLTExMTEtMTExMS0xMTExLTExMTExMTExMTExMSIsImFpZCI6IjAiLCJuZXQiOiJ0Y3AiLCJ0eXBlIjoibm9uZSIsImhvc3QiOiIiLCJwYXRoIjoiL3NzIiwidGxzIjoidGxzIn0=',
        'v2ray://eyJ2IjoiMiIsInBzIjoiVlBOIFNlcnZpY2UiLCJhZGQiOiJzZXJ2ZXIuY29tIiwicG9ydCI6IjgwODAiLCJpZCI6IjIyMjIyMjIyLTIyMjItMjIyMi0yMjIyLTIyMjIyMjIyMjIyMiIsImFpZCI6IjAiLCJuZXQiOiJ3cyIsInR5cGUiOiJub25lIiwiaG9zdCI6IiIsInBhdGgiOiIvd3MiLCJ0bHMiOiJ0bHMifQ=='
    ];
    return $samples[array_rand($samples)];
}

// ===============================
// کیبوردها
// ===============================

$o  = '🔘 بازگشت';
$oo = '🔘 برگشت';

$keyMain = make_reply_kb([
    [['text' => '🛒 خرید سرویس']],
    [['text' => '💫 اطلاعات کاربری'], ['text' => '🎰 گردونه شانس'], ['text' => '⚜ وضعیت سرویس ها']],
    [['text' => '💡 آموزش اتصال'], ['text' => '🪫 کد هدیه'], ['text' => '➕ افزایش موجودی']],
]);

$keyAdmin = make_reply_kb([
    [['text' => '📊 داشبورد مدیریت'], ['text' => '👥 مدیریت کاربران']],
    [['text' => '📦 مدیریت محصولات'], ['text' => '📢 ارسال پیام انبوه']],
    [['text' => '💳 مدیریت مالی'], ['text' => '📈 گزارش‌گیری']],
    [['text' => '⚙ تنظیمات پویا'], ['text' => '💾 پشتیبان‌گیری']],
]);

$keyBack  = make_reply_kb([[['text' => $o]]]);
$keyBack2 = make_reply_kb([[['text' => $oo]]]);

// ===============================
// دریافت آپدیت
// ===============================

$input = file_get_contents('php://input');
$update = json_decode($input, true);
if (!$update) { exit; }

$text = '';
$chat_id = '';
$from_id = '';
$first_name = 'کاربر';
$message_id = '';
$data = '';
$callback_query = null;

if (isset($update['message'])) {
    $message = $update['message'];
    $text = $message['text'] ?? '';
    $chat_id = $message['chat']['id'] ?? '';
    $from_id = $message['from']['id'] ?? '';
    $first_name = $message['from']['first_name'] ?? 'کاربر';
    $message_id = $message['message_id'] ?? '';
}

if (isset($update['callback_query'])) {
    $callback_query = $update['callback_query'];
    $data = $callback_query['data'] ?? '';
    $chat_id = $callback_query['message']['chat']['id'] ?? '';
    $from_id = $callback_query['from']['id'] ?? '';
    $message_id = $callback_query['message']['message_id'] ?? '';
    $first_name = $callback_query['from']['first_name'] ?? 'کاربر';
}

// خواندن مقادیر ثابت
$cart    = trim(@file_get_contents($cartPath));
$helpTxt = trim(@file_get_contents($helpPath));
$exPrice = (int) trim(@file_get_contents($exPath));
$v2Price = (int) trim(@file_get_contents($v2Path));

// اطمینان از ساخت دایرکتوری کاربر وقتی نیاز شد
if ($from_id) user_dir($from_id);

// ===============================
// توابع نمایشی دسته و محصول (اینلاین)
// ===============================

function show_categories($chat_id, $editMessageId = null) {
    $categories = ProductManager::getAllCategories();
    if (empty($categories)) {
        // ایجاد نمونه اولیه
        ProductManager::addCategory('ایرانسل', '🎖');
        ProductManager::addCategory('همراه اول', '🎖');
        $categories = ProductManager::getAllCategories();
    }
    $rows = [];
    foreach ($categories as $cat) {
        $rows[] = [[ 'text' => ($cat['icon'] ?? '📦') . ' ' . $cat['name'], 'callback_data' => 'cat:' . $cat['id'] ]];
    }
    $rows[] = [[ 'text' => '🔄 تازه‌سازی', 'callback_data' => 'cats:refresh' ]];
    $kb = make_inline_kb($rows);
    $text = "🎯 <b>انتخاب دسته محصول</b>\n\nلطفاً دسته موردنظر را انتخاب کنید:";
    if ($editMessageId) return tg_editMessage($chat_id, $editMessageId, $text, $kb);
    return tg_sendMessage($chat_id, $text, $kb);
}

function show_products($chat_id, string $category_id, $editMessageId = null) {
    $categories = ProductManager::getAllCategories();
    $category = $categories[$category_id] ?? null;
    if (!$category) return tg_sendMessage($chat_id, '❌ دسته یافت نشد.');
    $products = ProductManager::getCategoryProducts($category_id);

    if (empty($products)) {
        // ساخت نمونه محصول
        $catName = $category['name'];
        $defaultPrice = (strpos($catName, 'ایرانسل') !== false) ? (int) @file_get_contents(DATA_DIR . '/ex') : (int) @file_get_contents(DATA_DIR . '/v2ray');
        $sample = [
            'category_id' => $category_id,
            'name' => 'پکیج 1 گیگابایت',
            'description' => 'پکیج پرسرعت 1 گیگابایت',
            'price' => $defaultPrice ?: 50000,
            'volume' => '1 گیگابایت',
            'duration' => '30 روزه',
            'operator' => $catName,
            'config_type' => 'v2ray',
            'stock' => 10,
        ];
        ProductManager::addProduct($sample);
        $products = ProductManager::getCategoryProducts($category_id);
    }

    $rows = [];
    foreach ($products as $p) {
        $label = '🛒 ' . $p['name'] . ' | 💵 ' . number_format((int)$p['price']) . ' ریال';
        $rows[] = [[ 'text' => $label, 'callback_data' => 'prd:' . $p['id'] ]];
    }
    $rows[] = [[ 'text' => '🔙 بازگشت', 'callback_data' => 'back:cats' ]];
    $kb = make_inline_kb($rows);
    $text = '📦 <b>محصولات ' . htmlspecialchars($category['name']) . '</b>\n\nلطفاً محصول موردنظر را انتخاب کنید:';
    if ($editMessageId) return tg_editMessage($chat_id, $editMessageId, $text, $kb);
    return tg_sendMessage($chat_id, $text, $kb);
}

function show_product_details($chat_id, string $product_id, $editMessageId = null) {
    $p = ProductManager::getProduct($product_id);
    if (!$p) return tg_sendMessage($chat_id, '❌ محصول یافت نشد.');
    $text = '';
    $text .= '🎯 <b>' . htmlspecialchars($p['name']) . "</b>\n\n";
    $text .= '📝 <b>توضیحات:</b> ' . htmlspecialchars($p['description']) . "\n";
    $text .= '💳 <b>قیمت:</b> ' . number_format((int)$p['price']) . ' ریال' . "\n";
    $text .= '📊 <b>حجم:</b> ' . htmlspecialchars($p['volume']) . "\n";
    $text .= '⏰ <b>مدت زمان:</b> ' . htmlspecialchars($p['duration']) . "\n";
    $text .= '📡 <b>اپراتور:</b> ' . htmlspecialchars($p['operator']) . "\n";
    $text .= '🔧 <b>نوع کانفیگ:</b> ' . htmlspecialchars($p['config_type']) . "\n";
    $text .= '📦 <b>موجودی:</b> ' . (int)$p['stock'] . ' عدد';

    $rows = [
        [
            [ 'text' => '✅ خرید محصول', 'callback_data' => 'buy:' . $p['id'] ],
            [ 'text' => '📋 جزئیات بیشتر', 'callback_data' => 'more:' . $p['id'] ],
        ],
        [ [ 'text' => '🔙 بازگشت', 'callback_data' => 'back:cat:' . $p['category_id'] ] ],
    ];
    $kb = make_inline_kb($rows);

    if ($editMessageId) return tg_editMessage($chat_id, $editMessageId, $text, $kb);
    return tg_sendMessage($chat_id, $text, $kb);
}

// ===============================
// هندل پرداخت/شارژ
// ===============================

function create_deposit($user_id, int $amount, string $method = 'card'): string {
    $id = uniqid('dep_', true);
    $data = [
        'id' => $id,
        'user_id' => (string)$user_id,
        'amount' => $amount,
        'method' => $method,
        'status' => 'pending',
        'created_at' => time(),
        'note' => '',
    ];
    json_write(DATA_DIR . '/deposits/' . $id . '.json', $data);
    return $id;
}

function load_deposit(string $id): ?array {
    $p = DATA_DIR . '/deposits/' . $id . '.json';
    if (!file_exists($p)) return null;
    return json_read($p, true);
}

function save_deposit(array $deposit): void {
    json_write(DATA_DIR . '/deposits/' . $deposit['id'] . '.json', $deposit);
}

// ===============================
// جریان اصلی
// ===============================

$step = $from_id ? user_get_step($from_id) : 'none';
$coin = $from_id ? user_get_coin($from_id) : 0;

// شروع یا بازگشت
if ($text === '/start' || $text === $o) {
    tg_sendMessage($chat_id, '▪️ سلام ' . htmlspecialchars($first_name) . ' عزیز به ربات فروش وی پی ان ما خوش آمدی :', $keyMain);
    user_set_step($from_id, 'none');
    log_event('start', $from_id);
}
// منوی خرید: نمایش دسته‌ها (اینلاین)
elseif ($text === '🛒 خرید سرویس') {
    show_categories($chat_id);
    user_set_step($from_id, 'browsing');
}
// اطلاعات کاربری
elseif ($text === '💫 اطلاعات کاربری') {
    $v2Dir = user_dir($from_id) . '/vpn/v2ray';
    $irDir = user_dir($from_id) . '/vpn/iran';
    $v2Count = is_dir($v2Dir) ? max(0, count(array_diff(scandir($v2Dir), ['.', '..']))) : 0;
    $irCount = is_dir($irDir) ? max(0, count(array_diff(scandir($irDir), ['.', '..']))) : 0;
    $msg = "📌 <b>وضعیت کاربری شما</b>\n\n" .
           '🔢 شناسه: <code>' . $from_id . "</code>\n" .
           '💳 موجودی: <b>' . number_format($coin) . " ریال</b>\n" .
           '🔑 همراه اول: <b>' . $v2Count . "</b>\n" .
           '🎴 ایرانسل: <b>' . $irCount . '</b>';
    tg_sendMessage($chat_id, $msg, $keyMain);
}
// آموزش اتصال
elseif ($text === '💡 آموزش اتصال') {
    tg_sendMessage($chat_id, $helpTxt, $keyMain);
}
// وضعیت سرویس‌ها
elseif ($text === '⚜ وضعیت سرویس ها') {
    $tv2 = is_dir(DATA_DIR . '/vpn/v2ray') ? max(0, count(array_diff(scandir(DATA_DIR . '/vpn/v2ray'), ['.', '..']))) : 0;
    $tir = is_dir(DATA_DIR . '/vpn/iran')  ? max(0, count(array_diff(scandir(DATA_DIR . '/vpn/iran'),  ['.', '..']))) : 0;
    $kb = make_inline_kb([
        [ ['text' => 'تعداد سرویس', 'callback_data' => 'noop'], ['text' => 'قیمت(ریال)', 'callback_data' => 'noop'], ['text' => 'نام سرویس', 'callback_data' => 'noop'] ],
        [ ['text' => (string)$tir, 'callback_data' => 'noop'], ['text' => (string)$exPrice, 'callback_data' => 'noop'], ['text' => '🎖 ایرانسل', 'callback_data' => 'noop'] ],
        [ ['text' => (string)$tv2, 'callback_data' => 'noop'], ['text' => (string)$v2Price, 'callback_data' => 'noop'], ['text' => '🎖 همراه اول', 'callback_data' => 'noop'] ],
    ]);
    tg_sendMessage($chat_id, '🎴 <b>وضعیت سرویس‌های وی پی ان</b>', $kb);
}
// کد هدیه
elseif ($text === '🪫 کد هدیه') {
    tg_sendMessage($chat_id, '👈 کد هدیه را وارد کنید:', $keyBack);
    user_set_step($from_id, 'gift_code');
}
// گردونه شانس
elseif ($text === '🎰 گردونه شانس') {
    $datech = trim(@file_get_contents(user_dir($from_id) . '/datesh'));
    $today = date('Y-m-d');
    if ($datech === $today) {
        tg_sendMessage($chat_id, '⏳ شما امروز قبلا از گردونه استفاده کرده‌اید.', $keyBack);
    } else {
        $rand = rand(1,4);
        $messages = [
            1 => ['😁 پنجاه هزار ریال واریز شد!',  50000],
            2 => ['😥 پنجاه هزار ریال کسر شد!', -50000],
            3 => ['🎉 صد هزار ریال واریز شد!',  100000],
            4 => ['😑 شانس شما پوچ شد!', 0],
        ];
        [$msg, $delta] = $messages[$rand];
        $newCoin = max(0, $coin + $delta);
        user_set_coin($from_id, $newCoin);
        file_put_contents(user_dir($from_id) . '/datesh', $today);
        tg_sendMessage($chat_id, $msg, $keyBack);
        log_event('spin:' . $delta, $from_id);
    }
}
// افزایش موجودی
elseif ($text === '➕ افزایش موجودی') {
    $a = rand(1, 9); $b = rand(1, 9); $sum = $a + $b;
    file_put_contents(user_dir($from_id) . '/captcha.txt', (string)$sum);
    tg_sendMessage($chat_id, "♻️ لطفا حاصل جمع زیر را وارد کنید:\n<code>{$a} + {$b} = ?</code>", $keyBack);
    user_set_step($from_id, 'topup_captcha');
}

// ===============================
// پنل مدیریت (بخش‌های اصلی نگه داشته شده)
// ===============================
elseif ($from_id == $ADMIN) {
    if ($text === '/panel' || $text === $oo || $text === 'پنل') {
        tg_sendMessage($chat_id, '👑 <b>پنل مدیریت حرفه‌ای</b>', $keyAdmin);
    }
    elseif ($text === '📦 مدیریت محصولات') {
        $kb = make_reply_kb([
            [['text' => '➕ افزودن دسته'], ['text' => '📥 افزودن محصول']],
            [['text' => '✏️ ویرایش محصول'], ['text' => '🗑️ حذف محصول']],
            [['text' => '📋 لیست محصولات'], ['text' => '📊 آمار محصولات']],
            [['text' => $oo]],
        ]);
        tg_sendMessage($chat_id, '📦 <b>پنل مدیریت محصولات</b>', $kb);
    }
    elseif ($text === '➕ افزودن دسته') {
        tg_sendMessage($chat_id, "📁 <b>افزودن دسته جدید</b>\n\nلطفاً نام دسته را وارد کنید:", $keyBack2);
        user_set_step($from_id, 'add_category_name');
    }
    elseif ($step === 'add_category_name' && $text !== $oo) {
        file_put_contents(user_dir($from_id) . '/temp_category_name.txt', $text);
        tg_sendMessage($chat_id, "🎨 <b>انتخاب آیکون برای دسته</b>\n\nیک آیکون انتخاب کنید (مثلاً: 📦, 🔑, 🌐):", $keyBack2);
        user_set_step($from_id, 'add_category_icon');
    }
    elseif ($step === 'add_category_icon' && $text !== $oo) {
        $name = trim(@file_get_contents(user_dir($from_id) . '/temp_category_name.txt'));
        $id = ProductManager::addCategory($name, $text);
        @unlink(user_dir($from_id) . '/temp_category_name.txt');
        tg_sendMessage($chat_id, '✅ <b>دسته با موفقیت ایجاد شد!</b>\n\n📁 نام: ' . htmlspecialchars($text . ' ' . $name), $keyAdmin);
        user_set_step($from_id, 'none');
        log_event('add_category:' . $id, $from_id);
    }
    elseif ($text === '📥 افزودن محصول') {
        $categories = ProductManager::getAllCategories();
        if (empty($categories)) { tg_sendMessage($chat_id, '❌ ابتدا باید یک دسته ایجاد کنید.', $keyAdmin); }
        else {
            $rows = [];
            foreach ($categories as $cat) $rows[] = [[ 'text' => ($cat['icon'] ?? '📦') . ' ' . $cat['name'] ]];
            $rows[] = [[ 'text' => $oo ]];
            tg_sendMessage($chat_id, "📥 <b>افزودن محصول جدید</b>\n\nلطفاً دسته محصول را انتخاب کنید:", make_reply_kb($rows));
            user_set_step($from_id, 'add_product_category');
        }
    }
    elseif ($step === 'add_product_category' && $text !== $oo) {
        $category_name = trim(mb_substr($text, 2));
        $categories = ProductManager::getAllCategories();
        $selected = null;
        foreach ($categories as $cat) if ($cat['name'] === $category_name) { $selected = $cat['id']; break; }
        if ($selected) {
            file_put_contents(user_dir($from_id) . '/temp_product_category.txt', $selected);
            tg_sendMessage($chat_id, '📝 <b>نام محصول</b>\n\nنام محصول را وارد کنید:', $keyBack2);
            user_set_step($from_id, 'add_product_name');
        }
    }
    elseif ($step === 'add_product_name' && $text !== $oo) {
        file_put_contents(user_dir($from_id) . '/temp_product_name.txt', $text);
        tg_sendMessage($chat_id, '📋 <b>توضیحات محصول</b>\n\nتوضیحات محصول را وارد کنید:', $keyBack2);
        user_set_step($from_id, 'add_product_description');
    }
    elseif ($step === 'add_product_description' && $text !== $oo) {
        file_put_contents(user_dir($from_id) . '/temp_product_description.txt', $text);
        tg_sendMessage($chat_id, '💵 <b>قیمت محصول (ریال)</b>\n\nقیمت را به ریال وارد کنید:', $keyBack2);
        user_set_step($from_id, 'add_product_price');
    }
    elseif ($step === 'add_product_price' && $text !== $oo) {
        if (!is_numeric($text)) { tg_sendMessage($chat_id, '❌ لطفاً فقط عدد وارد کنید!'); }
        else {
            file_put_contents(user_dir($from_id) . '/temp_product_price.txt', $text);
            tg_sendMessage($chat_id, '📊 <b>حجم محصول</b>\n\nمثال: 10 گیگابایت', $keyBack2);
            user_set_step($from_id, 'add_product_volume');
        }
    }
    elseif ($step === 'add_product_volume' && $text !== $oo) {
        file_put_contents(user_dir($from_id) . '/temp_product_volume.txt', $text);
        tg_sendMessage($chat_id, '⏰ <b>مدت زمان محصول</b>\n\nمثال: 30 روزه', $keyBack2);
        user_set_step($from_id, 'add_product_duration');
    }
    elseif ($step === 'add_product_duration' && $text !== $oo) {
        file_put_contents(user_dir($from_id) . '/temp_product_duration.txt', $text);
        $kb = make_reply_kb([
            [['text' => '🎖 ایرانسل'], ['text' => '🎖 همراه اول']],
            [['text' => '🌐 سایر اپراتورها']],
            [['text' => $oo]],
        ]);
        tg_sendMessage($chat_id, '📡 <b>اپراتور محصول</b>\n\nانتخاب کنید:', $kb);
        user_set_step($from_id, 'add_product_operator');
    }
    elseif ($step === 'add_product_operator' && $text !== $oo) {
        file_put_contents(user_dir($from_id) . '/temp_product_operator.txt', $text);
        $kb = make_reply_kb([
            [['text' => 'v2ray'], ['text' => 'openvpn']],
            [['text' => 'shadowsocks'], ['text' => 'wireguard']],
            [['text' => $oo]],
        ]);
        tg_sendMessage($chat_id, '🔧 <b>نوع کانفیگ</b>\n\nانتخاب کنید:', $kb);
        user_set_step($from_id, 'add_product_config_type');
    }
    elseif ($step === 'add_product_config_type' && $text !== $oo) {
        file_put_contents(user_dir($from_id) . '/temp_product_config_type.txt', $text);
        tg_sendMessage($chat_id, '📦 <b>موجودی محصول</b>\n\nتعداد موجودی را وارد کنید:', $keyBack2);
        user_set_step($from_id, 'add_product_stock');
    }
    elseif ($step === 'add_product_stock' && $text !== $oo) {
        if (!is_numeric($text)) { tg_sendMessage($chat_id, '❌ لطفاً فقط عدد وارد کنید!'); }
        else {
            $userDir = user_dir($from_id);
            $product_data = [
                'category_id' => trim(@file_get_contents($userDir . '/temp_product_category.txt')),
                'name' => trim(@file_get_contents($userDir . '/temp_product_name.txt')),
                'description' => trim(@file_get_contents($userDir . '/temp_product_description.txt')),
                'price' => (int) trim(@file_get_contents($userDir . '/temp_product_price.txt')),
                'volume' => trim(@file_get_contents($userDir . '/temp_product_volume.txt')),
                'duration' => trim(@file_get_contents($userDir . '/temp_product_duration.txt')),
                'operator' => trim(@file_get_contents($userDir . '/temp_product_operator.txt')),
                'config_type' => trim(@file_get_contents($userDir . '/temp_product_config_type.txt')),
                'stock' => (int) $text,
            ];
            $pid = ProductManager::addProduct($product_data);
            foreach ([
                '/temp_product_category.txt', '/temp_product_name.txt', '/temp_product_description.txt',
                '/temp_product_price.txt', '/temp_product_volume.txt', '/temp_product_duration.txt',
                '/temp_product_operator.txt', '/temp_product_config_type.txt',
            ] as $t) @unlink($userDir . $t);

            tg_sendMessage($chat_id,
                '✅ <b>محصول با موفقیت اضافه شد!</b>\n\n' .
                '🎯 نام: ' . htmlspecialchars($product_data['name']) . "\n" .
                '💵 قیمت: ' . number_format($product_data['price']) . " ریال\n" .
                '📊 حجم: ' . htmlspecialchars($product_data['volume']) . "\n" .
                '📦 موجودی: ' . $product_data['stock'],
                $keyAdmin
            );
            user_set_step($from_id, 'none');
            log_event('add_product:' . $pid, $from_id);
        }
    }
    elseif ($text === '📊 داشبورد مدیریت') {
        // شمارش دقیق
        $userDirs = glob(DATA_DIR . '/user/*', GLOB_ONLYDIR) ?: [];
        $users_count = count($userDirs);
        $active_today = 0;
        foreach ($userDirs as $ud) {
            $d = @file_get_contents($ud . '/datesh');
            if (trim($d) === date('Y-m-d')) $active_today++;
        }
        $total_vpn = 0;
        foreach (['/vpn/v2ray', '/vpn/iran'] as $sub) {
            $dir = DATA_DIR . $sub;
            if (is_dir($dir)) $total_vpn += count(array_diff(scandir($dir), ['.', '..']));
        }
        tg_sendMessage($chat_id,
            '📈 <b>داشبورد زنده</b>\n\n' .
            '👥 کاربران کل: ' . $users_count . "\n" .
            '🔥 فعال امروز: ' . $active_today . "\n" .
            '🛒 سرویس‌های موجود: ' . $total_vpn . "\n" .
            '💵 درآمد امروز: در حال محاسبه...'
        );
    }
}

// ===============================
// پردازش مراحل کاربری
// ===============================
elseif ($step === 'gift_code' && $text !== $o) {
    $code = sanitize_gift_code($text);
    if ($code && file_exists(DATA_DIR . '/code/' . $code)) {
        $amount = (int) @file_get_contents(DATA_DIR . '/code/' . $code);
        user_set_coin($from_id, $coin + $amount);
        @unlink(DATA_DIR . '/code/' . $code);
        tg_sendMessage($chat_id, '✅ کد هدیه اعمال شد! ' . number_format($amount) . ' ریال به حساب شما افزوده شد.', $keyMain);
    } else {
        tg_sendMessage($chat_id, '❌ کد هدیه نامعتبر است.', $keyBack);
    }
    user_set_step($from_id, 'none');
}
elseif ($step === 'topup_captcha' && $text !== $o) {
    $correct = trim(@file_get_contents(user_dir($from_id) . '/captcha.txt'));
    if ($text == $correct) {
        tg_sendMessage($chat_id, '✅ احراز هویت موفق\n\n💵 لطفاً مبلغ شارژ را به ریال وارد کنید (حداقل 10,000):', $keyBack);
        user_set_step($from_id, 'topup_amount');
    } else {
        tg_sendMessage($chat_id, '❌ پاسخ اشتباه است. دوباره تلاش کنید.', $keyBack);
    }
}
elseif ($step === 'topup_amount' && $text !== $o) {
    if (!is_numeric($text) || (int)$text < 10000) {
        tg_sendMessage($chat_id, '❌ مبلغ معتبر نیست. حداقل 10,000 ریال.', $keyBack);
    } else {
        $amount = (int) $text;
        $depId = create_deposit($from_id, $amount, 'card');
        $kb = make_inline_kb([
            [ ['text' => '📤 ارسال رسید', 'callback_data' => 'sendres:' . $depId] ],
            [ ['text' => '💳 پرداخت درگاه', 'url' => $GLOBALS['PAY_URL'] . '/pay?invoice=' . urlencode($depId) . '&user=' . urlencode((string)$from_id) . '&amount=' . $amount] ],
        ]);
        tg_sendMessage($chat_id,
            "✅ احراز هویت موفق\n\n💳 برای شارژ حساب، مبلغ را به کارت زیر واریز کنید:\n<code>{$GLOBALS['cart']}</code>\n\n" .
            'مبلغ: <b>' . number_format($amount) . " ریال</b>\n" .
            'سپس رسید را ارسال کنید یا از درگاه پرداخت کنید.',
            $kb
        );
        user_set_step($from_id, 'none');
    }
}
elseif ($step === 'await_receipt' && $text !== $o) {
    // متن رسید کاربر (برای یک سپرده مشخص)
    $depId = trim(@file_get_contents(user_dir($from_id) . '/pending_deposit.txt'));
    $dep = $depId ? load_deposit($depId) : null;
    if (!$dep) {
        tg_sendMessage($chat_id, '❌ تراکنش یافت نشد. از ابتدا تلاش کنید.', $keyMain);
        user_set_step($from_id, 'none');
    } else {
        $dep['note'] = 'USER_NOTE: ' . trim($text);
        $dep['status'] = 'awaiting_admin';
        save_deposit($dep);
        tg_sendMessage($chat_id, '✅ رسید ثبت شد. پس از تایید ادمین، حساب شما شارژ می‌گردد.', $keyMain);
        @unlink(user_dir($from_id) . '/pending_deposit.txt');
        user_set_step($from_id, 'none');

        // اطلاع به ادمین
        if ($GLOBALS['ADMIN']) {
            $kb = make_inline_kb([
                [
                    ['text' => '✅ تایید و شارژ', 'callback_data' => 'dep:approve:' . $dep['id']],
                    ['text' => '❌ رد کردن',    'callback_data' => 'dep:reject:' . $dep['id']],
                ]
            ]);
            tg_sendMessage($GLOBALS['ADMIN'],
                '📥 <b>درخواست شارژ</b>\n\n' .
                'کاربر: <code>' . $from_id . "</code>\n" .
                'مبلغ: <b>' . number_format($dep['amount']) . " ریال</b>\n" .
                'یادداشت: ' . htmlspecialchars($dep['note']),
                $kb
            );
        }
    }
}

// ===============================
// پردازش CallbackQuery ها
// ===============================
if ($callback_query) {
    $cid = $callback_query['id'];

    // ناسازگاری‌های قدیمی را هم پشتیبانی می‌کنیم
    if (strpos($data, 'view_product_') === 0) { $data = 'prd:' . substr($data, strlen('view_product_')); }
    if (strpos($data, 'buy_product_') === 0)  { $data = 'buy:' . substr($data, strlen('buy_product_')); }
    if (strpos($data, 'confirm_buy_') === 0) { $data = 'confirm:' . substr($data, strlen('confirm_buy_')); }

    // دسته‌ها
    if ($data === 'cats:refresh') {
        show_categories($chat_id, $message_id);
        tg_answerCallback($cid);
        exit;
    }
    if (strpos($data, 'cat:') === 0) {
        $catId = substr($data, 4);
        show_products($chat_id, $catId, $message_id);
        tg_answerCallback($cid);
        exit;
    }
    if (strpos($data, 'back:cat:') === 0) {
        $catId = substr($data, strlen('back:cat:'));
        show_products($chat_id, $catId, $message_id);
        tg_answerCallback($cid);
        exit;
    }
    if ($data === 'back:cats') {
        show_categories($chat_id, $message_id);
        tg_answerCallback($cid);
        exit;
    }

    // محصول
    if (strpos($data, 'prd:') === 0) {
        $pid = substr($data, 4);
        show_product_details($chat_id, $pid, $message_id);
        tg_answerCallback($cid);
        exit;
    }
    if (strpos($data, 'more:') === 0) {
        $pid = substr($data, 5);
        $p = ProductManager::getProduct($pid);
        if ($p) {
            $text = 'ℹ️ <b>جزئیات بیشتر</b>\n\n' . htmlspecialchars(print_r($p, true));
            tg_editMessage($chat_id, $message_id, $text, make_inline_kb([[['text' => '🔙 بازگشت', 'callback_data' => 'prd:' . $pid]]])) ;
        }
        tg_answerCallback($cid);
        exit;
    }

    // خرید
    if (strpos($data, 'buy:') === 0) {
        $pid = substr($data, 4);
        $p = ProductManager::getProduct($pid);
        if (!$p) { tg_answerCallback($cid, '❌ محصول یافت نشد!', true); exit; }
        $userCoin = user_get_coin($from_id);
        if ((int)$p['stock'] < 1) { tg_answerCallback($cid, '❌ موجودی این محصول به اتمام رسیده است!', true); exit; }
        if ($userCoin < (int)$p['price']) {
            $need = (int)$p['price'] - $userCoin;
            tg_answerCallback($cid, '❌ موجودی کافی نیست. نیاز: ' . number_format($need) . ' ریال', true);
            exit;
        }
        $kb = make_inline_kb([
            [ ['text' => '✅ تایید خرید', 'callback_data' => 'confirm:' . $pid], ['text' => '❌ انصراف', 'callback_data' => 'cancel_buy'] ],
        ]);
        tg_editMessage($chat_id, $message_id,
            '🛒 <b>تایید نهایی خرید</b>\n\n' .
            '🎯 محصول: ' . htmlspecialchars($p['name']) . "\n" .
            '💵 قیمت: ' . number_format((int)$p['price']) . " ریال\n" .
            '💰 موجودی شما: ' . number_format($userCoin) . ' ریال' . "\n\n" .
            '✅ آیا از خرید این محصول اطمینان دارید؟',
            $kb
        );
        tg_answerCallback($cid);
        exit;
    }
    if (strpos($data, 'confirm:') === 0) {
        $pid = substr($data, 8);
        $p = ProductManager::getProduct($pid);
        if (!$p) { tg_answerCallback($cid, '❌ محصول یافت نشد!', true); exit; }
        $userCoin = user_get_coin($from_id);
        if ((int)$p['stock'] < 1) { tg_answerCallback($cid, '❌ موجودی تمام شده است!', true); exit; }
        if ($userCoin < (int)$p['price']) { tg_answerCallback($cid, '❌ موجودی کافی نیست!', true); exit; }

        // کسر cost و به‌روزرسانی موجودی محصول (با خواندن مجدد)
        user_set_coin($from_id, $userCoin - (int)$p['price']);
        $p2 = ProductManager::getProduct($pid);
        if ((int)$p2['stock'] < 1) { tg_answerCallback($cid, '❌ موجودی تمام شده است!', true); exit; }
        ProductManager::updateProduct($pid, ['stock' => ((int)$p2['stock']) - 1]);

        $config = generateConfig($p2);
        $purchase = [
            'user_id' => (string)$from_id,
            'product_id' => $pid,
            'product_name' => $p2['name'],
            'price' => (int)$p2['price'],
            'config' => $config,
            'purchase_time' => time(),
        ];
        $purchase_id = uniqid('buy_', true);
        json_write(user_dir($from_id) . '/purchases/' . $purchase_id . '.json', $purchase);

        tg_editMessage($chat_id, $message_id,
            '✅ <b>خرید با موفقیت انجام شد!</b>\n\n' .
            '🎯 محصول: ' . htmlspecialchars($p2['name']) . "\n" .
            '💵 مبلغ کسر شده: ' . number_format((int)$p2['price']) . " ریال\n" .
            '💰 موجودی جدید: ' . number_format(user_get_coin($from_id)) . " ریال\n\n" .
            '🔧 کانفیگ شما:\n<code>' . htmlspecialchars($config) . '</code>'
        );
        log_event('purchase:' . $p2['name'] . ':' . (int)$p2['price'], $from_id);
        tg_answerCallback($cid);
        exit;
    }
    if ($data === 'cancel_buy') {
        tg_editMessage($chat_id, $message_id, '❌ خرید لغو شد.');
        tg_answerCallback($cid);
        exit;
    }

    // دریافت رسید برای سپرده
    if (strpos($data, 'sendres:') === 0) {
        $depId = substr($data, 8);
        $dep = load_deposit($depId);
        if (!$dep || (string)$dep['user_id'] !== (string)$from_id) { tg_answerCallback($cid, '❌ تراکنش معتبر نیست!', true); exit; }
        file_put_contents(user_dir($from_id) . '/pending_deposit.txt', $depId);
        tg_editMessage($chat_id, $message_id,
            '📤 لطفاً اطلاعات رسید را وارد کنید (مبلغ/کد پیگیری/چهار رقم آخر کارت پرداخت‌کننده).',
            null
        );
        user_set_step($from_id, 'await_receipt');
        tg_answerCallback($cid);
        exit;
    }

    // مدیریت سپرده توسط ادمین
    if (strpos($data, 'dep:approve:') === 0 && $from_id == $GLOBALS['ADMIN']) {
        $depId = substr($data, strlen('dep:approve:'));
        $dep = load_deposit($depId);
        if ($dep && $dep['status'] !== 'approved') {
            $uid = (int)$dep['user_id'];
            $current = user_get_coin($uid);
            user_set_coin($uid, $current + (int)$dep['amount']);
            $dep['status'] = 'approved';
            save_deposit($dep);
            tg_editMessage($chat_id, $message_id, '✅ سپرده تایید و شارژ شد.');
            tg_sendMessage($uid, '✅ سپرده شما تایید شد و حساب شما شارژ گردید. مبلغ: ' . number_format((int)$dep['amount']) . ' ریال');
            log_event('deposit_approved:' . $depId, $uid);
        }
        tg_answerCallback($cid);
        exit;
    }
    if (strpos($data, 'dep:reject:') === 0 && $from_id == $GLOBALS['ADMIN']) {
        $depId = substr($data, strlen('dep:reject:'));
        $dep = load_deposit($depId);
        if ($dep && $dep['status'] !== 'approved') {
            $dep['status'] = 'rejected';
            save_deposit($dep);
            tg_editMessage($chat_id, $message_id, '❌ سپرده رد شد.');
            tg_sendMessage((int)$dep['user_id'], '❌ سپرده شما توسط ادمین رد شد. در صورت خطا با پشتیبانی در تماس باشید.');
            log_event('deposit_rejected:' . $depId, (int)$dep['user_id']);
        }
        tg_answerCallback($cid);
        exit;
    }

    // No-op
    if ($data === 'noop') {
        tg_answerCallback($cid);
        exit;
    }
}

// ===============================
// مراحل ناشناخته یا پیام‌های ناشناخته
// ===============================

if ($text && !in_array($text, [$o, $oo], true)) {
    // در صورتی که چیزی از موارد بالا نبود
    tg_sendMessage($chat_id, "🤔 دستور شناخته شده نیست!\n\nاز منوی زیر استفاده کنید:", $keyMain);
}

// پایان
