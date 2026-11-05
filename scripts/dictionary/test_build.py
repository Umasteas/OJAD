"""python3 -m unittest discover -s scripts/dictionary -p 'test_*.py'"""

import os
import sqlite3
import tempfile
import unittest

import build
import chinese
import examples

ROOT = os.path.dirname(os.path.dirname(build.HERE))
SAMPLE_DB = os.path.join(ROOT, 'Packages/OJADKit/Tests/OJADKitTests/Fixtures/sample-dictionary.sqlite')


def dump(path):
    db = sqlite3.connect(path)
    try:
        return list(db.iterdump())
    finally:
        db.close()


class SampleDictionaryTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()
        cls.path = os.path.join(cls.tmp.name, 'sample.sqlite')
        build.build_from(build.local_inputs(os.path.join(build.HERE, 'sample')), cls.path)
        cls.db = sqlite3.connect(cls.path)

    @classmethod
    def tearDownClass(cls):
        cls.db.close()
        cls.tmp.cleanup()

    def word(self, written, reading):
        return self.db.execute(
            'SELECT accents, class FROM words WHERE written = ? AND reading = ?', (written, reading)).fetchall()

    def test_committed_sample_matches_a_fresh_build(self):
        self.assertEqual(dump(SAMPLE_DB), dump(self.path),
                         'Rebuild it: python3 scripts/dictionary/build.py --inputs scripts/dictionary/sample '
                         '--out Packages/OJADKit/Tests/OJADKitTests/Fixtures/sample-dictionary.sqlite')

    def test_accent_and_conjugation_class(self):
        self.assertEqual(self.word('食べる', 'たべる'), [('2', 'v1')])
        self.assertEqual(self.word('飲む', 'のむ'), [('1', 'v5m')])
        self.assertEqual(self.word('行く', 'いく'), [('0', 'v5k-s')])
        self.assertEqual(self.word('来る', 'くる'), [('1', 'vk')])
        self.assertEqual(self.word('高い', 'たかい'), [('2', 'adj-i')])
        self.assertEqual(self.word('静か', 'しずか'), [('1', 'adj-na')])
        self.assertEqual(self.word('学校', 'がっこう'), [('0', 'n')])

    def test_usually_kana_words_are_shown_in_kana(self):
        self.assertIn(('0', 'vs-i'), self.word('する', 'する'))
        self.assertIn(('1', 'adj-ix'), self.word('いい', 'いい'))

    def test_suru_verbs_are_generated_from_nouns(self):
        self.assertEqual(self.word('勉強する', 'べんきょうする'), [('0', 'vs-i')])

    def test_every_spelling_is_a_search_key(self):
        keys = {k for (k,) in self.db.execute(
            "SELECT key FROM keys JOIN words ON words.id = word_id WHERE written = '綺麗'")}
        self.assertTrue({'綺麗', '奇麗', 'きれい'} <= keys, keys)

    def test_busy_prefixes_store_the_same_top_words_a_scan_finds(self):
        prefixes = [p for (p,) in self.db.execute('SELECT DISTINCT prefix FROM prefixes')]
        self.assertIn('か', prefixes)
        for prefix in prefixes:
            stored = [w for (w,) in self.db.execute(
                'SELECT word_id FROM prefixes WHERE prefix = ? ORDER BY position', (prefix,))]
            scanned = [w for (w, _) in self.db.execute(
                """SELECT w.id, MAX(k.key = ?) AS exact FROM keys k JOIN words w ON w.id = k.word_id
                   WHERE k.key >= ? AND k.key < ? GROUP BY w.id ORDER BY exact DESC, w.rank DESC, w.id LIMIT ?""",
                (prefix, prefix, prefix + '\U0010ffff', build.PREFIX_TOP))]
            self.assertEqual(stored, scanned, prefix)
            key_count = self.db.execute(
                'SELECT count(*) FROM keys WHERE key >= ? AND key < ?', (prefix, prefix + '\U0010ffff')).fetchone()[0]
            self.assertGreater(key_count, build.PREFIX_MIN_KEYS, prefix)


    def test_examples_are_grouped_by_sense_within_the_quotas(self):
        rows = self.db.execute(
            """SELECT e.word_id, e.sense, e.basis, s.japanese FROM examples e JOIN sentences s ON s.id = e.sentence_id
               ORDER BY e.word_id, e.position""").fetchall()
        per_word, per_sense = {}, {}
        for word_id, sense, basis, japanese in rows:
            per_word[word_id] = per_word.get(word_id, 0) + 1
            if sense is not None:
                per_sense[(word_id, sense)] = per_sense.get((word_id, sense), 0) + 1
            self.assertIn(basis, examples.BASES)
            self.assertLessEqual(len(japanese), examples.MAX_LENGTH)
        self.assertLessEqual(max(per_word.values()), examples.MAX_PER_WORD)
        self.assertLessEqual(max(per_sense.values()), examples.PER_SENSE)
        dangling = self.db.execute(
            """SELECT count(*) FROM examples e WHERE e.sense IS NOT NULL AND NOT EXISTS
               (SELECT 1 FROM senses s WHERE s.word_id = e.word_id AND s.number = e.sense)""").fetchone()[0]
        self.assertEqual(dangling, 0, 'every sense an example names is listed for its word')

    def test_taberu_has_an_example_for_each_of_its_senses(self):
        word_id = self.db.execute("SELECT id FROM words WHERE written = '食べる'").fetchone()[0]
        senses = [n for (n,) in self.db.execute('SELECT number FROM senses WHERE word_id = ? ORDER BY number', (word_id,))]
        self.assertEqual(senses, [1, 2])
        covered = {n for (n,) in self.db.execute('SELECT sense FROM examples WHERE word_id = ?', (word_id,))}
        self.assertEqual(covered, {1, 2})
        first = self.db.execute(
            """SELECT s.japanese, s.english FROM examples e JOIN sentences s ON s.id = e.sentence_id
               WHERE e.word_id = ? ORDER BY e.position LIMIT 1""", (word_id,)).fetchone()
        self.assertIn('食べ', first[0])
        self.assertTrue(first[1])

    def test_metadata_records_the_sources(self):
        meta = dict(self.db.execute('SELECT key, value FROM meta'))
        self.assertEqual(meta['schema'], '4')
        self.assertEqual(meta['tatoeba'], 'sample')
        self.assertEqual(meta['kftt'], '1.0')
        self.assertEqual(meta['wiktionary'], 'sample')
        self.assertEqual(meta['cedict'], 'sample')

    def chinese_of(self, written):
        return self.db.execute(
            """SELECT s.number, s.chinese, s.chinese_source FROM senses s JOIN words w ON w.id = s.word_id
               WHERE w.written = ? ORDER BY s.number""", (written,)).fetchall()

    def test_senses_get_wiktionary_chinese_aligned_by_meaning(self):
        self.assertEqual(self.chinese_of('食べる')[0][2], chinese.WIKTIONARY)
        self.assertIn('吃', self.chinese_of('食べる')[0][1])
        self.assertIn('维持生计', self.chinese_of('食べる')[1][1])
        self.assertEqual(self.chinese_of('映画'), [(1, '电影', chinese.WIKTIONARY)])
        mouse = dict((n, zh) for n, zh, _ in self.chinese_of('マウス'))
        self.assertIsNone(mouse[1], 'the laboratory mouse is not a computer mouse')
        self.assertIn('鼠标', mouse[2])

    def test_cognates_need_overlapping_english(self):
        self.assertEqual(self.chinese_of('衝突')[0], (1, '冲突', chinese.CEDICT))
        for written, false_friend in (('勉強', '勉强'), ('手紙', '手纸')):
            self.assertNotIn(false_friend, [zh for _, zh, _ in self.chinese_of(written)], written)

    def test_chinese_and_english_glosses_find_the_word(self):
        def found(term):
            return {(w, tier) for w, tier in self.db.execute(
                'SELECT w.written, g.tier FROM glosses g JOIN words w ON w.id = g.word_id WHERE g.term = ?', (term,))}
        self.assertIn(('食べる', chinese.TIER_CHINESE), found('吃'))
        self.assertIn(('食べる', chinese.TIER_ENGLISH), found('eat'))
        self.assertIn(('映画', chinese.TIER_CHINESE), found('电影'))
        self.assertEqual(self.db.execute("SELECT simplified FROM t2s WHERE traditional = '學'").fetchone(), ('学',))

    def test_example_chinese_is_simplified_and_labelled_when_via_english(self):
        rows = self.db.execute('SELECT chinese, chinese_via FROM sentences WHERE chinese IS NOT NULL').fetchall()
        self.assertTrue(any(via == 'english' for _, via in rows))
        self.assertTrue(any(via is None for _, via in rows))
        common_traditional = set('這個們說時會麼裡來對還開們')
        self.assertFalse(any(set(zh) & common_traditional for zh, _ in rows), 'example Chinese is stored in simplified')


