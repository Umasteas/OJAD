"""Simplified Chinese for JMdict senses, and the Chinese/English -> word search index.

Every Chinese string comes from a pinned source; nothing here translates:
- Chinese Wiktionary's Japanese entries (kaikki.org's wiktextract output): Chinese
  definitions written for Japanese words. Its older bulk-imported entries are a single
  text block, "詞【よみ】 / 品詞 / 1. 释义 / example…", and are parsed as such.
- CC-CEDICT: Chinese words spelt like the Japanese one (衝突 -> 冲突) whose English
  definition shares a content word with the JMdict sense, which keeps out false
  friends such as 勉強 / 勉强 ("reluctantly"). Chinese words whose English definition
  equals a JMdict gloss are only used to rank search, never shown.
- OpenCC: Traditional -> Simplified, and Japanese shinjitai -> Traditional.
"""

import gzip
import json
import re

import examples as corpus_examples

WIKTIONARY, CEDICT = 'wiktionary', 'cedict'
# Search tiers, strongest first: a shown Chinese gloss, a JMdict English gloss, a CC-CEDICT
# word whose English equals a JMdict gloss (searchable, not shown).
TIER_CHINESE, TIER_ENGLISH, TIER_PIVOT = 0, 1, 2
PIVOT_PER_SENSE = 3
ENGLISH_ITEMS_PER_SENSE = 4
MAX_GLOSS = 40
MAX_TERM = 12
SKIPPED_POS = {'soft-redirect', 'romanization', 'character', 'syllable', 'name'}
SKIPPED_TAGS = {'no-gloss', 'form-of', 'alt-of'}
HAN = re.compile(r'[\u3400-\u9fff\uf900-\ufaff]')
KANA = re.compile(r'[\u3040-\u30ff]')
LEGACY_HEAD = re.compile(r'^(.+?)【(.+?)】')
# A part of speech such as 「名·他サ」 or 「自五」, alone or before the definition on the same line.
LEGACY_POS = re.compile(r'^(?=[^\s]*[·・•?？サ五一])[名动動形副自他サ变變·・•?？一二上下五段连連体體助词詞感叹嘆接续續代数數量头頭尾词缀綴]+(?:\s+|$)'
                        r'|^(?:名|副|代|感|连体|連體|接续|接續|自动|自動|他动|他動|形动|形動)(?:\s+|$)')
# Unexpanded label templates left in some glosses: ':Template:音乐 休止符'.
TEMPLATE_LABEL = re.compile(r':?Template:(转|音乐|数|计算机|轉|音樂|數|計算機)\s?')
# The same, only when a definition follows on the line (「一下」 alone is a definition).
POS_PREFIX = re.compile(LEGACY_POS.pattern.replace(r'(?:\s+|$)', r'\s+(?=\S)'))
RUBY = re.compile(r'[(（][\u3040-\u30ff]+[)）]')
SPELLING_PREFIX = re.compile(r'^【([^】]+)】\s*')
HEADING = re.compile(r'==+[^=]*==+')
NUMBERED = re.compile(r'^\d+[.．]\s*')
ITEM_SPLIT = re.compile(r'[，,；;、]')
BRACKETS = re.compile(r'[（(〈<【\[][^）)〉>】\]]*[）)〉>】\]]')


# ---------- OpenCC ----------

def _opencc(path):
    for line in corpus_examples._lines(path):
        if line.strip() and not line.startswith('#'):
            source, targets = line.rstrip('\n').split('\t')
            yield source, targets.split(' ')


class Converter:
    def __init__(self, ts_characters, ts_phrases, jp_shinjitai):
        self.characters = {s: t[0] for s, t in _opencc(ts_characters)}
        self.table = dict(self.characters)
        self.table.update({s: t[0] for s, t in _opencc(ts_phrases)})
        self.longest = max(map(len, self.table))
        self.shinjitai = {}
        for traditional, shinjitai in _opencc(jp_shinjitai):
            for s in shinjitai:
                if s != traditional:
                    self.shinjitai.setdefault(s, traditional)

    def simplified(self, text):
        out, i = [], 0
        while i < len(text):
            for n in range(min(self.longest, len(text) - i), 0, -1):
                if text[i:i + n] in self.table:
                    out.append(self.table[text[i:i + n]])
                    i += n
                    break
            else:
                out.append(text[i])
                i += 1
        return ''.join(out)

    def from_japanese(self, text):
        return self.simplified(''.join(self.shinjitai.get(c, c) for c in text))


