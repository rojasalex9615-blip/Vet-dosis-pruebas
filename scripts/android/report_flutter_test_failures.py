"""Turn Flutter's JSON test report into concise GitHub failure annotations."""
import json
import sys
from pathlib import Path


def main():
    names = {}
    errors = {}
    failures = []
    for line in Path(sys.argv[1]).read_text(errors='replace').splitlines():
        try:
            event = json.loads(line)
        except json.JSONDecodeError:
            continue
        kind = event.get('type')
        if kind == 'testStart':
            test = event.get('test') or {}
            names[test.get('id')] = str(test.get('name', 'Unknown test'))
        elif kind == 'error':
            errors[event.get('testID')] = str(event.get('error', '')).splitlines()[0][:250]
        elif kind == 'testDone' and event.get('result') == 'failure':
            failures.append(event.get('testID'))
    if not failures:
        print('::error::Flutter tests failed before reporting an individual case.')
    for test_id in failures:
        title = names.get(test_id, 'Unknown test').replace('%', '%25').replace('\r', '%0D').replace('\n', '%0A')
        detail = errors.get(test_id, '').replace('%', '%25').replace('\r', '%0D').replace('\n', '%0A')
        print(f'::error::Flutter test failed: {title}: {detail}')


if __name__ == '__main__':
    main()