class ExampleMatchingTests(unittest.TestCase):
    def test_index_tokens(self):
        tokens = examples.parse_tokens('彼(かれ)[01] は 食べる{食べた}~ ログアウト~')
        self.assertEqual([(t['head'], t['reading'], t['sense'], t['surface'], t['checked']) for t in tokens], [
            ('彼', 'かれ', 1, '彼', False), ('は', None, None, 'は', False),
            ('食べる', None, None, '食べた', True), ('ログアウト', None, None, 'ログアウト', True),
        ])

    def test_text_matches_need_whole_words(self):
        runs = {run for run, _ in examples.whole_words('飛行機はあと一時間でニューヨークに着く。')}
        self.assertIn('飛行機', runs)
        self.assertIn('ニューヨーク', runs)
        self.assertNotIn('時間', runs)
        self.assertNotIn('ニュー', runs)
        self.assertTrue(examples.text_matchable('時間'))
        self.assertTrue(examples.text_matchable('テレビ'))
        self.assertFalse(examples.text_matchable('日'), 'one kanji is too ambiguous')
        self.assertFalse(examples.text_matchable('話し'), 'kana tails match inflections of other words')
        self.assertFalse(examples.text_matchable('たべる'))

    def test_gloss_guess_needs_exactly_one_overlapping_sense(self):
        senses = [(1, ['to eat']), (2, ['to live on (e.g. a salary)', 'to subsist on'])]
        self.assertEqual(examples.gloss_sense('I want to eat sushi.', senses), 1)
        self.assertEqual(examples.gloss_sense('They live on a small salary.', senses), 2)
        self.assertIsNone(examples.gloss_sense('Nice weather today.', senses))
        self.assertIsNone(examples.gloss_sense(None, senses))

    def test_every_sense_gets_one_before_any_gets_two(self):
        def candidate(i, sense, basis=examples.TAGGED):
            return {'id': i, 'sense': sense, 'basis': basis, 'japanese': 'あ' * 18, 'english': 'x',
                    'chinese': None, 'chinese_via': None, 'checked': True}
        pool = [candidate(i, 1) for i in range(1, 6)] + [candidate(10, 2), candidate(20, None, examples.UNASSIGNED)]
        chosen = examples.choose(pool, [1, 2, 3])
        self.assertEqual([(c['id'], c['sense']) for c in chosen], [(1, 1), (2, 1), (10, 2)])
        lonely = examples.choose([candidate(1, 1), candidate(20, None, examples.UNASSIGNED)], [1])
        self.assertEqual([c['id'] for c in lonely], [1, 20], 'unassigned sentences top a word up to two')