# ---------- readings ----------

VOWELS = {}
for _row, _vowel in zip(('あかさたなはまやらわがざだばぱぁゃ', 'いきしちにひみりぎじぢびぴぃ', 'うくすつぬふむゆるぐずづぶぷぅゅ',
                         'えけせてねへめれげぜでべぺぇ', 'おこそとのほもよろをごぞどぼぽぉょ'), 'あいうえお'):
    for _c in _row:
        VOWELS[_c] = _vowel


def pronunciation(kana):
    """Collapses spelling and pronunciation of long vowels, so Wiktionary's Tokyo
    pronunciation がっこー or えーが matches the readings がっこう and えいが."""
    hira = ''.join(chr(ord(c) - 0x60) if 'ァ' <= c <= 'ヶ' else c for c in kana)
    out = []
    for c in hira:
        vowel = VOWELS.get(out[-1]) if out else None
        if c == 'ー' and vowel:
            c = vowel
        elif (c == 'い' and vowel == 'え') or (c == 'う' and vowel == 'お'):
            c = vowel
        out.append(c)
    return ''.join(out)


def _ruby_reading(form):
    text, ruby = form['form'], form.get('ruby') or []
    out = text
    for base, kana in ruby:
        out = out.replace(base, kana, 1)
    return out if not HAN.search(out) else None


# ---------- Wiktionary ----------

def clean_gloss(text, convert):
    text = TEMPLATE_LABEL.sub('', HEADING.sub('', text)).replace('[', '').replace(']', '')
    text = convert.simplified(POS_PREFIX.sub('', text.strip())).rstrip('。.')
    if not text or len(text) > MAX_GLOSS or '==' in text or 'Template' in text or not HAN.search(text):
        return None
    # A reading written as ruby, 「诘(きつ)问(もん)」, rather than a definition.
    if RUBY.search(text):
        return None
    if len(KANA.findall(text)) * 3 > len(text):
        return None
    return text


def _legacy(block, convert):
    """(reading or None, glosses) from an old text block: 「詞【よみ】」, an optional part of
    speech, numbered or single definitions, then Japanese examples with their translations."""
    lines = [line.strip() for line in block.split('\n') if line.strip()]
    head = LEGACY_HEAD.match(lines[0]) if lines else None
    rest = lines[1:] if head else lines
    if rest:
        rest[0] = LEGACY_POS.sub('', rest[0])
        rest = [line for line in rest if line]
    numbered = [NUMBERED.sub('', line) for line in rest if NUMBERED.match(line)]
    glosses = numbered or rest[:1]
    reading = head.group(2) if head else None
    return reading, [g for g in (clean_gloss(g, convert) for g in glosses if not KANA.search(g)) if g]


def wiktionary_entries(paths, convert):
    """written -> [(pronunciations, [simplified glosses])]."""
    entries = {}
    for path in paths:
        for line in corpus_examples._lines(path):
            data = json.loads(line)
            if data.get('lang_code') != 'ja' or data.get('pos') in SKIPPED_POS:
                continue
            readings, glosses, by_spelling = set(), [], {}
            if data.get('pos') == 'unknown':
                block = '\n'.join(s['glosses'][0] for s in data.get('senses', []) if s.get('glosses'))
                reading, glosses = _legacy(block, convert)
                if reading and not HAN.search(reading):
                    readings.add(pronunciation(reading))
            else:
                for sense in data.get('senses', []):
                    if sense.get('glosses') and not SKIPPED_TAGS & set(sense.get('tags') or []):
                        spellings, text = _spelling_prefix(sense['glosses'][-1])
                        gloss = clean_gloss(text, convert)
                        if gloss:
                            glosses.append(gloss)
                            if spellings is not None:
                                by_spelling.setdefault(gloss, spellings)
                for sound in data.get('sounds', []):
                    if sound.get('other') and not HAN.search(sound['other']):
                        readings.add(pronunciation(sound['other']))
                for form in data.get('forms', []):
                    if 'canonical' in (form.get('tags') or []):
                        reading = _ruby_reading(form)
                        if reading:
                            readings.add(pronunciation(reading))
            if not HAN.search(data['word']):
                readings.add(pronunciation(data['word']))
            if glosses:
                glosses = list(dict.fromkeys(glosses))
                entries.setdefault(data['word'], []).append((readings, glosses))
                # A kana page lists the kanji it is written with (みる: 見る, 観る, 診る…) and may
                # mark glosses that belong to only some of them (【診る】 诊断).
                if not HAN.search(data['word']):
                    for form in data.get('forms', []):
                        if {'alternative', 'kanji'} <= set(form.get('tags') or []):
                            spelling = form['form']
                            own = [g for g in glosses if spelling in by_spelling.get(g, (spelling,))]
                            if own:
                                entries.setdefault(spelling, []).append(({pronunciation(data['word'])}, own))
    return entries


