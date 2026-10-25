"""Turn Flutter's JSON test report into concise GitHub failure annotations."""
import json
import sys
from pathlib import Path


def main():
    lines = Path(sys.argv[1]).read_text(errors='replace').splitlines()
    names = {}
    errors = {}
    failures = []
    for line in lines:
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
        elif kind == 'testDone' and event.get('result') not in ('success', 'skipped'):
            failures.append(event.get('testID'))
    if not failures:
        print('::error::Flutter tests failed before reporting an individual case.')
        for test_id, detail in list(errors.items())[:8]:
            title = names.get(test_id, 'Unknown test')
            print(f'::error::Flutter error event: {title}: {detail}')
        if not errors:
            for line in lines[-6:]:
                detail = line[:400].replace('%', '%25').replace('\r', '%0D').replace('\n', '%0A')
                print(f'::error::Flutter test tail: {detail}')
    for test_id in failures:
        title = names.get(test_id, 'Unknown test').replace('%', '%25').replace('\r', '%0D').replace('\n', '%0A')
        detail = errors.get(test_id, '').replace('%', '%25').replace('\r', '%0D').replace('\n', '%0A')
        print(f'::error::Flutter test failed: {title}: {detail}')


if __name__ == '__main__':
    main()
