"""Per-sense example sentences from pinned Tatoeba and KFTT snapshots.

Tatoeba's Japanese index (the former Tanaka Corpus "B lines") lists every
dictionary word of a sentence as `headword(reading)[sense]{surface}~`, where
`[sense]` is the 1-based JMdict sense number and `~` marks a checked example.
Words the index never lists fall back to sentences that contain them verbatim,
from Tatoeba's unindexed sentences and then from the Kyoto Free Translation Task
(Wikipedia articles with NICT's English translations). Every Japanese sentence
comes from a corpus; nothing here writes Japanese.
"""

import bz2
import io
import os
import re
import tarfile

# How an example was tied to its word and sense, strongest first. The app labels the weaker ones.
#   tagged/jmdict: the corpus or JMdict names the sense; single: the word has one sense;
#   gloss: sense guessed from the English translation; unassigned: indexed word, sense unknown;
#   text: an unindexed sentence that merely contains the spelling (sense only if the word has one).
TAGGED, JMDICT, SINGLE, GLOSS, UNASSIGNED, TEXT = 'tagged', 'jmdict', 'single', 'gloss', 'unassigned', 'text'
BASES = (TAGGED, JMDICT, SINGLE, GLOSS, UNASSIGNED, TEXT)
TEXT_MATCH_LENGTHS = range(2, 9)
MIN_PER_WORD = 2
PER_SENSE = 2
MAX_PER_WORD = 10
MAX_LENGTH = 60
KFTT_ID_BASE = 1_000_000_000
KFTT_PARTS = ('train', 'dev', 'tune', 'test')

TOKEN = re.compile(r'^(?P<head>[^(\[{~|]+)(?:\((?P<reading>[^)]+)\))?(?:\[(?P<sense>\d+)\])?(?:\{(?P<surface>[^}]+)\})?(?P<checked>~)?$')
WORD = re.compile(r"[a-z]+(?:'[a-z]+)?")
STOPWORDS = set('''
a an the to of in on at by for with from as into onto up down out off over about be is are was were been being
do does did have has had it its this that these those one someone something sb sth oneself etc or and not no
e g i e very much more most some any all such so than then there their they them he she his her you your we our
'''.split())


def parse_tokens(line):
    tokens = []
    for raw in line.split():
        m = TOKEN.match(raw)
        if not m:
            continue
        tokens.append({
            'head': m['head'], 'reading': m['reading'], 'sense': int(m['sense']) if m['sense'] else None,
            'surface': m['surface'] or m['head'], 'checked': bool(m['checked']),
        })
    return tokens


def _lines(path):
    if path.endswith('.tar.bz2'):
        with tarfile.open(path, 'r:bz2') as tar:
            member = next(m for m in tar.getmembers() if m.isfile())
            yield from io.TextIOWrapper(tar.extractfile(member), encoding='utf-8')
    elif path.endswith('.bz2'):
        with bz2.open(path, 'rt', encoding='utf-8') as f:
            yield from f
    else:
        with open(path, encoding='utf-8') as f:
            yield from f


def _tsv(path, columns):
    for line in _lines(path):
        parts = line.rstrip('\n').split('\t')
        if len(parts) >= columns:
            yield parts


class Corpus:
    """Japanese sentences with their index tokens and English/Chinese translations."""

    def __init__(self, japanese, indices, eng_links, english, cmn_links, chinese):
        self.japanese = {int(i): text for i, _, text in _tsv(japanese, 3)}
        self.tokens = {}
        for sentence_id, _, line in _tsv(indices, 3):
            sentence_id = int(sentence_id)
            if sentence_id in self.japanese:
                self.tokens[sentence_id] = parse_tokens(line)
        self.english = self._translations(eng_links, english)
        self.chinese = self._translations(cmn_links, chinese)

    def _translations(self, links_path, sentences_path):
        links = {}
        for jpn, other in _tsv(links_path, 2):
            jpn = int(jpn)
            if jpn in self.japanese:
                links.setdefault(jpn, []).append(int(other))
        wanted = {i for ids in links.values() for i in ids}
        texts = {int(i): text for i, _, text in _tsv(sentences_path, 3) if int(i) in wanted}
        # Lowest id first: the oldest translation is usually the reviewed one.
        return {jpn: next((texts[i] for i in sorted(ids) if i in texts), None) for jpn, ids in links.items()}

    def unindexed(self):
        return ((i, text) for i, text in self.japanese.items() if i not in self.tokens)


