#!/usr/bin/env python3
"""Copy the actual Mac page scripts to Linux; don't maintain a third divergent copy."""
from pathlib import Path
import re

root = Path(__file__).resolve().parent.parent
source = (root / 'Sources/JustSayIt/CollectivIQ.swift').read_text()
target = root / 'integrations/ciq'
target.mkdir(parents=True, exist_ok=True)
for field, name in [('routeSteps', 'route.js'), ('steps', 'chat.js'), ('ddrSteps', 'ddr.js')]:
    match = re.search(r'static let ' + field + r' = #"""\n(.*?)\n"""#', source, re.S)
    if not match:
        raise ValueError('Missing script: ' + field)
    (target / name).write_text(match[1] + '\n')
store = (root / 'Sources/JustSayIt/Store.swift').read_text()
prompt = re.search(r'let ciqStandardPrompt = """\n(.*?)\n"""', store, re.S)
if not prompt:
    raise ValueError('Missing meeting prompt')
(target / 'prompt.txt').write_text(prompt[1] + '\n')
