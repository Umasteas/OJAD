# OJAD Personal

A personal iOS app that looks up Japanese pitch accent on OJAD (Online Japanese Accent Dictionary, University of Tokyo) and redraws OJAD's pitch curves natively, without audio.

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

**Example sentence**:
A Japanese sentence from Tatoeba containing the looked-up word, shown with its translation.
_Avoid_: Sample

**Sentence analysis**:
スズキクン's split of a sentence into accent phrases with their accent commands, requested only when the user opens an example sentence. `phrasing` appears only where it names OJAD's own endpoint (`/ojad/phrasing/index`).
_Avoid_: Prosody