def _script(c):
    if not c:
        return None
    if '\u4e00' <= c <= '\u9fff' or c == '々':
        return 'kanji'
    if 'ァ' <= c <= 'ヺ' or c == 'ー':
        return 'katakana'
    return None


def text_matchable(spelling):
    """Spellings distinctive enough to find verbatim: all-kanji words of two or more
    characters, or katakana words of three or more. Kana tails (話し, 彼の) are left
    out, since they mostly match inflections of other words."""
    if len(spelling) not in TEXT_MATCH_LENGTHS:
        return False
    scripts = {_script(c) for c in spelling}
    return scripts == {'kanji'} or (scripts == {'katakana'} and len(spelling) >= 3)


def whole_words(text):
    """(run, next character) for every run that could be a whole word: neighbours must
    not continue the same script, so 時間 is not found in 一時間 nor ニュー in ニューヨーク."""
    for length in TEXT_MATCH_LENGTHS:
        for start in range(len(text) - length + 1):
            script = _script(text[start])
            before = text[start - 1] if start else ''
            following = text[start + length] if start + length < len(text) else ''
            if script is not None and _script(before) != script and _script(following) != script:
                yield text[start:start + length], following


def kftt_sentences(path):
    """(id, japanese, english) for KFTT's short, self-contained sentences. Ids follow
    the line order of the original files from KFTT_ID_BASE, so they are stable."""
    def read(part, lang):
        name = f'kyoto-{part}.{lang}'
        if os.path.isdir(path):
            with open(os.path.join(path, name), encoding='utf-8') as f:
                return f.read().splitlines()
        with tarfile.open(path, 'r:gz') as tar:
            return tar.extractfile(f'kftt-data-1.0/data/orig/{name}').read().decode('utf-8').splitlines()

    number = KFTT_ID_BASE
    for part in KFTT_PARTS:
        japanese, english = read(part, 'ja'), read(part, 'en')
        for ja, en in zip(japanese, english):
            ja, en = ja.strip(), en.strip()
            if 8 <= len(ja) <= MAX_LENGTH and ja.endswith('。') and en and not re.search(r'[()（）『』「」]', ja):
                yield number, ja, en
            number += 1


def content_words(text):
    return {stem(w) for w in WORD.findall(text.lower()) if w not in STOPWORDS and len(w) > 1}


def stem(word):
    for suffix in ('ing', 'ed', 'es', 's', 'ly'):
        if word.endswith(suffix) and len(word) - len(suffix) >= 3:
            return word[:-len(suffix)]
    return word


def gloss_sense(english, senses):
    """1-based sense whose glosses share the most content words with the English
    translation, or None when no sense or several senses tie."""
    if not english:
        return None
    words = content_words(english)
    scores = []
    for number, glosses in senses:
        vocabulary = set().union(*(content_words(g) for g in glosses)) if glosses else set()
        scores.append((len(words & vocabulary), number))
    scores.sort(reverse=True)
    if not scores or scores[0][0] == 0 or (len(scores) > 1 and scores[1][0] > 0):
        return None
    return scores[0][1]


def choose(candidates, sense_numbers):
    """Picks up to MAX_PER_WORD examples: every sense gets one before any gets a
    second (PER_SENSE at most), then unassigned sentences top the word up to MIN_PER_WORD.

    candidates: dicts with id, sense (or None), basis, japanese, english, chinese, checked.
    """
    def quality(c):
        strength = BASES.index(c['basis'])
        return (strength, c['id'] >= KFTT_ID_BASE, not c['checked'], c['english'] is None, c['chinese'] is None,
                abs(len(c['japanese']) - 18), c['id'])

    by_sense = {}
    for c in sorted(candidates, key=quality):
        by_sense.setdefault(c['sense'], []).append(c)
    chosen, used = [], set()
    for round_ in range(PER_SENSE):
        for number in sense_numbers:
            pool = [c for c in by_sense.get(number, []) if c['id'] not in used]
            if pool and len(chosen) < MAX_PER_WORD:
                chosen.append(pool[0])
                used.add(pool[0]['id'])
    for c in by_sense.get(None, []):
        if len(chosen) >= MIN_PER_WORD:
            break
        if c['id'] not in used:
            chosen.append(c)
            used.add(c['id'])
    order = {number: i for i, number in enumerate(sense_numbers)}
    chosen.sort(key=lambda c: (order.get(c['sense'], len(order)), quality(c)))
    return chosen
