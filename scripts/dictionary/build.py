#!/usr/bin/env python3
"""Builds the offline dictionary (SQLite) from pinned Kanjium, JMdict, corpus and Chinese sources.

    python3 scripts/dictionary/build.py --out App/Generated/Dictionary.sqlite
    python3 scripts/dictionary/build.py --inputs scripts/dictionary/sample --out sample.sqlite
    python3 scripts/dictionary/build.py --make-sample scripts/dictionary/sample-words.txt

The schema and key normalization must stay in sync with
Packages/OJADKit/Sources/OJADKit/OfflineDictionary.swift and Kana.swift.
"""

import argparse
import gzip
import hashlib
import io
import json
import math
import os
import re
import sqlite3
import sys
import time
import unicodedata
import urllib.request
import zipfile

import chinese
import examples as corpus_examples

HERE = os.path.dirname(os.path.abspath(__file__))
SCHEMA_VERSION = 4
# Suggestions for prefixes matching more than PREFIX_MIN_KEYS keys are precomputed
# (top PREFIX_TOP words), so no query on the phone scans more than that many keys.
PREFIX_TOP = 20
PREFIX_MIN_KEYS = 32
PREFIX_MAX_LENGTH = 4

TATOEBA_VERSION = '2026-10-31'
TATOEBA_FILES = {
    'japanese': 'jpn_sentences.tsv.bz2', 'indices': 'jpn_indices.tar.bz2',
    'eng_links': 'jpn-eng_links.tsv.bz2', 'english': 'eng_sentences.tsv.bz2',
    'cmn_links': 'jpn-cmn_links.tsv.bz2', 'chinese': 'cmn_sentences.tsv.bz2', 'cmn_eng_links': 'cmn-eng_links.tsv.bz2',
}
WIKTIONARY_VERSION = 'zhwiktionary 2026-11-01 (kaikki.org, wiktextract 19f9a30)'
WIKTIONARY_FILES = ('zhwiktionary-ja-hans.jsonl', 'zhwiktionary-ja-hant.jsonl')
CEDICT_FILE = 'cedict_1_0_ts_utf-8_mdbg.txt.gz'
CEDICT_VERSION = '2026-11-04'
OPENCC_FILES = {'ts_characters': 'TSCharacters.txt', 'ts_phrases': 'TSPhrases.txt', 'jp_shinjitai': 'JPShinjitaiCharacters.txt'}

CONJUGATING = {
    'v1', 'v1-s', 'v5aru', 'v5b', 'v5g', 'v5k', 'v5k-s', 'v5m', 'v5n', 'v5r', 'v5r-i', 'v5s', 'v5t',
    'v5u', 'v5u-s', 'vk', 'vs-i', 'vs-s', 'vz', 'adj-i', 'adj-ix', 'adj-na',
}
GODAN_ENDINGS = {'v5b': 'ぶ', 'v5g': 'ぐ', 'v5k': 'く', 'v5k-s': 'く', 'v5m': 'む', 'v5n': 'ぬ', 'v5r': 'る',
                 'v5r-i': 'る', 'v5aru': 'る', 'v5s': 'す', 'v5t': 'つ', 'v5u': 'う', 'v5u-s': 'う'}
HIDDEN_KANJI_TAGS = {'rK', 'sK', 'iK', 'oK', 'ik'}
HIDDEN_KANA_TAGS = {'sk', 'ik', 'ok'}


# ---------- normalization (mirrors Kana.searchKey in Swift) ----------

def search_key(text):
    text = unicodedata.normalize('NFKC', text).lower()
    return ''.join(chr(ord(c) - 0x60) if 'ァ' <= c <= 'ヶ' else c for c in text)


def is_kana(text):
    return all('ぁ' <= c <= 'ゖ' or 'ァ' <= c <= 'ヺ' or c in 'ーゝゞヽヾ' for c in text)


# ---------- inputs ----------

def sha256(path):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for chunk in iter(lambda: f.read(1 << 20), b''):
            h.update(chunk)
    return h.hexdigest()


def download(url, path, attempts=4):
    """The Wayback Machine, which serves the Tatoeba and KFTT snapshots, is sometimes slow to answer."""
    for attempt in range(attempts):
        print(f'downloading {url}', file=sys.stderr)
        try:
            request = urllib.request.Request(url, headers={'User-Agent': 'OJAD-dictionary-build'})
            with urllib.request.urlopen(request, timeout=300) as response, open(path + '.part', 'wb') as out:
                out.write(response.read())
            os.replace(path + '.part', path)
            return
        except OSError as error:
            if attempt == attempts - 1:
                raise
            print(f'  failed ({error}), retrying', file=sys.stderr)
            time.sleep(4 * 2 ** attempt)


