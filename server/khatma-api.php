<?php
/*
 * الختمة الجماعية (ختمة العائلة) — خادم بسيط لموقع «القرآن حول العالم»
 * يُرفع في مجلد /quran/ بجانب family-khatma.html. لا يحتاج قاعدة بيانات: كل ختمة ملف JSON صغير.
 * البيانات تُحفظ خارج public_html إن أمكن (لا تُحمَّل من المتصفح)، وإلا في مجلد محمي بجانب الملف.
 * لا أسماء حقيقية مطلوبة ولا بريد ولا أرقام: اسم يكتبه المشارك بنفسه، ورمز عشوائي يحفظه جهازه.
 */
header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: no-store');
header('X-Content-Type-Options: nosniff');

const PARTS = 30;
const MAX_GROUP_BYTES = 64000;

function data_dir() {
    $out = dirname(__DIR__, 2) . '/hawl-khatma-data';          // خارج public_html
    if ((@is_dir($out) || @mkdir($out, 0750, true)) && @is_writable($out)) return $out;
    $in = __DIR__ . '/khatma-data';                             // بديل: بجانب الملف مع منع القراءة المباشرة
    if (!@is_dir($in)) @mkdir($in, 0750, true);
    if (!@is_file($in . '/.htaccess')) @file_put_contents($in . '/.htaccess', "Require all denied\nDeny from all\n");
    if (!@is_file($in . '/index.html')) @file_put_contents($in . '/index.html', '');
    return $in;
}

function fail($msg, $code = 400) { http_response_code($code); echo json_encode(['ok' => false, 'error' => $msg], JSON_UNESCAPED_UNICODE); exit; }
function ok($a) { echo json_encode(['ok' => true] + $a, JSON_UNESCAPED_UNICODE); exit; }

/** نص قصير نظيف: بلا وسوم ولا رموز تحكم، وطول محدود */
function clean($s, $max) {
    $s = trim(preg_replace('/[\x00-\x1F\x7F\x{200B}-\x{200F}\x{202A}-\x{202E}\x{2066}-\x{2069}]/u', '', strip_tags((string)$s)));
    return mb_substr($s, 0, $max);
}
function token_ok($t) { return is_string($t) && preg_match('/^[A-Za-z0-9_-]{16,64}$/', $t); }
function new_id() {
    $abc = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';                   // دون حروف وأرقام متشابهة
    $s = ''; for ($i = 0; $i < 6; $i++) $s .= $abc[random_int(0, strlen($abc) - 1)];
    return $s;
}
function path_of($id) {
    if (!preg_match('/^[A-Z2-9]{6}$/', (string)$id)) fail('رمز الختمة غير صحيح');
    return data_dir() . '/' . $id . '.json';
}

/** يقرأ الختمة ويعدّلها تحت قفل (لا يتعارض مشاركان يحجزان في اللحظة نفسها) */
function with_group($id, $fn) {
    $f = path_of($id);
    if (!is_file($f)) fail('لم نجد هذه الختمة، ربما حُذفت', 404);
    $h = fopen($f, 'c+');
    if (!$h || !flock($h, LOCK_EX)) fail('حاول مرة أخرى', 503);
    $g = json_decode(stream_get_contents($h), true);
    if (!is_array($g)) { flock($h, LOCK_UN); fclose($h); fail('ملف الختمة تالف', 500); }
    $res = $fn($g);                                             // تعيد [الختمة بعد التعديل أو null، الرد]
    if ($res[0] !== null) {
        $res[0]['updated'] = time();
        $json = json_encode($res[0], JSON_UNESCAPED_UNICODE);
        if (strlen($json) > MAX_GROUP_BYTES) { flock($h, LOCK_UN); fclose($h); fail('الختمة كبيرة جدًا'); }
        ftruncate($h, 0); rewind($h); fwrite($h, $json); fflush($h);
    }
    flock($h, LOCK_UN); fclose($h);
    return $res[1];
}

/** ما يراه الجميع: دون رموز الأجهزة */
function public_view($g, $me) {
    $parts = [];
    foreach ($g['parts'] as $n => $p) {
        $parts[] = ['n' => $n + 1, 'by' => $p['by'] ?? null, 'done' => !empty($p['done']), 'mine' => $me !== '' && ($p['m'] ?? '') === $me];
    }
    return ['id' => $g['id'], 'name' => $g['name'], 'owner' => $g['owner'], 'note' => $g['note'], 'deadline' => $g['deadline'],
            'round' => $g['round'], 'parts' => $parts, 'admin' => false];
}

/** حد بسيط لإنشاء الختمات من العنوان نفسه (٢٠ في الساعة) */
function rate_limit_create() {
    $f = data_dir() . '/_rate.json';
    $ip = hash('sha256', ($_SERVER['REMOTE_ADDR'] ?? '') . 'hawl');
    $h = fopen($f, 'c+'); if (!$h) return;
    flock($h, LOCK_EX);
    $r = json_decode(stream_get_contents($h), true) ?: [];
    $now = time();
    foreach ($r as $k => $v) { $r[$k] = array_values(array_filter($v, function ($t) use ($now) { return $t > $now - 3600; })); if (!$r[$k]) unset($r[$k]); }
    $r[$ip] = $r[$ip] ?? [];
    if (count($r[$ip]) >= 20) { flock($h, LOCK_UN); fclose($h); fail('أنشأت ختمات كثيرة، حاول بعد ساعة', 429); }
    $r[$ip][] = $now;
    ftruncate($h, 0); rewind($h); fwrite($h, json_encode($r)); flock($h, LOCK_UN); fclose($h);
}

