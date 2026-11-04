"""python3 -m unittest discover -s scripts/dictionary -p 'test_*.py'"""

import os
import sqlite3
import tempfile
import unittest

import build

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


class SearchKeyTests(unittest.TestCase):
    def test_folds_katakana_and_width(self):
        self.assertEqual(build.search_key('コーヒー'), 'こーひー')
        self.assertEqual(build.search_key('ｺｰﾋｰ'), 'こーひー')
        self.assertEqual(build.search_key('ＡＢＣ'), 'abc')


if __name__ == '__main__':
    unittest.main()