def fetch_sources(cache_dir):
    with open(os.path.join(HERE, 'sources.json'), encoding='utf-8') as f:
        sources = json.load(f)
    os.makedirs(cache_dir, exist_ok=True)
    paths = {}
    for group in sources.values():
        for name, spec in group['files'].items():
            path = os.path.join(cache_dir, name)
            if not os.path.exists(path) or sha256(path) != spec['sha256']:
                download(spec['url'], path)
            actual = sha256(path)
            if actual != spec['sha256']:
                sys.exit(f'{name}: sha256 {actual} does not match the pinned {spec["sha256"]}')
            paths[name] = path
    return paths


def load_jmdict(path):
    if path.endswith('.zip'):
        with zipfile.ZipFile(path) as z:
            name = next(n for n in z.namelist() if n.endswith('.json'))
            with z.open(name) as f:
                return json.load(io.TextIOWrapper(f, encoding='utf-8'))
    with open(path, encoding='utf-8') as f:
        return json.load(f)


def load_accents(path):
    rows = []
    with open(path, encoding='utf-8') as f:
        for line in f:
            parts = line.rstrip('\n').split('\t')
            if len(parts) != 3:
                continue
            written, reading, field = parts
            accents = list(dict.fromkeys(int(x) for x in re.findall(r'\d+', field)))
            if accents:
                rows.append((written, reading or written, accents))
    return rows


def load_frequencies(path):
    freq = {}
    with open(path, encoding='utf-8') as f:
        for line in f:
            if line.startswith('#'):
                continue
            parts = line.rstrip('\n').split('\t')
            if len(parts) == 2 and parts[1].isdigit():
                freq[parts[0]] = max(freq.get(parts[0], 0), int(parts[1]))
    return freq


# ---------- JMdict matching ----------

class JMdict:
    def __init__(self, data):
        self.version = data.get('version', '')
        self.date = data.get('dictDate', '')
        self.by_pair = {}
        self.by_kana = {}
        for entry in data['words']:
            kanji = [k['text'] for k in entry['kanji']]
            for kana in entry['kana']:
                self.by_kana.setdefault(kana['text'], []).append(entry)
                applies = kana['appliesToKanji']
                for k in kanji:
                    if '*' in applies or k in applies:
                        self.by_pair.setdefault((k, kana['text']), []).append(entry)

    def match(self, written, reading):
        if is_kana(written):
            candidates = [e for e in self.by_kana.get(written, [])]
            candidates.sort(key=lambda e: (not usually_kana(e) and bool(e['kanji']), not any(k['common'] for k in e['kana']), int(e['id'])))
        else:
            candidates = list(self.by_pair.get((written, reading), []))
            candidates.sort(key=lambda e: (not any(k['common'] for k in e['kanji'] if k['text'] == written), int(e['id'])))
            if not candidates and len(written) > 1 and written[-1] == reading[-1]:
                # e.g. Kanjium 良い/いい vs JMdict's kana-only いい entry.
                candidates = [e for e in self.by_kana.get(reading, []) if not e['kanji']]
        return candidates[0] if candidates else None


def usually_kana(entry):
    return bool(entry['sense']) and 'uk' in entry['sense'][0]['misc']


def senses_for(entry, written, reading):
    out = []
    for sense in entry['sense']:
        kanji_ok = is_kana(written) or '*' in sense['appliesToKanji'] or written in sense['appliesToKanji']
        kana_ok = '*' in sense['appliesToKana'] or reading in sense['appliesToKana']
        if kanji_ok and kana_ok:
            out.append(sense)
    return out or entry['sense']


def word_class(senses, reading):
    for sense in senses:
        for pos in sense['partOfSpeech']:
            if pos not in CONJUGATING:
                continue
            if pos in GODAN_ENDINGS and reading.endswith(GODAN_ENDINGS[pos]):
                return pos
            if pos in ('v1', 'v1-s', 'vz') and reading.endswith('る'):
                return pos
            if pos == 'vk' and reading.endswith('くる'):
                return pos
            if pos in ('vs-i', 'vs-s') and reading.endswith('する'):
                return pos
            if pos in ('adj-i', 'adj-ix') and reading.endswith('い'):
                return pos
            if pos == 'adj-na':
                return pos
    return 'n'


def display_written(entry, kanjium_written, reading):
    if entry is None:
        return kanjium_written
    if usually_kana(entry) or not entry['kanji']:
        return reading
    applicable = []
    for kana in entry['kana']:
        if kana['text'] == reading:
            applies = kana['appliesToKanji']
            applicable = [k for k in entry['kanji'] if '*' in applies or k['text'] in applies]
    visible = [k for k in applicable if not HIDDEN_KANJI_TAGS & set(k['tags'])]
    for k in visible:
        if k['common']:
            return k['text']
    return visible[0]['text'] if visible else kanjium_written


