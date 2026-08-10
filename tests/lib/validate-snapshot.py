"""Checks the shipped snapshot without building a Drupal site.

`tests/check.sh` is the real verification, but it needs a disposable site and a
destructive install, so nobody runs it before a commit. Most of what has
actually regressed here does not need a site to see: a binary nobody claims is
never copied into `public://`, a declared image dimension that disagrees with
the JPEG beside it, a `component_version` pinned to a version the wrapper no
longer considers active, an enum value that shipped as an integer. All of that
is readable from the files themselves in about a second.

Usage:
    python3 tests/lib/validate-snapshot.py <repo root> [--allow <file>]

Without `--allow`, every problem counts and the exit code is non-zero if there
is one. With it, problems whose line appears in the allowlist are reported as
`known` and only new ones fail -- and an allowlist line that matches nothing is
itself an error, so the file cannot outlive the problems it describes.
"""

import pathlib
import re
import sys

import yaml
from PIL import Image

# The same table `tests/check.sh` uses for its own version of the description
# assertion. Kept identical so the two cannot disagree about what "twenty-one"
# means.
WORDS = {
    'one': 1, 'two': 2, 'three': 3, 'four': 4, 'five': 5, 'six': 6,
    'seven': 7, 'eight': 8, 'nine': 9, 'ten': 10, 'eleven': 11, 'twelve': 12,
    'thirteen': 13, 'fourteen': 14, 'fifteen': 15, 'sixteen': 16,
    'seventeen': 17, 'eighteen': 18, 'nineteen': 19, 'twenty': 20,
    'twenty-one': 21, 'twenty-two': 22,
}

CHECKS = [
    'yaml-parses',
    'binary-has-entity',
    'entity-has-binary',
    'image-dimensions',
    'component-ids-resolve',
    'version-pins-are-active',
    'enum-inputs-are-strings',
    'recipe-description-counts',
]


def load(path):
    """Parsed YAML, or None if it does not parse. `yaml-parses` reports those."""
    try:
        return yaml.safe_load(path.read_text())
    except Exception:
        return None


def rel(root, path):
    return str(path.relative_to(root))


def yaml_files(root):
    for directory in ('config', 'content'):
        yield from sorted((root / directory).rglob('*.yml'))
    yield root / 'recipe.yml'


def trees(root):
    """Every component tree that ships, as (file, item) pairs.

    Three shapes: pages keep a list under `default.components`, page regions and
    content templates keep a mapping under `component_tree`.
    """
    for page in sorted((root / 'content' / 'canvas_page').glob('*.yml')):
        data = load(page) or {}
        for item in (data.get('default') or {}).get('components') or []:
            yield page, item
    for pattern in ('canvas.page_region.*.yml', 'canvas.content_template.*.yml'):
        for config in sorted((root / 'config').glob(pattern)):
            data = load(config) or {}
            for item in (data.get('component_tree') or {}).values():
                yield config, item


def file_entities(root):
    """uuid -> (entity path, binary path), for the file entities that ship."""
    entities = {}
    directory = root / 'content' / 'file'
    for entity in sorted(directory.glob('*.yml')):
        data = load(entity)
        if not data:
            continue
        uuid = (data.get('_meta') or {}).get('uuid')
        uri = ((data.get('default') or {}).get('uri') or [{}])[0].get('value', '')
        if uuid and uri.startswith('public://'):
            entities[uuid] = (entity, directory / uri[len('public://'):])
    return entities


def image_values(node):
    """Every mapping carrying width, height and a file `entity` reference."""
    if isinstance(node, dict):
        if {'width', 'height', 'entity'} <= node.keys():
            yield node
        for value in node.values():
            yield from image_values(value)
    elif isinstance(node, list):
        for value in node:
            yield from image_values(value)


def check_yaml_parses(root):
    return [rel(root, p) for p in yaml_files(root) if load(p) is None]


def check_binary_has_entity(root):
    directory = root / 'content' / 'file'
    claimed = {b.name for _, b in file_entities(root).values()}
    return [p.name for p in sorted(directory.iterdir())
            if p.suffix != '.yml' and p.name not in claimed]


def check_entity_has_binary(root):
    found = []
    for entity in sorted((root / 'content' / 'file').glob('*.yml')):
        data = load(entity)
        if not data:
            continue
        default = data.get('default') or {}
        uri = (default.get('uri') or [{}])[0].get('value', '')
        binary = root / 'content' / 'file' / uri[len('public://'):]
        if not uri.startswith('public://') or not binary.exists():
            found.append('%s claims %s which does not ship' % (entity.name, uri))
            continue
        declared = (default.get('filesize') or [{}])[0].get('value')
        actual = binary.stat().st_size
        if declared is not None and int(declared) != actual:
            found.append('%s declares filesize %d, %s is %d bytes'
                         % (entity.name, int(declared), binary.name, actual))
    return found


