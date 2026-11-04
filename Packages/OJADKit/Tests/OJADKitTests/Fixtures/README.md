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

`fujisaki-golden.json` holds `[position, level]` samples computed by OJAD's own
`/ojad/js/function.js?20180709` in Node: `f.set_type(type)`, then
`f.fujisaki_curve(i, accent, 1, phrase, question)` minus `Ap * f._Gp(start + morae * mola)`,
for `i` stepping from 0 while `i < morae + 0.3`.