def spellings(entry, kanjium_written, reading):
    out = [kanjium_written, reading]
    if entry is not None:
        for kana in entry['kana']:
            if kana['text'] == reading:
                applies = kana['appliesToKanji']
                out += [k['text'] for k in entry['kanji']
                        if ('*' in applies or k['text'] in applies) and 'sK' not in k['tags']]
        out += [k['text'] for k in entry['kana']
                if search_key(k['text']) == search_key(reading) and not HIDDEN_KANA_TAGS & set(k['tags'])]
    return list(dict.fromkeys(out))


def english_glosses(sense):
    return [g['text'] for g in sense['gloss'] if g.get('lang', 'eng') == 'eng']


def gloss_text(glosses):
    text = '; '.join(glosses[:3])
    return text if len(text) <= 80 else text[:79] + '…'


def short_gloss(senses):
    for sense in senses:
        glosses = english_glosses(sense)
        if glosses:
            return gloss_text(glosses)
    return None


def numbered(entry, senses):
    """[(1-based JMdict sense number, sense)] for the senses that apply to this spelling."""
    return [(number, sense) for number, sense in enumerate(entry['sense'], start=1) if any(sense is s for s in senses)]


def jmdict_examples(numbered_senses):
    for number, sense in numbered_senses:
        for example in sense.get('examples', []):
            if example['source']['type'] != 'tatoeba':
                continue
            texts = {s['lang']: s['text'] for s in example['sentences']}
            if 'jpn' in texts:
                yield int(example['source']['value']), number, texts['jpn'], texts.get('eng'), example['text']


# ---------- build ----------

def build(accents_rows, novels, wiki, jmdict):
    groups = {}
    for written, reading, accents in accents_rows:
        entry = jmdict.match(written, reading)
        key = ('j', entry['id'], search_key(reading)) if entry else ('k', written, reading)
        group = groups.get(key)
        if group is None:
            group = groups[key] = {'entry': entry, 'written': written, 'reading': reading, 'accents': [], 'spellings': []}
        group['accents'] = list(dict.fromkeys(group['accents'] + accents))
        group['spellings'] = list(dict.fromkeys(group['spellings'] + spellings(entry, written, reading)))

    words = []
    for group in groups.values():
        entry, reading = group['entry'], group['reading']
        senses = senses_for(entry, group['written'], reading) if entry else []
        cls = word_class(senses, reading)
        written = display_written(entry, group['written'], reading)
        common = bool(entry) and any(k['common'] for k in entry['kana'] if k['text'] == reading)
        # Prefer the kanji spellings' frequency: the bare kana of e.g. 掏る (する) is a different, far commoner word.
        counted = [s for s in group['spellings'] if not is_kana(s) and (s in novels or s in wiki)]
        if not counted or (common and usually_kana(entry)):
            counted = group['spellings']
        freq_novels = max((novels.get(s, 0) for s in counted), default=0)
        freq_wiki = max((wiki.get(s, 0) for s in counted), default=0)
        rank = int(100 * math.log1p(freq_novels) + 150 * math.log1p(freq_wiki) + (300 if common else 0))
        base = {
            'written': written, 'reading': reading, 'accents': group['accents'], 'class': cls, 'rank': rank,
            'gloss': short_gloss(senses), 'keys': group['spellings'] + [written],
            'entry': entry, 'senses': numbered(entry, senses) if entry else [], 'suru': False,
        }
        words.append(base)
        takes_suru = any('vs' in s['partOfSpeech'] for s in senses)
        if takes_suru and cls in ('n', 'adj-na') and not reading.endswith('する'):
            suru_senses = [s for s in senses if 'vs' in s['partOfSpeech']]
            words.append({
                'written': written + 'する', 'reading': reading + 'する', 'accents': group['accents'], 'class': 'vs-i',
                'rank': rank - 1, 'gloss': short_gloss(suru_senses), 'keys': [s + 'する' for s in group['spellings']],
                'entry': entry, 'senses': numbered(entry, suru_senses), 'suru': True, 'base': base,
            })

    seen = set()
    unique = []
    for word in sorted(words, key=lambda w: (search_key(w['reading']), w['written'], w['class'], -w['rank'])):
        identity = (word['written'], word['reading'], word['class'])
        if identity in seen:
            continue
        seen.add(identity)
        unique.append(word)
    return unique


def default_reading(entry, head):
    if is_kana(head):
        return head
    for kana in entry['kana']:
        if '*' in kana['appliesToKanji'] or head in kana['appliesToKanji']:
            return kana['text']
    return None


