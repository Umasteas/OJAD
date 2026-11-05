# Fixtures

`ojad-recorded.json` holds OJAD's word entries for 食べる, 高い, 静か and 学校, keyed by query.
They were parsed from OJAD's search pages (`GET /ojad/search/index/curve:fujisaki/word:<word>`),
recorded on 2026-11-04 with the User-Agent `OJAD-personal-ios-dev (+https://github.com/Umasteas/OJAD)`,
by the parser the app had while it still had online features. They are encoded as `WordEntry` JSON.

`fujisaki-golden.json` holds `[position, level]` samples computed by OJAD's own
`/ojad/js/function.js?20180709` in Node: `f.set_type(type)`, then
`f.fujisaki_curve(i, accent, 1, phrase, question)` minus `Ap * f._Gp(start + morae * mola)`,
for `i` stepping from 0 while `i < morae + 0.3`.

## Offline dictionary

`sample-dictionary.sqlite` is generated, not edited: `scripts/dictionary/build.py` run on
`scripts/dictionary/sample/`, which holds the pinned sources (`scripts/dictionary/sources.json`)
filtered to the words in `scripts/dictionary/sample-words.txt`:

```
python3 scripts/dictionary/build.py --make-sample scripts/dictionary/sample-words.txt
python3 scripts/dictionary/build.py --inputs scripts/dictionary/sample \
    --out Packages/OJADKit/Tests/OJADKitTests/Fixtures/sample-dictionary.sqlite
```

`scripts/dictionary/test_build.py` checks that the committed file matches a fresh build.

`ojad-validation.json` is what OJAD lists for 510 words, recorded on 2026-11-04 with the
User-Agent `OJADPersonal/1.0 (personal study app; +https://github.com/Umasteas/OJAD)` from
`GET /ojad/search/index/curve:fujisaki/category:<n>/limit:<m>` (one request per page) and
parsed by the same former parser. One row per word: `id`, `headword`, `category`, `forms` as
`[kind, ["<notation> <H/L per mora> <accent commands>", …]]`, and the OJAD list it came from:

| `ojadCategory` | `category:` | Pages |
|---|---|---|
| `godan` | 1 | `limit:100`, pages 1 and 3 |
| `ichidan` | 2 | `limit:100` |
| `irregular` | 3 | `limit:30` |
| `iAdjective` | 4 | `limit:100` |
| `naAdjective` | 5 | `limit:50` |
| `noun` | 6 | `limit:30` |
