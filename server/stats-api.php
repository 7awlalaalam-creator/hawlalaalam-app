<?php
/**
 * إحصاءات تطبيق «القرآن حول العالم» المجهولة — /quran/stats-api.php
 *
 * POST (JSON):
 *   {"action":"add","pages":N,"cc":"SA","ref":"K7Q2MA","khatmas":0}  صفحات جديدة منذ آخر إرسال
 *   {"action":"join","ref":"K7Q2MA"}                                    مستخدم جديد أدخل رمز من دعاه
 * GET:
 *   ?action=world            مجموع صفحات اليوم وأعلى الدول
 *   ?action=ref&code=XXXXXX  أثر رمز دعوة
 *
 * لا يُخزَّن عنوان IP ولا أي معرّف للجهاز: فقط مجاميع لكل دولة في اليوم، ولكل رمز دعوة.
 * حدّ الطلبات يستعمل بصمة يومية للعنوان (sha256 مع ملح يتغيّر كل يوم) تُحذف بانتهاء اليوم.
 */

ini_set('display_errors', '0');
header('Content-Type: application/json; charset=utf-8');
header('X-Content-Type-Options: nosniff');
date_default_timezone_set('Asia/Riyadh');

define('AWL_STATS_DIR', '/home/awlalaal/hawl-stats');
define('AWL_STATS_MAX_POSTS', 80);          // لكل عنوان في اليوم
define('AWL_STATS_MAX_PAGES', 1208);        // صفحات لكل عنوان في اليوم (ختمتان)
define('AWL_STATS_MAX_JOINS', 3);           // تسجيل رمز دعوة لكل عنوان في اليوم
define('AWL_STATS_MAX_CODES', 200000);      // حد أعلى لعدد رموز الدعوة المحفوظة
define('AWL_REF_RE', '/^[ABCDEFGHJKMNPQRSTUVWXYZ2-9]{6}$/');

function out($a, $code = 200) {
    http_response_code($code);
    echo json_encode($a, JSON_UNESCAPED_UNICODE);
    exit;
}

if (!is_dir(AWL_STATS_DIR) && !@mkdir(AWL_STATS_DIR, 0750, true)) out(['ok' => false, 'error' => 'storage'], 500);

/** يقرأ ملف JSON صغيرًا ويعدّله تحت قفل حصري، ويكتب نسخة كاملة ثم يستبدل بها الأصل (لا يضيع شيء عند خطأ) */
function with_json($name, $fn) {
    $path = AWL_STATS_DIR . '/' . $name;
    $dir = dirname($path);
    if (!is_dir($dir) && !@mkdir($dir, 0750, true)) return null;
    $h = @fopen($path . '.lock', 'c');
    if (!$h || !flock($h, LOCK_EX)) { if ($h) fclose($h); return null; }
    $raw = is_file($path) ? (string)@file_get_contents($path) : '';
    $data = $raw === '' ? [] : json_decode($raw, true);
    if (!is_array($data)) { flock($h, LOCK_UN); fclose($h); return null; }   // ملف تالف: لا نكتب فوقه
    $res = $fn($data);
    $json = json_encode($data, JSON_UNESCAPED_UNICODE);
    if ($json !== false) {
        $tmp = $path . '.' . getmypid() . '.tmp';
        if (@file_put_contents($tmp, $json) !== false) @rename($tmp, $path);
    }
    flock($h, LOCK_UN);
    fclose($h);
    return $res;
}

function read_json($name) {
    $path = AWL_STATS_DIR . '/' . $name;
    if (!is_file($path)) return [];
    $d = json_decode((string) @file_get_contents($path), true);
    return is_array($d) ? $d : [];
}

$day = date('Ymd');