def attach_examples(words, corpus, kftt):
    """Sets word['examples'] from JMdict's own examples plus every Tatoeba sentence
    whose index lists the word, each tied to the sense it illustrates where known."""
    by_spelling = {}
    for word in words:
        if word['entry'] is not None and not word['suru']:
            for spelling in dict.fromkeys(word['keys']):
                by_spelling.setdefault(spelling, []).append(word)
    suru_of = {id(w['base']): w for w in words if w['suru']}
    candidates = {}

    def add(word, sentence_id, sense, basis, japanese, english, form, checked):
        found = candidates.setdefault(id(word), {})
        if sentence_id not in found and len(japanese) <= corpus_examples.MAX_LENGTH:
            via = corpus.chinese_via_english.get(sentence_id)
            found[sentence_id] = {
                'id': sentence_id, 'sense': sense, 'basis': basis, 'japanese': japanese, 'english': english,
                'chinese': corpus.chinese.get(sentence_id) or via, 'chinese_via': 'english' if via else None,
                'form': form, 'checked': checked,
            }

    def resolve(token):
        options = by_spelling.get(token['head'], [])
        if token['reading']:
            key = search_key(token['reading'])
            options = [w for w in options if search_key(w['reading']) == key]
        elif len(options) > 1:
            options = [w for w in options if w['reading'] == default_reading(w['entry'], token['head'])] or options
        return max(options, key=lambda w: (w['rank'], w['reading'])) if options else None

    def assign(word, token, english):
        numbers = [number for number, _ in word['senses']]
        if token['sense'] is not None:
            return (token['sense'], corpus_examples.TAGGED) if token['sense'] in numbers else (None, corpus_examples.UNASSIGNED)
        if len(numbers) == 1:
            return numbers[0], corpus_examples.SINGLE
        number = corpus_examples.gloss_sense(english, [(n, english_glosses(s)) for n, s in word['senses']])
        return (number, corpus_examples.GLOSS) if number else (None, corpus_examples.UNASSIGNED)

    for word in words:
        if word['entry'] is not None:
            for sentence_id, number, japanese, english, form in jmdict_examples(word['senses']):
                add(word, sentence_id, number, corpus_examples.JMDICT, japanese, english, form, True)

    for sentence_id, tokens in corpus.tokens.items():
        japanese, english = corpus.japanese[sentence_id], corpus.english.get(sentence_id)
        for position, token in enumerate(tokens):
            word = resolve(token)
            if word is None:
                continue
            add(word, sentence_id, *assign(word, token, english), japanese, english, token['surface'], token['checked'])
            suru = suru_of.get(id(word))
            following = tokens[position + 1] if position + 1 < len(tokens) else None
            if suru and following and following['head'] == '為る':
                add(suru, sentence_id, *assign(suru, token, english), japanese, english,
                    token['surface'] + following['surface'], token['checked'])

    # Words the index never lists still get real sentences that contain them verbatim.
    # Only a word's own display spelling, and only when no other word is written the same way.
    homographs = {}
    for word in words:
        if not word['suru']:
            homographs[word['written']] = homographs.get(word['written'], 0) + 1
    wanted = {
        word['written']: word for word in words
        if word['entry'] is not None and not word['suru'] and homographs[word['written']] == 1
        and len(candidates.get(id(word), {})) < corpus_examples.MIN_PER_WORD
        and corpus_examples.text_matchable(word['written'])
    }
    # 気付 followed by kana is 気付く, not the noun 気付.
    verb_stems = {w['written'][:-1] for w in words if w['class'] != 'n' and w['class'] != 'adj-na' and is_kana(w['written'][-1])}
    unindexed = [(i, japanese, corpus.english.get(i)) for i, japanese in corpus.unindexed()]
    for sentence_id, japanese, english in unindexed + list(kftt):
        for spelling, following in corpus_examples.whole_words(japanese):
            word = wanted.get(spelling)
            if word is None or (spelling in verb_stems and is_kana(following)):
                continue
            sense = word['senses'][0][0] if len(word['senses']) == 1 else None
            add(word, sentence_id, sense, corpus_examples.TEXT, japanese, english, spelling, False)

    for word in words:
        numbers = [number for number, _ in word['senses']]
        word['examples'] = corpus_examples.choose(list(candidates.get(id(word), {}).values()), numbers)


def attach_chinese(words, glosses):
    """Sets each word's Chinese per sense and unaligned, and its search terms."""
    homographs = {}
    for word in words:
        if not word['suru']:
            homographs[word['written']] = homographs.get(word['written'], 0) + 1
    for word in words:
        base = word['base'] if word['suru'] else word
        english = [(number, english_glosses(sense)) for number, sense in word['senses']]
        shown, unaligned = glosses.for_word(base['written'], base['reading'], english, homographs.get(base['written']) == 1)
        word['chinese_senses'] = shown
        word['chinese'] = '；'.join(unaligned[:3]) or None
        pivots = [(number, glosses.pivot(items)) for number, items in english if number not in shown]
        word['search_terms'] = chinese.search_terms(shown, unaligned, english, pivots)


