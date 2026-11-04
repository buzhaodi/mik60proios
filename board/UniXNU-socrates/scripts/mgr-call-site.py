#!/usr/bin/env python3
"""Relocate the sheng_pmgr_run call for this board, or put it back.

The sheng-platform-power patch calls sheng_pmgr_run right after
bsd_bufferinit, which on socrates is more than 500 lines before
IOKitBSDInit - the IORegistry platform does not exist yet and the console
is not attached either (panics paint garbage; first-boot hardware evidence
2026-11-04). `move` relocates the block to just before IOKitBSDInit;
`restore` puts it back so the patch series re-applies cleanly on repeated
builds (the boot-progress patch has a hunk in the IOKit area whose context
the moved block would break).
"""
import re
import sys

PATH = '.cache/xnu-work/bsd/kern/bsd_init.c'
BLOCK = (
    '\n#if defined(XNU_SHENG_PMGR) && XNU_SHENG_PMGR\n'
    '\textern void sheng_pmgr_run(void);\n'
    '\tboot_progress_stage("original PMGR nub start");\n'
    '\tsheng_pmgr_run();\n'
    '\tboot_progress_stage("original PMGR nub returned");\n'
    '#endif\n'
)
OLD_ANCHOR = '\tbsd_bufferinit();\n'
NEW_ANCHOR = '\tkern_return_t result = IOKitBSDInit();'
MARKER = ('\t/* moved from after bsd_bufferinit: pre-IOKit the registry platform\n'
          '\t * does not exist and panics cannot paint (mgr-call-site.py) */\n')


def is_moved(s):
    return 'original PMGR nub start' in s and \
        s.index('original PMGR nub start') < s.index('IOKitBSDInit()')


def main():
    action = sys.argv[1] if len(sys.argv) > 1 else 'move'
    s = open(PATH).read()
    if action == 'move':
        if is_moved(s):
            print('sheng_pmgr_run already before IOKitBSDInit')
            return
        assert s.count(BLOCK) == 1, 'PMGR block not found at the patched position'
        s = s.replace(BLOCK, '', 1)
        assert s.count(NEW_ANCHOR) == 1, 'expected exactly one IOKitBSDInit call'
        s = s.replace(NEW_ANCHOR, BLOCK + '\n' + MARKER + NEW_ANCHOR, 1)
        print('sheng_pmgr_run moved to just before IOKitBSDInit')
    elif action == 'restore':
        if not is_moved(s):
            print('sheng_pmgr_run already at the patched position')
            return
        # tolerate both marker layouts (the old heredoc move left no blank line
        # between the block and the marker)
        m = re.search(re.escape(BLOCK) + r'(?:\n\t/\* moved[^\n]*\n)?(?:\t \*[^\n]*\n)?', s)
        assert m, 'moved PMGR block not found for restore'
        s = s[:m.start()] + s[m.end():]
        assert s.count(OLD_ANCHOR) == 1, 'expected exactly one bsd_bufferinit call'
        s = s.replace(OLD_ANCHOR, OLD_ANCHOR + BLOCK, 1)
        print('sheng_pmgr_run restored to after bsd_bufferinit')
    else:
        raise SystemExit(f'usage: {sys.argv[0]} [move|restore]')
    open(PATH, 'w').write(s)


if __name__ == '__main__':
    main()
