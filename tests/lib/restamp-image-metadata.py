"""Rewrites what the shipped content claims about the shipped images.

Three numbers are declared about every photograph -- `filesize` in its file
entity, and `width`/`height` in every image field that references it -- and all
three have to agree with the bytes. Eleven of thirty-seven dimensions did not:
Drupal writes them into the rendered width/height attributes and into the box
Canvas reserves before the file loads, so a portrait box reserved for a
landscape photograph is a guaranteed layout shift on the largest element of the
page. Re-encoding the set invalidates all of them at once, which is why this
exists as a tool rather than as a careful hand pass.

It edits only those numbers. A YAML round-trip would reformat all 37 files and
bury the real change, so this reads the text the same way orphan-files.py does.

Usage:
    python3 tests/lib/restamp-image-metadata.py content [--dry-run]
"""

import pathlib
import re
import sys

from PIL import Image

FILESIZE = re.compile(r'(filesize:\n\s+-\n\s+value: )(\d+)')
DIMENSIONS = re.compile(r'(width: )(\d+)(\n\s+height: )(\d+)(\n\s+entity: )([0-9a-f-]{36})')


def shipped_files(content):
    """uuid -> path of the binary that file entity claims."""
    files = {}
    for entity in sorted((content / 'file').glob('*.yml')):
        text = entity.read_text()
        uuid = re.search(r'uuid: ([0-9a-f-]{36})', text)
        uri = re.search(r"value: '?public://([^'\n]+)'?", text)
        if uuid and uri:
            files[uuid.group(1)] = content / 'file' / uri.group(1)
    return files


def main(argv):
    content = pathlib.Path(argv[1])
    dry_run = '--dry-run' in argv
    files = shipped_files(content)
    changes = []
    unresolved = []

    for entity in sorted((content / 'file').glob('*.yml')):
        text = entity.read_text()
        uri = re.search(r"value: '?public://([^'\n]+)'?", text)
        if not uri:
            continue
        binary = content / 'file' / uri.group(1)
        if not binary.exists():
            unresolved.append('%s claims %s which does not ship' % (entity.name, uri.group(1)))
            continue

        def restamp(match, size=binary.stat().st_size):
            if int(match.group(2)) != size:
                changes.append('%s filesize %s -> %d' % (entity.name, match.group(2), size))
            return '%s%d' % (match.group(1), size)

        updated = FILESIZE.sub(restamp, text)
        if updated != text and not dry_run:
            entity.write_text(updated)

    for directory in ('media', 'node'):
        for path in sorted((content / directory).glob('*.yml')):
            text = path.read_text()

            def restamp(match):
                binary = files.get(match.group(6))
                if binary is None or not binary.exists():
                    unresolved.append('%s references %s, which no shipped file entity claims'
                                      % (path.name, match.group(6)))
                    return match.group(0)
                with Image.open(binary) as image:
                    width, height = image.size
                if (int(match.group(2)), int(match.group(4))) != (width, height):
                    changes.append('%s %s %sx%s -> %dx%d'
                                   % (path.name, binary.name, match.group(2),
                                      match.group(4), width, height))
                return '%s%d%s%d%s%s' % (match.group(1), width, match.group(3),
                                         height, match.group(5), match.group(6))

            updated = DIMENSIONS.sub(restamp, text)
            if updated != text and not dry_run:
                path.write_text(updated)

    for line in changes:
        print(line)
    for line in unresolved:
        print('UNRESOLVED %s' % line, file=sys.stderr)
    print('%d change%s%s' % (len(changes), '' if len(changes) == 1 else 's',
                             ' (dry run, nothing written)' if dry_run else ''))
    return 1 if unresolved else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