def write_database(words, out, meta, convert):
    if os.path.exists(out):
        os.remove(out)
    os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
    db = sqlite3.connect(out)
    db.executescript('''
        PRAGMA journal_mode = OFF;
        PRAGMA page_size = 4096;
        CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL) WITHOUT ROWID;
        CREATE TABLE words (
            id INTEGER PRIMARY KEY,
            written TEXT NOT NULL,
            reading TEXT NOT NULL,
            accents TEXT NOT NULL,
            class TEXT NOT NULL,
            rank INTEGER NOT NULL,
            gloss TEXT,
            chinese TEXT
        );
        CREATE TABLE keys (key TEXT NOT NULL, word_id INTEGER NOT NULL, PRIMARY KEY (key, word_id)) WITHOUT ROWID;
        CREATE TABLE prefixes (
            prefix TEXT NOT NULL,
            position INTEGER NOT NULL,
            word_id INTEGER NOT NULL,
            exact INTEGER NOT NULL,
            PRIMARY KEY (prefix, position)
        ) WITHOUT ROWID;
        CREATE TABLE senses (
            word_id INTEGER NOT NULL,
            number INTEGER NOT NULL,
            gloss TEXT NOT NULL,
            chinese TEXT,
            chinese_source TEXT,
            PRIMARY KEY (word_id, number)
        ) WITHOUT ROWID;
        CREATE TABLE sentences (
            id INTEGER PRIMARY KEY,
            japanese TEXT NOT NULL,
            english TEXT,
            chinese TEXT,
            chinese_via TEXT
        );
        CREATE TABLE examples (
            word_id INTEGER NOT NULL,
            position INTEGER NOT NULL,
            sentence_id INTEGER NOT NULL,
            sense INTEGER,
            basis TEXT NOT NULL,
            form TEXT,
            PRIMARY KEY (word_id, position)
        ) WITHOUT ROWID;
        CREATE TABLE glosses (
            term TEXT NOT NULL,
            word_id INTEGER NOT NULL,
            sense INTEGER,
            tier INTEGER NOT NULL,
            position INTEGER NOT NULL,
            PRIMARY KEY (term, word_id)
        ) WITHOUT ROWID;
        CREATE TABLE t2s (traditional TEXT PRIMARY KEY, simplified TEXT NOT NULL) WITHOUT ROWID;
    ''')
    sentences = {}
    for word_id, word in enumerate(words, start=1):
        db.execute('INSERT INTO words VALUES (?, ?, ?, ?, ?, ?, ?, ?)', (
            word_id, word['written'], word['reading'], ','.join(map(str, word['accents'])),
            word['class'], word['rank'], word['gloss'], word['chinese']))
        for key in sorted({search_key(k) for k in word['keys'] if k}):
            db.execute('INSERT INTO keys VALUES (?, ?)', (key, word_id))
        for number, sense in word['senses']:
            glosses = english_glosses(sense)
            if glosses:
                text, source = word['chinese_senses'].get(number, (None, None))
                db.execute('INSERT INTO senses VALUES (?, ?, ?, ?, ?)', (word_id, number, gloss_text(glosses), text, source))
        db.executemany('INSERT INTO glosses VALUES (?, ?, ?, ?, ?)',
                       [(term, word_id, *rest) for term, *rest in word['search_terms']])
        for position, example in enumerate(word['examples']):
            zh = convert.simplified(example['chinese']) if example['chinese'] else None
            sentences[example['id']] = (example['japanese'], example['english'], zh, example['chinese_via'])
            db.execute('INSERT INTO examples VALUES (?, ?, ?, ?, ?, ?)', (
                word_id, position, example['id'], example['sense'], example['basis'], example['form']))
    db.executemany('INSERT INTO t2s VALUES (?, ?)',
                   sorted((t, s) for t, s in convert.characters.items() if len(t) == 1 and len(s) == 1 and t != s))
    db.executemany('INSERT INTO sentences VALUES (?, ?, ?, ?, ?)',
                   [(sentence_id, *texts) for sentence_id, texts in sorted(sentences.items())])
    ranks = {word_id: word['rank'] for word_id, word in enumerate(words, start=1)}
    for prefix, rows in top_prefixes(db.execute('SELECT key, word_id FROM keys'), ranks):
        db.executemany('INSERT INTO prefixes VALUES (?, ?, ?, ?)',
                       [(prefix, position, word_id, exact) for position, (word_id, exact) in enumerate(rows)])
    meta = dict(meta, schema=str(SCHEMA_VERSION), words=str(len(words)), prefix_top=str(PREFIX_TOP))
    db.executemany('INSERT INTO meta VALUES (?, ?)', sorted(meta.items()))
    db.commit()
    db.execute('VACUUM')
    db.close()