class ChineseTests(unittest.TestCase):
    def test_long_vowels_match_across_spelling_and_pronunciation(self):
        self.assertEqual(chinese.pronunciation('がっこー'), chinese.pronunciation('がっこう'))
        self.assertEqual(chinese.pronunciation('えーが'), chinese.pronunciation('えいが'))
        self.assertEqual(chinese.pronunciation('ネーサン'), chinese.pronunciation('ねえさん'))
        self.assertNotEqual(chinese.pronunciation('きのう'), chinese.pronunciation('きの'))

    def test_old_wiktionary_blocks(self):
        convert = chinese.Converter(**build.local_inputs(os.path.join(build.HERE, 'sample'))['opencc'])
        self.assertEqual(chinese._legacy('整理【せいり】\n名·他サ\n1. 整理，收拾。\n2. 清理，处理。\n人員整理\n精简人员。', convert),
                         ('せいり', ['整理，收拾', '清理，处理']))
        self.assertEqual(chinese._legacy('愛吟【あいぎん】\n名?他サ 喜欢吟诵(诗歌)。', convert), ('あいぎん', ['喜欢吟诵(诗歌)']))
        self.assertEqual(chinese._legacy('上下【じょうげ】\n上下。', convert), ('じょうげ', ['上下']))
        self.assertEqual(chinese._legacy('哀恳，哀求。', convert), (None, ['哀恳，哀求']))
        self.assertEqual(chinese.clean_gloss('名·自他サ 下降，落下。', convert), '下降，落下')
        self.assertEqual(chinese.clean_gloss(':Template:音乐 休止符', convert), '休止符')
        self.assertEqual(chinese.clean_gloss('思索，[[盘算', convert), '思索，盘算')
        self.assertEqual(chinese.clean_gloss('一下', convert), '一下')
        self.assertIsNone(chinese.clean_gloss('诘(きつ)问(もん) (kitsumon)', convert))
        self.assertEqual(chinese._spelling_prefix('【見る、視る】 看，观看。'), (('見る', '視る'), '看，观看。'))
        self.assertEqual(convert.simplified('學校'), '学校')
        self.assertEqual(convert.from_japanese('衝突'), '冲突')

    def test_search_terms(self):
        self.assertEqual(chinese.english_items('to eat (with chopsticks)'), 'eat')
        self.assertEqual(chinese.chinese_items('吃喝，饮食（古）'), ['吃喝', '饮食'])
        self.assertEqual(chinese.distinct(['直率，开放，坦率', '开放，坦率', '露骨']), ['直率，开放，坦率', '露骨'])
        terms = chinese.search_terms({1: ('吃', chinese.WIKTIONARY)}, ['饮食'], [(1, ['to eat'])], [(1, ['吃', '食'])])
        self.assertEqual(terms, [('eat', 1, chinese.TIER_ENGLISH, 0), ('吃', 1, chinese.TIER_CHINESE, 0),
                                 ('食', 1, chinese.TIER_PIVOT, 1), ('饮食', None, chinese.TIER_CHINESE, 0)])
        self.assertEqual(chinese.english_items('dog (Canis (lupus) familiaris)'), 'dog')


class SearchKeyTests(unittest.TestCase):
    def test_folds_katakana_and_width(self):
        self.assertEqual(build.search_key('コーヒー'), 'こーひー')
        self.assertEqual(build.search_key('ｺｰﾋｰ'), 'こーひー')
        self.assertEqual(build.search_key('ＡＢＣ'), 'abc')


if __name__ == '__main__':
    unittest.main()
