"""Stdin-only cap-at-write evidence sink. No subprocess or process control."""
import os
from pathlib import Path
import sys

CAP = 1024**2
NAMES = {'helper-tests.log', 'dependency-prepare.log', 'lifecycle-compile.log', 'lifecycle-test.log'}


def exclusive(path):
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
    return os.fdopen(fd, 'wb')


def capture(source, target):
    target = Path(target)
    if target.name not in NAMES or target.parent.is_symlink() or not target.parent.is_dir():
        raise ValueError('Only fixed evidence log names in an existing regular directory')
    marker = target.with_name(target.name + '.overflow.json')
    if target.exists() or target.is_symlink() or marker.exists() or marker.is_symlink():
        raise ValueError('Refuse evidence overwrite or redirection')
    retained = 0
    overflow = False
    with exclusive(target) as output:
        while True:
            block = source.read(16384)
            if not block:
                break
            keep = block[:max(0, CAP - retained)]
            if keep:
                output.write(keep)
                output.flush()
                retained += len(keep)
            if len(keep) != len(block) and not overflow:
                # Write immediately, including when a timeout prevents EOF.
                with exclusive(marker) as flag:
                    flag.write(b'{"overflow":true,"retainedLimit":1048576}\n')
                overflow = True
    return 1 if overflow else 0


def main():
    try:
        if len(sys.argv) != 2:
            raise ValueError('One fixed evidence destination required')
        evidence = Path(os.environ['EVIDENCE'])
        temp = Path(os.environ['RUNNER_TEMP'])
        expected = temp / 'neon532-evidence'
        if (evidence != expected or evidence.is_symlink()
                or evidence.resolve() != temp.resolve() / 'neon532-evidence'):
            raise ValueError('Evidence directory differs from hosted fixed path')
        target = Path(sys.argv[1])
        if target.parent != evidence:
            raise ValueError('Destination outside evidence directory')
        return capture(sys.stdin.buffer, target)
    except Exception as error:
        print('log-sink-failed: ' + type(error).__name__, file=sys.stderr)
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