def top_prefixes(keys, ranks):
    """(prefix, [(word_id, exact)]) for every busy prefix, ordered like the app's own
    prefix query: exact matches first, then rank descending, then id."""
    matches = {}
    key_counts = {}
    for key, word_id in keys:
        for length in range(1, min(len(key), PREFIX_MAX_LENGTH) + 1):
            prefix = key[:length]
            key_counts[prefix] = key_counts.get(prefix, 0) + 1
            words = matches.setdefault(prefix, {})
            words[word_id] = words.get(word_id, False) or key == prefix
    for prefix in sorted(matches):
        if key_counts[prefix] <= PREFIX_MIN_KEYS:
            continue
        ordered = sorted(matches[prefix].items(), key=lambda item: (not item[1], -ranks[item[0]], item[0]))
        yield prefix, [(word_id, int(exact)) for word_id, exact in ordered[:PREFIX_TOP]]


def build_from(inputs, out):
    jmdict = JMdict(load_jmdict(inputs['jmdict']))
    words = build(load_accents(inputs['accents']), load_frequencies(inputs['novels']),
                  load_frequencies(inputs['wiki']), jmdict)
    attach_examples(words, corpus_examples.Corpus(**inputs['tatoeba']), corpus_examples.kftt_sentences(inputs['kftt']))
    convert = chinese.Converter(**inputs['opencc'])
    chinese_sentences = (text for _, _, text in corpus_examples._tsv(inputs['tatoeba']['chinese'], 3))
    attach_chinese(words, chinese.Glosses(
        chinese.wiktionary_entries(inputs['wiktionary'], convert), chinese.cedict_entries(inputs['cedict']),
        convert, chinese_sentences))
    write_database(words, out, {
        'jmdict': f'{jmdict.version} {jmdict.date}'.strip(), 'kanjium': inputs['kanjium_version'],
        'tatoeba': inputs['tatoeba_version'], 'kftt': '1.0', 'wiktionary': inputs['wiktionary_version'],
        'cedict': inputs['cedict_version'],
    }, convert)
    print(f'{out}: {len(words)} words, {os.path.getsize(out) / 1e6:.1f} MB', file=sys.stderr)


def pinned_inputs(cache_dir):
    paths = fetch_sources(cache_dir)
    with open(os.path.join(HERE, 'sources.json'), encoding='utf-8') as f:
        commit = re.search(r'/kanjium/([0-9a-f]{40})/', f.read()).group(1)
    return {
        'accents': paths['accents.txt'], 'novels': paths['novels_freq.txt'], 'wiki': paths['wikipedia_freq.txt'],
        'jmdict': paths['jmdict-examples-eng.json.zip'], 'kanjium_version': commit,
        'tatoeba': {name: paths[file] for name, file in TATOEBA_FILES.items()}, 'tatoeba_version': TATOEBA_VERSION,
        'kftt': paths['kftt-data-1.0.tar.gz'],
        'wiktionary': [paths[name] for name in WIKTIONARY_FILES], 'wiktionary_version': WIKTIONARY_VERSION,
        'cedict': paths[CEDICT_FILE], 'cedict_version': CEDICT_VERSION,
        'opencc': {name: paths[file] for name, file in OPENCC_FILES.items()},
    }


def local_inputs(directory):
    return {
        'accents': os.path.join(directory, 'accents.txt'), 'novels': os.path.join(directory, 'novels_freq.txt'),
        'wiki': os.path.join(directory, 'wikipedia_freq.txt'), 'jmdict': os.path.join(directory, 'jmdict.json'),
        'kanjium_version': 'sample',
        'tatoeba': {name: os.path.join(directory, 'tatoeba', file.replace('.tar.bz2', '.csv').replace('.bz2', ''))
                    for name, file in TATOEBA_FILES.items()},
        'tatoeba_version': 'sample',
        'kftt': os.path.join(directory, 'kftt'),
        'wiktionary': [os.path.join(directory, 'chinese', name) for name in WIKTIONARY_FILES],
        'wiktionary_version': 'sample',
        'cedict': os.path.join(directory, 'chinese', CEDICT_FILE.replace('.gz', '')), 'cedict_version': 'sample',
        'opencc': {name: os.path.join(directory, 'chinese', file) for name, file in OPENCC_FILES.items()},
    }