def check_image_dimensions(root):
    entities = file_entities(root)
    found = []
    for directory in ('media', 'node'):
        for path in sorted((root / 'content' / directory).glob('*.yml')):
            for value in image_values(load(path) or {}):
                target = entities.get(value['entity'])
                if not target or not target[1].exists():
                    continue
                with Image.open(target[1]) as image:
                    actual = image.size
                if (value['width'], value['height']) != actual:
                    found.append('%s %s declared %dx%d actual %dx%d'
                                 % (path.name, target[1].name, value['width'],
                                    value['height'], actual[0], actual[1]))
    return found


def check_component_ids_resolve(root):
    found = set()
    for path, item in trees(root):
        component_id = item.get('component_id', '')
        if not component_id.startswith('js.'):
            continue
        name = component_id[len('js.'):]
        for config in ('canvas.component.js.%s.yml' % name,
                       'canvas.js_component.%s.yml' % name):
            if not (root / 'config' / config).exists():
                found.add('%s %s has no config/%s' % (path.name, component_id, config))
    return sorted(found)


def check_version_pins_are_active(root):
    found = []
    for path, item in trees(root):
        pinned = item.get('component_version')
        component_id = item.get('component_id', '')
        if not pinned or not component_id.startswith('js.'):
            continue
        wrapper = load(root / 'config' / ('canvas.component.%s.yml' % component_id))
        if not wrapper:
            continue
        active = wrapper.get('active_version')
        if pinned != active:
            found.append('%s %s pinned %s active %s'
                         % (path.name, component_id, pinned, active))
    return found


def check_enum_inputs_are_strings(root):
    schemas = {}
    for config in sorted((root / 'config').glob('canvas.js_component.*.yml')):
        data = load(config) or {}
        schemas[data.get('machineName')] = data.get('props') or {}
    found = []
    for path, item in trees(root):
        component_id = item.get('component_id', '')
        if not component_id.startswith('js.'):
            continue
        props = schemas.get(component_id[len('js.'):], {})
        for prop, value in (item.get('inputs') or {}).items():
            schema = props.get(prop)
            if not isinstance(schema, dict) or 'enum' not in schema:
                continue
            if schema.get('type') == 'string' and not isinstance(value, str):
                found.append('%s %s.%s is %s %r'
                             % (path.name, component_id, prop,
                                type(value).__name__, value))
            elif isinstance(value, str) and value not in schema['enum']:
                found.append('%s %s.%s is %r, not in the enum'
                             % (path.name, component_id, prop, value))
    return found


def check_recipe_description_counts(root):
    said = ((load(root / 'recipe.yml') or {}).get('description') or '').lower()
    found = []
    for noun, actual in (
        ('components', len(list((root / 'config').glob('canvas.js_component.*.yml')))),
        ('pages', len(list((root / 'content' / 'canvas_page').glob('*.yml')))),
    ):
        if not any(WORDS.get(word) == actual and '%s %s' % (word, noun) in said
                   for word in WORDS):
            match = re.search(r'([a-z-]+) %s' % noun, said)
            found.append('recipe.yml says %r %s, %d ship'
                         % (match.group(1) if match else '?', noun, actual))
    return found


def main(argv):
    root = pathlib.Path(argv[1]).resolve()
    allow = pathlib.Path(argv[3]) if len(argv) > 3 and argv[2] == '--allow' else None

    results = {name: globals()['check_' + name.replace('-', '_')](root)
               for name in CHECKS}
    lines = ['%s: %s' % (name, problem)
             for name in CHECKS for problem in results[name]]

    if allow is None:
        for line in lines:
            print(line)
        print()
        for name in CHECKS:
            count = len(results[name])
            print('%s %s' % (name.ljust(26),
                             'ok' if not count
                             else '%d problem%s' % (count, 's' if count > 1 else '')))
        print('\n%d problems' % len(lines))
        return 1 if lines else 0

    allowed = [l for l in allow.read_text().splitlines()
               if l.strip() and not l.startswith('#')]
    new = [l for l in lines if l not in allowed]
    # An allowlist line that matches nothing describes a past, which is how an
    # allowlist turns into a place defects go to be forgotten.
    stale = [l for l in allowed if l not in lines]
    for line in new:
        print('NEW   %s' % line)
    for line in stale:
        print('STALE %s (allowlisted but no longer found -- delete this line)' % line)
    print('%d known, %d new%s' % (len(lines) - len(new), len(new),
                                  ', %d stale' % len(stale) if stale else ''))
    return 1 if new or stale else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