$in = json_decode(file_get_contents('php://input') ?: '[]', true);
if (!is_array($in)) $in = [];
$in += $_GET;
$action = (string)($in['action'] ?? '');
$me = token_ok($in['member'] ?? '') ? $in['member'] : '';

switch ($action) {
    case 'create':
        if ($_SERVER['REQUEST_METHOD'] !== 'POST') fail('طريقة غير صحيحة', 405);
        if ($me === '') fail('رمز الجهاز مفقود');
        $name = clean($in['name'] ?? '', 40);
        $owner = clean($in['owner'] ?? '', 30);
        if ($name === '' || $owner === '') fail('اكتب اسم الختمة واسمك');
        rate_limit_create();
        do { $id = new_id(); $f = path_of($id); } while (file_exists($f));
        $admin = bin2hex(random_bytes(16));
        $deadline = preg_match('/^\d{4}-\d{2}-\d{2}$/', (string)($in['deadline'] ?? '')) ? $in['deadline'] : '';
        $g = ['id' => $id, 'name' => $name, 'owner' => $owner, 'note' => clean($in['note'] ?? '', 80), 'deadline' => $deadline,
              'round' => 1, 'admin' => hash('sha256', $admin), 'created' => time(), 'parts' => array_fill(0, PARTS, ['by' => null])];
        if (file_put_contents($f, json_encode($g, JSON_UNESCAPED_UNICODE), LOCK_EX) === false) fail('تعذّر الحفظ على الخادم', 500);
        $v = public_view($g, $me); $v['admin'] = true;
        ok(['group' => $v, 'adminKey' => $admin]);

    case 'get':
        $f = path_of($in['id'] ?? '');
        if (!is_file($f)) fail('لم نجد هذه الختمة، ربما حُذفت', 404);
        $g = json_decode((string)file_get_contents($f), true);
        if (!is_array($g)) fail('ملف الختمة تالف', 500);
        $v = public_view($g, $me);
        $v['admin'] = isset($in['adminKey']) && is_string($in['adminKey']) && hash_equals($g['admin'], hash('sha256', $in['adminKey']));
        ok(['group' => $v]);

    case 'take':
    case 'done':
    case 'undo':
    case 'release':
        if ($_SERVER['REQUEST_METHOD'] !== 'POST') fail('طريقة غير صحيحة', 405);
        if ($me === '') fail('رمز الجهاز مفقود');
        $n = (int)($in['part'] ?? 0);
        if ($n < 1 || $n > PARTS) fail('رقم الجزء غير صحيح');
        $who = clean($in['who'] ?? '', 30);
        $res = with_group($in['id'] ?? '', function ($g) use ($action, $n, $me, $who) {
            $p = &$g['parts'][$n - 1];
            $mine = ($p['m'] ?? '') === $me;
            if ($action === 'take') {
                if (!empty($p['by']) && !$mine) return [null, ['taken' => true]];
                if ($who === '') return [null, ['needName' => true]];
                $p = ['by' => $who, 'm' => $me, 'done' => false, 'at' => time()];
            } elseif (!$mine) {
                return [null, ['notMine' => true]];
            } elseif ($action === 'done') {
                $p['done'] = true; $p['at'] = time();
            } elseif ($action === 'undo') {
                $p['done'] = false;
            } else {
                $p = ['by' => null];
            }
            unset($p);
            return [$g, ['group' => public_view($g, $me)]];
        });
        if (!empty($res['taken'])) fail('حجز هذا الجزء شخص آخر قبلك', 409);
        if (!empty($res['needName'])) fail('اكتب اسمك');
        if (!empty($res['notMine'])) fail('هذا الجزء ليس محجوزًا باسمك', 403);
        ok($res);

    case 'newround':                 // بعد إتمام الختمة: ختمة جديدة بالرابط نفسه (لمنشئها فقط)
    case 'delete':
        if ($_SERVER['REQUEST_METHOD'] !== 'POST') fail('طريقة غير صحيحة', 405);
        $key = (string)($in['adminKey'] ?? '');
        $id = $in['id'] ?? '';
        if ($action === 'delete') {
            $f = path_of($id);
            $g = is_file($f) ? json_decode((string)file_get_contents($f), true) : null;
            if (!is_array($g) || !hash_equals($g['admin'], hash('sha256', $key))) fail('هذا لمنشئ الختمة فقط', 403);
            @unlink($f);
            ok(['deleted' => true]);
        }
        $res = with_group($id, function ($g) use ($key, $me) {
            if (!hash_equals($g['admin'], hash('sha256', $key))) return [null, ['denied' => true]];
            $g['round'] = ($g['round'] ?? 1) + 1;
            $g['parts'] = array_fill(0, PARTS, ['by' => null]);
            $v = public_view($g, $me); $v['admin'] = true;
            return [$g, ['group' => $v]];
        });
        if (!empty($res['denied'])) fail('هذا لمنشئ الختمة فقط', 403);
        ok($res);

    default:
        fail('طلب غير معروف');
}