def make_sample(words_file, cache_dir, out_dir):
    """Extracts the source lines for the listed words, so tests run on real data without downloads."""
    inputs = pinned_inputs(cache_dir)
    with open(words_file, encoding='utf-8') as f:
        wanted = {line.split('#')[0].strip() for line in f} - {''}
    rows = [line for line in open(inputs['accents'], encoding='utf-8')
            if (lambda p: len(p) == 3 and (p[0] in wanted or (p[1] or p[0]) in wanted))(line.rstrip('\n').split('\t'))]
    data = load_jmdict(inputs['jmdict'])
    jmdict = JMdict(data)
    entries = {}
    names = set()
    for line in rows:
        written, reading, _ = line.rstrip('\n').split('\t')
        entry = jmdict.match(written, reading or written)
        if entry:
            entries[entry['id']] = entry
            names |= {k['text'] for k in entry['kanji'] + entry['kana']}
        names |= {written, reading}
    os.makedirs(out_dir, exist_ok=True)
    with open(os.path.join(out_dir, 'accents.txt'), 'w', encoding='utf-8') as f:
        f.writelines(rows)
    for name in ('novels', 'wiki'):
        source = inputs[name]
        target = os.path.join(out_dir, os.path.basename(source))
        with open(source, encoding='utf-8') as f, open(target, 'w', encoding='utf-8') as out:
            out.writelines(line for line in f if line.split('\t')[0] in names)
    sense_fields = ('partOfSpeech', 'appliesToKanji', 'appliesToKana', 'misc', 'gloss', 'examples')
    words = [dict(entry, sense=[{k: sense.get(k, []) for k in sense_fields} for sense in entry['sense']])
             for entry in (entries[k] for k in sorted(entries, key=int))]
    with open(os.path.join(out_dir, 'jmdict.json'), 'w', encoding='utf-8') as f:
        f.write(json.dumps({'version': data['version'], 'dictDate': data['dictDate']}, ensure_ascii=False)[:-1])
        f.write(', "words": [\n')
        f.write(',\n'.join(json.dumps(w, ensure_ascii=False, sort_keys=True) for w in words))
        f.write('\n]}\n')
    sentences = sample_corpora(inputs, names, entries.values(), out_dir)
    lines = sample_chinese(inputs, names, entries.values(), out_dir)
    print(f'{out_dir}: {len(rows)} accent rows, {len(entries)} JMdict entries, {sentences} sentences, '
          f'{lines} Chinese source lines', file=sys.stderr)


SAMPLE_PER_WORD = 8


def sample_corpora(inputs, names, entries, out_dir):
    """Writes the Tatoeba and KFTT lines the sample words need, capped per word."""
    paths = inputs['tatoeba']
    japanese = {int(i): line for i, line in ((l.split('\t', 1)[0], l) for l in corpus_examples._lines(paths['japanese']))}
    keep, per_word = set(), {}
    for entry in entries:
        for sense in entry['sense']:
            keep |= {int(e['source']['value']) for e in sense.get('examples', []) if e['source']['type'] == 'tatoeba'}
    index_lines = []
    for line in corpus_examples._lines(paths['indices']):
        sentence_id, _, tokens = line.rstrip('\n').split('\t')
        heads = {t['head'] for t in corpus_examples.parse_tokens(tokens)} & names
        wanted = [h for h in heads if per_word.get(h, 0) < SAMPLE_PER_WORD]
        if int(sentence_id) in keep or wanted:
            for head in wanted:
                per_word[head] = per_word.get(head, 0) + 1
            keep.add(int(sentence_id))
            index_lines.append(line)
    indexed = {int(line.split('\t', 1)[0]) for line in index_lines}
    matchable = {n for n in names if corpus_examples.text_matchable(n)}
    for sentence_id, line in japanese.items():
        if sentence_id in indexed:
            continue
        found = {run for run, _ in corpus_examples.whole_words(line.rstrip('\n').split('\t')[2])} & matchable
        wanted = [n for n in found if per_word.get(('text', n), 0) < 3]
        for n in wanted:
            per_word[('text', n)] = per_word.get(('text', n), 0) + 1
        if wanted:
            keep.add(sentence_id)

    directory = os.path.join(out_dir, 'tatoeba')
    os.makedirs(directory, exist_ok=True)

    def write(name, lines):
        target = name.replace('.tar.bz2', '.csv').replace('.bz2', '')
        with open(os.path.join(directory, target), 'w', encoding='utf-8') as f:
            f.writelines(lines)

    write(TATOEBA_FILES['japanese'], [japanese[i] for i in sorted(keep) if i in japanese])
    write(TATOEBA_FILES['indices'], index_lines)
    linked = {}
    for links_name in ('eng_links', 'cmn_links'):
        links = [l for l in corpus_examples._lines(paths[links_name]) if int(l.split('\t', 1)[0]) in keep]
        linked[links_name] = {int(l.rstrip('\n').split('\t')[1]) for l in links}
        write(TATOEBA_FILES[links_name], links)
    via = [l for l in corpus_examples._lines(paths['cmn_eng_links']) if int(l.rstrip('\n').split('\t')[1]) in linked['eng_links']]
    write(TATOEBA_FILES['cmn_eng_links'], via)
    chinese_ids = linked['cmn_links'] | {int(l.split('\t', 1)[0]) for l in via}
    for sentences_name, ids in (('english', linked['eng_links']), ('chinese', chinese_ids)):
        write(TATOEBA_FILES[sentences_name],
              [l for l in corpus_examples._lines(paths[sentences_name]) if int(l.split('\t', 1)[0]) in ids])

    kftt_dir = os.path.join(out_dir, 'kftt')
    os.makedirs(kftt_dir, exist_ok=True)
    pairs = []
    for _, ja, en in corpus_examples.kftt_sentences(inputs['kftt']):
        found = {run for run, _ in corpus_examples.whole_words(ja)} & matchable
        wanted = [n for n in found if per_word.get(('kftt', n), 0) < 3]
        for n in wanted:
            per_word[('kftt', n)] = per_word.get(('kftt', n), 0) + 1
        if wanted:
            pairs.append((ja, en))
    for part in corpus_examples.KFTT_PARTS:
        for lang, column in (('ja', 0), ('en', 1)):
            with open(os.path.join(kftt_dir, f'kyoto-{part}.{lang}'), 'w', encoding='utf-8') as f:
                f.writelines(pair[column] + '\n' for pair in (pairs if part == 'train' else []))
    return len(keep) + len(pairs)


