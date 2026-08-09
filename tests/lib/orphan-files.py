"""Counts file entities in a recipe's content/file whose bytes are missing.

Shipped without its binary, a file entity makes the importer log a warning and
leave a managed row pointing at nothing. Nothing else in the suite can see it,
because no media references it and the media count is unaffected.

Kept as a file rather than inline in check.sh: the first two attempts were a
sed expression that matched nothing and a heredoc that silently swallowed the
twenty assertions after it.
"""

import pathlib
import re
import sys

directory = pathlib.Path(sys.argv[1])
binaries = {p.name for p in directory.iterdir() if p.suffix != '.yml'}
missing = 0
for entity in sorted(directory.glob('*.yml')):
    text = entity.read_text()
    match = re.search(r"value: '?public://([^'\n]+)'?", text)
    if not match or match.group(1) not in binaries:
        missing += 1
        continue
    # A binary replaced without re-running the export leaves the entity
    # claiming a size the bytes do not have.
    declared = re.search(r'filesize:\n\s+-\n\s+value: (\d+)', text)
    if declared and int(declared.group(1)) != (directory / match.group(1)).stat().st_size:
        missing += 1
print(missing)