// ترحيل لمرة واحدة: refs.json القديم (ملف واحد لكل الرموز) ← ملف لكل رمز
if (is_file(AWL_STATS_DIR . '/refs.json')) {
    $old = read_json('refs.json'); $n = 0;
    foreach ($old as $code => $r) {
        if (!is_array($r) || preg_match(AWL_REF_RE, (string)$code) !== 1) continue;
        with_json('refs/' . $code . '.json', function (&$d) use ($r) { foreach ($r as $k => $v) $d[$k] = $v; });
        $n++;
    }
    with_json('refs-count.json', function (&$d) use ($n) { $d['n'] = ($d['n'] ?? 0) + $n; });
    @rename(AWL_STATS_DIR . '/refs.json', AWL_STATS_DIR . '/refs-migrated.json');
}

/** عنوان الطلب؛ في IPv6 نأخذ الشبكة /64 كلها (وإلا يتجاوز المهاجم الحد بتغيير العنوان) */
function client_bucket() {
    $ip = (string)($_SERVER['REMOTE_ADDR'] ?? '');
    if (filter_var($ip, FILTER_VALIDATE_IP, FILTER_FLAG_IPV6)) {
        $bin = @inet_pton($ip);
        if ($bin !== false) $ip = bin2hex(substr($bin, 0, 8)) . '::/64';
    }
    return $ip;
}

/** حدود يومية لكل عنوان دون حفظه: ملف صغير لكل بصمة (ملح يتغيّر كل يوم، ويُحذف ما مضى) */
function rate_take($day, $pages = 0, $join = false) {
    $salt = read_json('salt.json');
    if (($salt['day'] ?? '') !== $day) {
        $salt = ['day' => $day, 'v' => bin2hex(random_bytes(16))];
        @file_put_contents(AWL_STATS_DIR . '/salt.json', json_encode($salt), LOCK_EX);
        foreach (glob(AWL_STATS_DIR . '/rate/*', GLOB_ONLYDIR) ?: [] as $d) {
            if (basename($d) !== $day) { array_map('unlink', glob($d . '/*') ?: []); @rmdir($d); }
        }
        foreach (glob(AWL_STATS_DIR . '/world-*.json') ?: [] as $f) if (filemtime($f) < time() - 90 * 86400) @unlink($f);
    }
    $key = substr(hash('sha256', client_bucket() . $salt['v']), 0, 20);
    return with_json("rate/$day/$key.json", function (&$d) use ($pages, $join) {
        $d['n'] = ($d['n'] ?? 0) + 1;
        if ($d['n'] > AWL_STATS_MAX_POSTS) return -1;
        if ($join) {
            $d['j'] = ($d['j'] ?? 0) + 1;
            return $d['j'] <= AWL_STATS_MAX_JOINS ? 1 : -1;
        }
        $left = max(0, AWL_STATS_MAX_PAGES - ($d['p'] ?? 0));
        $take = min($pages, $left);
        $d['p'] = ($d['p'] ?? 0) + $take;
        return $take;                         // الصفحات المقبولة (قد تكون أقل من المطلوب)
    });
}

/** ملف صغير لكل رمز دعوة (الرمز مطابق لـ AWL_REF_RE فهو آمن كاسم ملف) */
function ref_file($code) { return 'refs/' . $code . '.json'; }
function ref_can_create($code) {
    if (is_file(AWL_STATS_DIR . '/' . ref_file($code))) return true;
    $n = (int)(read_json('refs-count.json')['n'] ?? 0);
    return $n < AWL_STATS_MAX_CODES;
}
function ref_created() { with_json('refs-count.json', function (&$d) { $d['n'] = ($d['n'] ?? 0) + 1; }); }

$method = $_SERVER['REQUEST_METHOD'] ?? 'GET';

