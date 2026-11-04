# Fixtures

Recorded from OJAD on 2026-11-04, one request each, several seconds apart, with the
User-Agent `OJAD-personal-ios-dev (+https://github.com/Umasteas/OJAD)`.

Search pages (`GET /ojad/search/index/curve:fujisaki/word:<word>`) are trimmed to the
`div#search_result` block (site chrome and scripts outside it removed) and wrapped in a
minimal HTML document. Nothing inside the block is edited.

| File | Query |
|---|---|
| `search-taberu.html` | 食べる (2グループ verb) |
| `search-takai.html` | 高い (い-adjective, accent variants) |
| `search-shizuka.html` | 静か (な-adjective) |
| `search-gakkou.html` | 学校 (noun) |
| `search-kiru.html` | きる (homonyms 切る / 着る) |
| `search-nomu-shizuka.html` | 飲む,静か (batch query: header belongs to the first row only) |
| `search-no-result.html` | zzqqxxふが |

スズキクン pages (`POST /ojad/phrasing/index`, `curve=advanced`, `estimation=crf`) are
trimmed to the `div#phrasing_main` block the same way.

| File | Text |
|---|---|
| `phrasing-asagohan.html` | 朝ご飯を食べるのを忘れた。 |
| `phrasing-kinou-oishikatta.html` | 昨日、友達と駅前の店でラーメンを食べました。美味しかったですか？ |

`tatoeba-taberu.json` is the unmodified response of
`GET https://api.tatoeba.org/v1/sentences?lang=jpn&q=食べる&sort=relevance&word_count=6-40&is_orphan=no&is_unapproved=no&trans:lang=cmn,eng&trans:is_unapproved=no&showtrans=matching&limit=10`
(sentences CC BY 2.0 FR, by their listed owners on tatoeba.org).

`fujisaki-golden.json` holds `[position, level]` samples computed by OJAD's own
`/ojad/js/function.js?20180709` in Node: `f.set_type(type)`, then
`f.fujisaki_curve(i, accent, 1, phrase, question)` minus `Ap * f._Gp(start + morae * mola)`,
for `i` stepping from 0 while `i < morae + 0.3`.
