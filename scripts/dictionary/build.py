#!/usr/bin/env python3
"""Builds the offline dictionary (SQLite) from pinned Kanjium + JMdict sources.

    python3 scripts/dictionary/build.py --out App/Generated/Dictionary.sqlite
    python3 scripts/dictionary/build.py --inputs scripts/dictionary/sample --out sample.sqlite
    python3 scripts/dictionary/build.py --make-sample scripts/dictionary/sample-words.txt

The schema and key normalization must stay in sync with
Packages/OJADKit/Sources/OJADKit/OfflineDictionary.swift and Kana.swift.
"""

import argparse
import hashlib
import io
import json
import math
import os
import re
import sqlite3
import sys
import unicodedata
import urllib.request
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
SCHEMA_VERSION = 1
MAX_EXAMPLES = 6

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


def fetch_sources(cache_dir):
    with open(os.path.join(HERE, 'sources.json'), encoding='utf-8') as f:
        sources = json.load(f)
    os.makedirs(cache_dir, exist_ok=True)
    paths = {}
    for group in sources.values():
        for name, spec in group['files'].items():
            path = os.path.join(cache_dir, name)
            if not os.path.exists(path) or sha256(path) != spec['sha256']:
                print(f'downloading {spec["url"]}', file=sys.stderr)
                request = urllib.request.Request(spec['url'], headers={'User-Agent': 'OJAD-dictionary-build'})
                with urllib.request.urlopen(request) as response, open(path + '.part', 'wb') as out:
                    out.write(response.read())
                os.replace(path + '.part', path)
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


def short_gloss(senses):
    for sense in senses:
        glosses = [g['text'] for g in sense['gloss'] if g.get('lang', 'eng') == 'eng']
        if glosses:
            text = '; '.join(glosses[:3])
            return text if len(text) <= 80 else text[:79] + '…'
    return None


def examples_of(entry):
    out = []
    seen = set()
    for sense in entry['sense']:
        for example in sense.get('examples', []):
            if example['source']['type'] != 'tatoeba':
                continue
            sentence_id = int(example['source']['value'])
            texts = {s['lang']: s['text'] for s in example['sentences']}
            if sentence_id in seen or 'jpn' not in texts:
                continue
            seen.add(sentence_id)
            out.append((sentence_id, texts['jpn'], texts.get('eng'), example['text']))
    return out[:MAX_EXAMPLES]


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
        words.append({
            'written': written, 'reading': reading, 'accents': group['accents'], 'class': cls, 'rank': rank,
            'gloss': short_gloss(senses), 'keys': group['spellings'] + [written],
            'examples': examples_of(entry) if entry else [],
        })
        takes_suru = any('vs' in s['partOfSpeech'] for s in senses)
        if takes_suru and cls in ('n', 'adj-na') and not reading.endswith('する'):
            suru_glosses = [s for s in senses if 'vs' in s['partOfSpeech']]
            words.append({
                'written': written + 'する', 'reading': reading + 'する', 'accents': group['accents'], 'class': 'vs-i',
                'rank': rank - 1, 'gloss': short_gloss(suru_glosses), 'keys': [s + 'する' for s in group['spellings']],
                'examples': [],
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


def write_database(words, out, meta):
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
            gloss TEXT
        );
        CREATE TABLE keys (key TEXT NOT NULL, word_id INTEGER NOT NULL, PRIMARY KEY (key, word_id)) WITHOUT ROWID;
        CREATE TABLE examples (
            word_id INTEGER NOT NULL,
            position INTEGER NOT NULL,
            tatoeba_id INTEGER NOT NULL,
            japanese TEXT NOT NULL,
            english TEXT,
            form TEXT,
            PRIMARY KEY (word_id, position)
        ) WITHOUT ROWID;
    ''')
    for word_id, word in enumerate(words, start=1):
        db.execute('INSERT INTO words VALUES (?, ?, ?, ?, ?, ?, ?)', (
            word_id, word['written'], word['reading'], ','.join(map(str, word['accents'])),
            word['class'], word['rank'], word['gloss']))
        for key in sorted({search_key(k) for k in word['keys'] if k}):
            db.execute('INSERT INTO keys VALUES (?, ?)', (key, word_id))
        for position, (sentence_id, japanese, english, form) in enumerate(word['examples']):
            db.execute('INSERT INTO examples VALUES (?, ?, ?, ?, ?, ?)',
                       (word_id, position, sentence_id, japanese, english, form))
    meta = dict(meta, schema=str(SCHEMA_VERSION), words=str(len(words)))
    db.executemany('INSERT INTO meta VALUES (?, ?)', sorted(meta.items()))
    db.commit()
    db.execute('VACUUM')
    db.close()


def build_from(inputs, out):
    jmdict = JMdict(load_jmdict(inputs['jmdict']))
    words = build(load_accents(inputs['accents']), load_frequencies(inputs['novels']),
                  load_frequencies(inputs['wiki']), jmdict)
    write_database(words, out, {'jmdict': f'{jmdict.version} {jmdict.date}'.strip(), 'kanjium': inputs['kanjium_version']})
    print(f'{out}: {len(words)} words, {os.path.getsize(out) / 1e6:.1f} MB', file=sys.stderr)


def pinned_inputs(cache_dir):
    paths = fetch_sources(cache_dir)
    with open(os.path.join(HERE, 'sources.json'), encoding='utf-8') as f:
        commit = re.search(r'/kanjium/([0-9a-f]{40})/', f.read()).group(1)
    return {
        'accents': paths['accents.txt'], 'novels': paths['novels_freq.txt'], 'wiki': paths['wikipedia_freq.txt'],
        'jmdict': paths['jmdict-examples-eng.json.zip'], 'kanjium_version': commit,
    }


def local_inputs(directory):
    return {
        'accents': os.path.join(directory, 'accents.txt'), 'novels': os.path.join(directory, 'novels_freq.txt'),
        'wiki': os.path.join(directory, 'wikipedia_freq.txt'), 'jmdict': os.path.join(directory, 'jmdict.json'),
        'kanjium_version': 'sample',
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
    print(f'{out_dir}: {len(rows)} accent rows, {len(entries)} JMdict entries', file=sys.stderr)


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