def _spelling_prefix(gloss):
    """'【見る、視る】 看，观看。' -> (('見る', '視る'), '看，观看。'); (None, gloss) without one."""
    m = SPELLING_PREFIX.match(gloss)
    if not m:
        return None, gloss
    return tuple(s for s in re.split(r'[、,，・]', m.group(1)) if s), gloss[m.end():]


# ---------- CC-CEDICT ----------

CEDICT_LINE = re.compile(r'^(\S+) (\S+) \[[^\]]*\] /(.*)/\s*$')
CEDICT_SKIP = ('variant of', 'old variant', 'see ', 'surname ', 'CL:', 'abbr. for', 'used in', 'Taiwan pr.')


def cedict_entries(path):
    """[(simplified, [English definitions])]."""
    out = []
    opener = gzip.open if path.endswith('.gz') else open
    with opener(path, 'rt', encoding='utf-8') as f:
        for line in f:
            m = CEDICT_LINE.match(line)
            if not m or line.startswith('#'):
                continue
            definitions = [d for d in m.group(3).split('/') if d and not d.startswith(CEDICT_SKIP)]
            if definitions:
                out.append((m.group(2), definitions))
    return out


def english_items(gloss):
    """'to eat (with chopsticks)' -> 'eat'; the normalized form used as a search term."""
    text = gloss.lower()
    while '(' in text:
        text, n = re.subn(r'\([^()]*\)', ' ', text)
        if not n:
            break
    text = re.sub(r"^\s*(to|a|an|the)\s+", '', text)
    return ' '.join(re.sub(r"[^a-z0-9' -]", ' ', text).split())


def chinese_items(gloss):
    """'吃喝，饮食（古）' -> ['吃喝', '饮食']."""
    items = []
    for item in ITEM_SPLIT.split(BRACKETS.sub('', gloss)):
        item = item.strip(' 　.。')
        if item and len(item) <= MAX_TERM and HAN.search(item) and not KANA.search(item):
            items.append(item)
    return items


