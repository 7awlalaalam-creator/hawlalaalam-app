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

header('Content-Type: application/json; charset=utf-8');
header('X-Content-Type-Options: nosniff');
date_default_timezone_set('Asia/Riyadh');

define('AWL_STATS_DIR', '/home/awlalaal/hawl-stats');
define('AWL_STATS_MAX_POSTS', 80);          // لكل عنوان في اليوم
define('AWL_REF_RE', '/^[ABCDEFGHJKMNPQRSTUVWXYZ2-9]{6}$/');

function out($a, $code = 200) {
    http_response_code($code);
    echo json_encode($a, JSON_UNESCAPED_UNICODE);
    exit;
}

if (!is_dir(AWL_STATS_DIR) && !@mkdir(AWL_STATS_DIR, 0750, true)) out(['ok' => false, 'error' => 'storage'], 500);

/** يقرأ ملف JSON ويعدّله تحت قفل حصري */
function with_json($name, $fn) {
    $path = AWL_STATS_DIR . '/' . $name;
    $h = fopen($path, 'c+');
    if (!$h) return null;
    flock($h, LOCK_EX);
    $raw = stream_get_contents($h);
    $data = $raw ? json_decode($raw, true) : [];
    if (!is_array($data)) $data = [];
    $res = $fn($data);
    ftruncate($h, 0);
    rewind($h);
    fwrite($h, json_encode($data, JSON_UNESCAPED_UNICODE));
    fflush($h);
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

/** حدّ الطلبات اليومي دون حفظ العنوان */
function rate_ok($day) {
    $salt = read_json('salt.json');
    if (($salt['day'] ?? '') !== $day) {
        $salt = ['day' => $day, 'v' => bin2hex(random_bytes(16))];
        @file_put_contents(AWL_STATS_DIR . '/salt.json', json_encode($salt));
        foreach (glob(AWL_STATS_DIR . '/rate-*.json') ?: [] as $f) if (basename($f) !== "rate-$day.json") @unlink($f);
    }
    $key = substr(hash('sha256', ($_SERVER['REMOTE_ADDR'] ?? '') . $salt['v']), 0, 16);
    return with_json("rate-$day.json", function (&$d) use ($key) {
        $d[$key] = ($d[$key] ?? 0) + 1;
        return $d[$key] <= AWL_STATS_MAX_POSTS;
    });
}

$method = $_SERVER['REQUEST_METHOD'] ?? 'GET';

if ($method === 'POST') {
    $in = json_decode((string) file_get_contents('php://input', false, null, 0, 4096), true);
    if (!is_array($in)) out(['ok' => false, 'error' => 'json'], 400);
    if (!rate_ok($day)) out(['ok' => false, 'error' => 'rate'], 429);
    $action = (string) ($in['action'] ?? '');
    $ref = strtoupper((string) ($in['ref'] ?? ''));
    $hasRef = preg_match(AWL_REF_RE, $ref) === 1;

    if ($action === 'join') {
        if (!$hasRef) out(['ok' => false, 'error' => 'ref'], 400);
        with_json('refs.json', function (&$d) use ($ref) {
            $r = $d[$ref] ?? [];
            $r['j'] = ($r['j'] ?? 0) + 1;
            $d[$ref] = $r;
        });
        out(['ok' => true]);
    }

    if ($action === 'add') {
        $pages = max(0, min(604, (int) ($in['pages'] ?? 0)));
        $khatmas = max(0, min(3, (int) ($in['khatmas'] ?? 0)));
        $cc = strtoupper((string) ($in['cc'] ?? ''));
        if ($pages > 0 && preg_match('/^[A-Z]{2}$/', $cc)) {
            with_json("world-$day.json", function (&$d) use ($cc, $pages) {
                $d[$cc] = ($d[$cc] ?? 0) + $pages;
            });
        }
        if ($hasRef && ($pages > 0 || $khatmas > 0)) {
            with_json('refs.json', function (&$d) use ($ref, $pages, $khatmas, $day) {
                $r = $d[$ref] ?? [];
                $r['p'] = ($r['p'] ?? 0) + $pages;
                $r['k'] = ($r['k'] ?? 0) + $khatmas;
                if ($pages > 0) {
                    if (($r['ld'] ?? '') !== $day) { $r['d'] = ($r['d'] ?? 0) + 1; $r['ld'] = $day; $r['t'] = 0; }
                    $r['t'] = ($r['t'] ?? 0) + $pages;
                }
                $d[$ref] = $r;
            });
        }
        out(['ok' => true]);
    }
    out(['ok' => false, 'error' => 'action'], 400);
}

$action = (string) ($_GET['action'] ?? '');

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
    $code = strtoupper((string) ($_GET['code'] ?? ''));
    if (preg_match(AWL_REF_RE, $code) !== 1) out(['ok' => false, 'error' => 'ref'], 400);
    $r = read_json('refs.json')[$code] ?? [];
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
