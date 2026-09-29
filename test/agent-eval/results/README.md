# Raw answers from the first experiment

The model answers behind the table in `../README.md`, kept so they can be re-graded (`grade.py --set easy|hard results/<set>/*.md`) or
inspected. File names are `<model>-<A|B>-<run>.md`: **A** = control prompt (no primer), **B** = primer version 1 prepended.
`easy/` used the first prompt wording, whose lack of a "self-contained" rule let two haiku solutions call a helper from another task
(`parse-pairs`); `hard/` used the corrected wording that `make_prompt.py` now produces. Models: haiku and sonnet.