if ($method === 'POST') {
    $in = json_decode((string) file_get_contents('php://input', false, null, 0, 4096), true);
    if (!is_array($in)) out(['ok' => false, 'error' => 'json'], 400);
    $action = (string) ($in['action'] ?? '');
    $ref = strtoupper((string) ($in['ref'] ?? ''));
    $hasRef = preg_match(AWL_REF_RE, $ref) === 1;

    if ($action === 'join') {
        if (!$hasRef) out(['ok' => false, 'error' => 'ref'], 400);
        $r = rate_take($day, 0, true);
        if ($r === null) out(['ok' => false, 'error' => 'storage'], 503);
        if ($r < 0) out(['ok' => false, 'error' => 'rate'], 429);
        if (!ref_can_create($ref)) out(['ok' => false, 'error' => 'full'], 503);
        $new = !is_file(AWL_STATS_DIR . '/' . ref_file($ref));
        with_json(ref_file($ref), function (&$r) { $r['j'] = ($r['j'] ?? 0) + 1; });
        if ($new) ref_created();
        out(['ok' => true]);
    }

    if ($action === 'add') {
        $pages = max(0, min(604, (int) ($in['pages'] ?? 0)));
        $khatmas = max(0, min(1, (int) ($in['khatmas'] ?? 0)));
        $pages = rate_take($day, $pages);
        if ($pages === null) out(['ok' => false, 'error' => 'storage'], 503);
        if ($pages < 0) out(['ok' => false, 'error' => 'rate'], 429);
        $cc = strtoupper((string) ($in['cc'] ?? ''));
        if ($pages > 0 && preg_match('/^[A-Z]{2}$/', $cc)) {
            with_json("world-$day.json", function (&$d) use ($cc, $pages) {
                $d[$cc] = ($d[$cc] ?? 0) + $pages;
            });
        }
        if ($hasRef && ($pages > 0 || $khatmas > 0) && is_file(AWL_STATS_DIR . '/' . ref_file($ref))) {   // رمز سُجّل من قبل فقط
            with_json(ref_file($ref), function (&$r) use ($pages, $khatmas, $day) {
                $r['p'] = ($r['p'] ?? 0) + $pages;
                $r['k'] = ($r['k'] ?? 0) + $khatmas;
                if ($pages > 0) {
                    if (($r['ld'] ?? '') !== $day) { $r['d'] = ($r['d'] ?? 0) + 1; $r['ld'] = $day; $r['t'] = 0; }
                    $r['t'] = ($r['t'] ?? 0) + $pages;
                }
            });
        }
        out(['ok' => true]);
    }
    out(['ok' => false, 'error' => 'action'], 400);
}

// بعض الخوادم لا تمرّر الاستعلام إلى $_GET: نقرؤه من الرابط نفسه احتياطًا
$q = $_GET;
if (empty($q['action'])) parse_str((string) (parse_url($_SERVER['REQUEST_URI'] ?? '', PHP_URL_QUERY) ?: ($_SERVER['QUERY_STRING'] ?? '')), $q);
$action = (string) ($q['action'] ?? '');
if ($action === '') $action = 'world';                 // الرابط المجرد يعرض الخريطة

if ($action === 'world') {
    header('Cache-Control: public, max-age=60');
    $w = read_json("world-$day.json");
    arsort($w);
    $top = [];
    foreach (array_slice($w, 0, 60, true) as $cc => $p) $top[] = ['cc' => $cc, 'pages' => (int) $p];
    out(['ok' => true, 'day' => $day, 'total' => array_sum($w), 'countries' => count($w), 'top' => $top]);
}

if ($action === 'ref') {
    header('Cache-Control: no-store');
    $code = strtoupper((string) ($q['code'] ?? ''));
    if (preg_match(AWL_REF_RE, $code) !== 1) out(['ok' => false, 'error' => 'ref'], 400);
    $r = read_json(ref_file($code));
    out([
        'ok' => true,
        'joined' => (int) ($r['j'] ?? 0),
        'pages' => (int) ($r['p'] ?? 0),
        'today' => ($r['ld'] ?? '') === $day ? (int) ($r['t'] ?? 0) : 0,
        'khatmas' => (int) ($r['k'] ?? 0),
        'days' => (int) ($r['d'] ?? 0),
    ]);
}

out(['ok' => false, 'error' => 'action'], 400);