class Glosses:
    def __init__(self, wiktionary, cedict, convert, chinese_sentences=()):
        self.wiktionary = wiktionary
        self.convert = convert
        self.by_written = {}
        self.english_of = {}
        self.by_definition = {}
        for simplified, definitions in cedict:
            self.by_written.setdefault(simplified, []).append(definitions)
            vocabulary = self.english_of.setdefault(simplified, set())
            for definition in definitions:
                vocabulary |= corpus_examples.content_words(definition)
                for item in definition.split(';'):
                    key = english_items(item)
                    if key:
                        self.by_definition.setdefault(key, set()).add(simplified)
        self.longest = max((len(w) for w in self.english_of), default=1)
        # CC-CEDICT words a build consulted, when set (to cut the test sample down to them).
        self.used = None
        # How often a candidate word occurs in Tatoeba's Chinese sentences, to rank search-only words.
        self.frequency = {}
        for sentence in chinese_sentences:
            sentence = convert.simplified(sentence)
            for start in range(len(sentence)):
                for n in range(1, min(4, len(sentence) - start) + 1):
                    piece = sentence[start:start + n]
                    if piece in self.english_of:
                        self.frequency[piece] = self.frequency.get(piece, 0) + 1

    def _english_of_chinese(self, gloss):
        found = []
        for item in chinese_items(gloss) or [gloss]:
            if item in self.english_of:
                found.append(item)
                continue
            i = 0
            while i < len(item):
                for n in range(min(self.longest, len(item) - i), 1, -1):
                    if item[i:i + n] in self.english_of:
                        found.append(item[i:i + n])
                        i += n
                        break
                else:
                    i += 1
        if self.used is not None:
            self.used.update(found)
        return set().union(*(self.english_of[w] for w in found)) if found else set()

    def wiktionary_glosses(self, written, reading, unique):
        candidates = self.wiktionary.get(written, [])
        key = pronunciation(reading)
        matched = [glosses for readings, glosses in candidates if key in readings]
        if not matched and unique:
            matched = [glosses for _, glosses in candidates]
        return list(dict.fromkeys(g for glosses in matched for g in glosses))

    def for_word(self, written, reading, senses, unique):
        """senses: [(number, [English glosses])]. Returns ({number: (text, source)}, [unaligned glosses])."""
        vocabularies = {n: set().union(*(corpus_examples.content_words(g) for g in glosses)) if glosses else set()
                        for n, glosses in senses}
        per_sense, unaligned = {}, []
        glosses = self.wiktionary_glosses(written, reading, unique)
        for gloss in glosses:
            if len(senses) == 1:
                per_sense.setdefault(senses[0][0], []).append(gloss)
                continue
            words = self._english_of_chinese(gloss)
            scores = sorted(((len(words & v), n) for n, v in vocabularies.items()), reverse=True)
            if scores and scores[0][0] > 0 and (len(scores) == 1 or scores[0][0] > scores[1][0]):
                per_sense.setdefault(scores[0][1], []).append(gloss)
            else:
                unaligned.append(gloss)
        shown = {n: ('；'.join(distinct(g)[:3]), WIKTIONARY) for n, g in per_sense.items()}
        if HAN.search(written):
            cognate = self.convert.from_japanese(written)
            for number, english in senses:
                if number in shown:
                    continue
                if self.used is not None and cognate in self.by_written:
                    self.used.add(cognate)
                for definitions in self.by_written.get(cognate, []):
                    if len(written) > 1:
                        agrees = vocabularies[number] & set().union(*(corpus_examples.content_words(d) for d in definitions))
                    else:
                        # CC-CEDICT lists so many meanings for one character that some English always
                        # overlaps; it must list the sense's first gloss itself (水: water).
                        items = {english_items(i) for d in definitions for i in d.split(';')}
                        agrees = bool(english) and english_items(english[0]) in items
                    if agrees:
                        shown[number] = (cognate, CEDICT)
                        break
        return shown, distinct(unaligned)

    def pivot(self, english_glosses):
        """Search-only Chinese words whose CC-CEDICT definition equals one of the English glosses."""
        hits = {}
        for gloss in english_glosses:
            for word in self.by_definition.get(english_items(gloss), ()):
                hits[word] = hits.get(word, 0) + 1
        ranked = sorted(hits, key=lambda w: (-hits[w], -self.frequency.get(w, 0), w))
        chosen = [w for w in ranked if self.frequency.get(w, 0) > 0][:PIVOT_PER_SENSE]
        if self.used is not None:
            self.used.update(chosen)
        return chosen


def distinct(glosses):
    """Drops glosses whose items an earlier gloss already lists (「开放，坦率」 after 「直率，开放，坦率」)."""
    seen, out = set(), []
    for gloss in glosses:
        items = set(chinese_items(gloss)) or {gloss}
        if not items <= seen:
            out.append(gloss)
            seen |= items
    return out


def search_terms(sense_chinese, word_chinese, sense_english, pivots):
    """[(term, sense, tier, position)] for one word, position being the term's place in its
    sense's list (0 = the sense's first meaning); the strongest tier wins when terms repeat."""
    terms = {}

    def add(items, sense, tier):
        for position, term in enumerate(items):
            if term and (term not in terms or tier < terms[term][1]):
                terms[term] = (sense, tier, position)

    for number, (text, _) in sense_chinese.items():
        add(chinese_items(text), number, TIER_CHINESE)
    add([item for gloss in word_chinese for item in chinese_items(gloss)], None, TIER_CHINESE)
    for number, glosses in sense_english:
        add([english_items(g) for g in glosses[:ENGLISH_ITEMS_PER_SENSE]], number, TIER_ENGLISH)
    for number, words in pivots:
        add(words, number, TIER_PIVOT)
    return [(term, *value) for term, value in sorted(terms.items())]