def sample_chinese(inputs, names, entries, out_dir):
    """Writes the Wiktionary entries, the CC-CEDICT lines and the OpenCC tables the sample words need."""
    directory = os.path.join(out_dir, 'chinese')
    os.makedirs(directory, exist_ok=True)
    convert = chinese.Converter(**inputs['opencc'])
    spellings = names | {n[:-2] for n in names if n.endswith('する')}
    count = 0
    for source, name in zip(inputs['wiktionary'], WIKTIONARY_FILES):
        kept = []
        for line in corpus_examples._lines(source):
            data = json.loads(line)
            alternatives = {f['form'] for f in data.get('forms', []) if {'alternative', 'kanji'} <= set(f.get('tags') or [])}
            if data['word'] not in spellings and not alternatives & spellings:
                continue
            data = {key: data[key] for key in ('word', 'lang_code', 'pos', 'senses', 'sounds', 'forms') if key in data}
            data['senses'] = [{k: v for k, v in sense.items() if k in ('glosses', 'tags')} for sense in data['senses']]
            data['sounds'] = [{'other': s['other']} for s in data.get('sounds', []) if s.get('other')]
            data['forms'] = [f for f in data.get('forms', []) if {'canonical', 'alternative'} & set(f.get('tags') or [])]
            kept.append(json.dumps(data, ensure_ascii=False, sort_keys=True) + '\n')
        with open(os.path.join(directory, name), 'w', encoding='utf-8') as f:
            f.writelines(kept)
        count += len(kept)
    # Run the real lookups over the full CC-CEDICT and keep only the lines they consulted.
    sample = local_inputs(out_dir)
    jmdict = JMdict(load_jmdict(sample['jmdict']))
    words = build(load_accents(sample['accents']), load_frequencies(sample['novels']), load_frequencies(sample['wiki']), jmdict)
    for word in words:
        word['examples'] = []
    cmn = (text for _, _, text in corpus_examples._tsv(inputs['tatoeba']['chinese'], 3))
    glosses = chinese.Glosses(chinese.wiktionary_entries(sample['wiktionary'], convert),
                              chinese.cedict_entries(inputs['cedict']), convert, cmn)
    glosses.used = set()
    attach_chinese(words, glosses)
    with gzip.open(inputs['cedict'], 'rt', encoding='utf-8') as f, \
            open(os.path.join(directory, CEDICT_FILE.replace('.gz', '')), 'w', encoding='utf-8') as out:
        for line in f:
            m = chinese.CEDICT_LINE.match(line)
            if m and not line.startswith('#') and m.group(2) in glosses.used:
                out.write(line)
                count += 1
    for name, file in OPENCC_FILES.items():
        with open(inputs['opencc'][name], encoding='utf-8') as f, open(os.path.join(directory, file), 'w', encoding='utf-8') as out:
            out.write(f.read())
    return count


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--out', help='SQLite file to write')
    parser.add_argument('--inputs', help='directory with accents.txt, novels_freq.txt, wikipedia_freq.txt, jmdict.json')
    parser.add_argument('--cache', default=os.path.join(HERE, '.cache'), help='download cache for the pinned sources')
    parser.add_argument('--make-sample', metavar='WORDS_FILE', help='extract sample inputs for the listed words')
    parser.add_argument('--sample-dir', default=os.path.join(HERE, 'sample'))
    args = parser.parse_args()
    if args.make_sample:
        make_sample(args.make_sample, args.cache, args.sample_dir)
    elif args.out:
        build_from(local_inputs(args.inputs) if args.inputs else pinned_inputs(args.cache), args.out)
    else:
        parser.error('nothing to do: pass --out or --make-sample')


if __name__ == '__main__':
    main()
