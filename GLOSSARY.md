# OJAD Personal

A personal, fully offline iOS app that shows Japanese pitch accent the way OJAD (Online Japanese Accent Dictionary, University of Tokyo) does, from a bundled dictionary, without audio.

## Language

**Word entry**:
One row of OJAD's 単語検索 result: a headword with its conjugated forms.
_Avoid_: Word (ambiguous with the typed query), item

**Headword**:
OJAD's 見出し語 for a word entry, e.g. `食べる・食べます`; its first part is the **lemma**.
_Avoid_: Title, midashi

**Conjugated form**:
One column of a word entry's conjugation table (辞書形, 〜ます形, …), labelled per the word's category.
_Avoid_: Katsuyo, inflection, column

**Reading**:
The kana of a conjugated form with its pitch pattern; a form can have several when OJAD lists accent variants.
_Avoid_: Variant, pronunciation

**Mora**:
The timing unit pitch is assigned to; one kana, or two for 拗音 (`きょ`).
_Avoid_: Syllable, character

**Accent nucleus**:
The last high mora before pitch falls (アクセント核), shown as `ꜜ`.
_Avoid_: Downstep, accent top

**Accent commands**:
OJAD's per-mora array (`[0,1,0]`) that drives its curve renderer: 0 low, >0 high, integers count accent commands.
_Avoid_: Curve data, pitch array

**Pitch curve**:
The F0 contour drawn from accent commands with OJAD's Fujisaki-model presets.
_Avoid_: Graph, intonation line

**Sense**:
One numbered meaning of a word in JMdict (from 1), with its English glosses; only the senses that apply to the word's spelling and reading.
_Avoid_: Meaning, definition

**Chinese gloss**:
The Simplified Chinese for a sense, from Chinese Wiktionary, or from the same-spelt Chinese word in CC-CEDICT when its English agrees (labelled 同形词). Wiktionary Chinese that fits no single sense is kept on the word.
_Avoid_: Translation, 机翻 (no machine translation is used)

**Meaning search**:
Finding Japanese words by typing a Chinese or English gloss (`吃`, `eat`) instead of the word itself; matches rank exact, then prefix, then contains, and words reached only through CC-CEDICT's English (a **pivot**) come last.
_Avoid_: Reverse lookup, translation search

**Example sentence**:
A corpus sentence (Tatoeba, or KFTT as a fallback) that uses the looked-up word, shown with its translations under the sense it illustrates.
_Avoid_: Sample

**Basis**:
How an example sentence was tied to its word and sense: named by the corpus index or JMdict, the word's only sense, guessed from the English translation, or a plain text match. The weaker ones are labelled in the UI.
_Avoid_: Confidence, source
